function [EEG, options] = DefineBins(input, opts)
%% DefineBins  Assign events to ERP bins with an event-selection language.
%
% DefineBins replaces the ERPLAB EVENTLIST + BINLISTER step with a small,
% readable event-selection language. Each statement defines one bin as a
% predicate over the events in the recording; every event that satisfies the
% predicate becomes a time-locked point for that bin. Nothing is reshaped
% here (the data stays CONTINUOUS): DefineBins only tags events with their
% bin membership, so a later EpochBins step can cut the epochs and an
% AverageBins step can average per bin.
%
% Signature (Alakazam transformation contract):
%   [EEG, options] = DefineBins(input)        % interactive: prompt for a script
%   [EEG, options] = DefineBins(input, opts)  % replay: opts is a stored struct
%
% The returned OPTIONS struct carries .script (the text the analyst typed) and
% .bins (the compiled query plan). On replay the compiled plan is evaluated
% directly against the new dataset's events - no re-parsing, no eval of text.
%
%% LANGUAGE
%
% One statement per bin (the ':' after the label is optional):
%
%   bin <n> "<label>" : <expr>
%
% <expr> is a boolean combination (and / or / not, grouped with parentheses;
% 'and' between two adjacent terms is optional) of two kinds of terms, both
% evaluated relative to a candidate event e:
%
%   * anchor     a marker code (or set of codes), true when e's own marker
%                matches one of them. Codes are integers (112) or quoted text
%                markers ("S112"); a quoted marker may use wildcards, ? for
%                any single character and * for any run ("s??" matches s + two
%                characters). A set of alternatives is written either
%                pipe-separated (112|122) or as a braced list, which reads
%                well for many markers: {"s11" "s22" "s33" "s44"} (elements
%                separated by spaces and/or commas). Both forms may be used
%                anywhere a code appears, including inside next(...)/any(...).
%
%   * relation   a constraint on a neighbouring event, measured as a signed
%                delay from e (positive = later):
%                   next(code)                the nearest following event of
%                                             that code (skipping others)
%                   prev(code)                the nearest preceding event
%                   adjacent(code)            the immediately next event must
%                                             be that code
%                   any(code) within (lo,hi]  some event of that code exists
%                                             in the window
%                Any relation may be constrained by a window:
%                   ... within (200,1200] ms
%                Interval notation is explicit about open/closed bounds and
%                takes an optional unit (ms, the default, or samples). Windows
%                are signed, so [-1200,-200) means "before".
%
% A single optional 'epoch' statement gives the window to cut around every
% matched event. It is written once and applies to ALL bins (they share one
% window). With it, DefineBins returns a segmented (channels x time x trials)
% dataset that plots in EpochView; without it the data stays continuous and
% only the bin tags are added.
%
% Example (the N400-style case: a target whose response falls in a plausible
% reaction-time window):
%
%   epoch [-200,800] ms
%   bin 1 "Related"   : 112 and next(118) within (200,1200] ms
%   bin 2 "Unrelated" : 122 and next(118) within (200,1200] ms
%   bin 3 "No response": (112|122) and not next(118) within (0,2000] ms
%
% Lines beginning with % or # are comments. See bin_language.md for the full
% reference.
%
%% RESULT
%
% Adds to EEG:
%   EEG.bindesc(b) : struct per bin with fields index, label, script, plan,
%                    events (indices into EEG.event), rt (per-event delay to
%                    the captured neighbour, ms; NaN when none), n, and - once
%                    epoched - trials (indices into the epoch stack).
%   EEG.event(i).bini : row vector of bin numbers this event belongs to
%                    (ERPLAB-style; an event may be in several bins).
% With an 'epoch' statement it also segments EEG.data into
% channels x time x trials, sets DataFormat = 'EPOCHED', fills EEG.times and
% EEG.epoch (one entry per trial, tagged with its bins).
%
% See also: Epoch, Segmentation, Average.

%#ok<*AGROW>

    %% Guard input
    if nargin < 1
        throw(MException('Alakazam:DefineBins', ...
            'Problem in DefineBins: No Data Supplied'));
    end

    EEG = input;

    %% Mode: interactive (Init) or replay (stored options struct)
    if nargin == 1
        options = 'Init';
    else
        options = opts;
    end
    interactive = (ischar(options) || isstring(options)) ...
        && strcmpi(string(options), "Init");

    if interactive
        script = promptForScript();
        spec   = parseSpec(script);              % may throw parse errors
        % Remember the last valid script so it prefills the editor next time.
        setpref('Alakazam', 'DefineBinsScript', script);
        options = struct('script', script, 'bins', spec.bins, 'epoch', spec.epoch);
    else
        if ~isstruct(options) || ~isfield(options, 'bins')
            throw(MException('Alakazam:DefineBins', ...
                'Problem in DefineBins: invalid stored options'));
        end
        spec.bins = options.bins;
        if isfield(options, 'epoch'); spec.epoch = options.epoch; else; spec.epoch = []; end
    end
    bins = spec.bins;

    if isempty(bins)
        throw(MException('Alakazam:DefineBins', ...
            'Problem in DefineBins: no bins defined'));
    end

    %% Validate events
    if ~isfield(EEG, 'event') || isempty(EEG.event) ...
            || ~isfield(EEG.event, 'type') || ~isfield(EEG.event, 'latency')
        throw(MException('Alakazam:DefineBins', ...
            'Problem in DefineBins: dataset has no usable events'));
    end

    %% Latency-ordered view of the events
    [ctx, order] = buildContext(EEG);
    nEv = numel(order);

    %% Evaluate each bin predicate against every event
    membership = cell(1, nEv);                   % per ordered position
    bindesc = struct('index', {}, 'label', {}, 'script', {}, ...
                     'plan', {}, 'events', {}, 'rt', {}, 'n', {});

    for b = 1:numel(bins)
        matchedOrig = [];
        rts = [];
        for p = 1:nEv
            [tf, capLat] = evalNode(bins(b).expr, p, ctx);
            if tf
                matchedOrig(end+1) = order(p);
                if isnan(capLat)
                    rts(end+1) = NaN;
                else
                    rts(end+1) = (capLat - ctx.lat(p)) / ctx.srate * 1000;
                end
                membership{p}(end+1) = bins(b).index;
            end
        end
        bindesc(b).index  = bins(b).index;
        bindesc(b).label  = bins(b).label;
        bindesc(b).script = bins(b).text;
        bindesc(b).plan   = bins(b).expr;
        bindesc(b).events = matchedOrig;
        bindesc(b).rt     = rts;
        bindesc(b).n      = numel(matchedOrig);
    end

    %% Tag events with their bin membership (ERPLAB-style .bini)
    for p = 1:nEv
        EEG.event(order(p)).bini = membership{p};
    end

    %% Cut epochs when an 'epoch' window was given, so the result plots as an
    %  epoched dataset (EpochView). Without it, the data stays continuous and
    %  only the bin tags are added.
    if ~isempty(spec.epoch)
        [EEG, bindesc] = cutEpochs(EEG, bindesc, spec.epoch);
    end
    EEG.bindesc = bindesc;

    %% Interactive summary
    if interactive
        reportBins(bindesc, EEG);
    end
end

% ======================================================================= %
%  Interactive prompt
% ======================================================================= %
function script = promptForScript()
    template = [ ...
        '% Codes are markers; ? matches any single character; { } lists alternatives.' newline ...
        '% Relations: next(c) prev(c) adjacent(c) any(c) within (lo,hi] unit.'         newline ...
        '% Combine with and / or / not (adjacent terms are and-ed). ''epoch'' segments.' newline ...
        'epoch [-200,800] ms'                                                          newline ...
        'bin 1 "Related"   {"s11" "s22" "s33" "s44" "s55"} and next("S201") within (200,1200] ms' newline ...
        'bin 2 "Unrelated" "s??" not {"s11" "s22" "s33" "s44" "s55"} and next("S201") within (200,1200] ms' ];

    % Prefill with the last script the user ran (remembered across sessions),
    % falling back to the built-in template on first use.
    default = getpref('Alakazam', 'DefineBinsScript', template);

    answer = inputdlg('Bin definitions:', 'DefineBins', [20 90], {default});
    if isempty(answer)
        throw(MException('Alakazam:DefineBins', 'DefineBins cancelled.'));
    end
    script = answer{1};
    if ischar(script) && size(script, 1) > 1
        % inputdlg returns a char matrix for multi-line input; join to a
        % single newline-separated row.
        script = strjoin(cellstr(script), newline);
    end
    script = char(script);
end

function reportBins(bindesc, EEG)
    lines = strings(0, 1);
    for b = 1:numel(bindesc)
        d = bindesc(b);
        valid = ~isnan(d.rt);
        if any(valid)
            rtStr = sprintf('  (mean delay %.0f ms)', mean(d.rt(valid)));
        else
            rtStr = '';
        end
        lines(end+1) = sprintf('bin %d "%s": %d events%s', ...
            d.index, d.label, d.n, rtStr);
    end
    if isfield(EEG, 'DataFormat') && strcmpi(EEG.DataFormat, 'EPOCHED')
        lines(end+1) = sprintf('--> segmented: %d epochs x %d samples', ...
            EEG.trials, EEG.pnts);
    end
    helpdlg(char(strjoin(lines, newline)), 'DefineBins: bins created');
end

% ======================================================================= %
%  Event context
% ======================================================================= %
function [ctx, order] = buildContext(EEG)
    ev  = EEG.event;
    n   = numel(ev);
    lat = zeros(1, n);
    typ = strings(1, n);
    for i = 1:n
        L = ev(i).latency;
        if isempty(L); L = NaN; else; L = double(L); end
        lat(i) = L;
        typ(i) = canonType(ev(i).type);
    end
    [latS, order] = sort(lat);
    ctx.lat   = latS;
    ctx.typ   = typ(order);
    ctx.srate = EEG.srate;
end

function s = canonType(t)
    if isnumeric(t)
        s = num2str(t);
    else
        s = char(string(t));
    end
    s = string(regexprep(strtrim(s), '\s+', ''));
end

function tf = matchCode(typStr, codes)
    for i = 1:numel(codes)
        c = codes(i);
        if contains(c, '?') || contains(c, '*')
            % Wildcard marker: ? = any one character, * = any run.
            if ~isempty(regexpi(typStr, wildcardToRegex(c), 'once'))
                tf = true; return;
            end
        else
            if strcmpi(typStr, c); tf = true; return; end
            va = str2double(typStr); vc = str2double(c);
            if ~isnan(va) && ~isnan(vc) && va == vc; tf = true; return; end
        end
    end
    tf = false;
end

function rx = wildcardToRegex(c)
    rx = regexptranslate('escape', char(c));   % escape regex metacharacters
    rx = strrep(rx, '\?', '.');                % ? -> any single character
    rx = strrep(rx, '\*', '.*');               % * -> any run of characters
    rx = ['^' rx '$'];
end

% ======================================================================= %
%  Evaluator
% ======================================================================= %
function [tf, cap] = evalNode(node, p, ctx)
    switch node.op
        case 'anchor'
            tf  = matchCode(ctx.typ(p), node.codes);
            cap = NaN;
        case 'rel'
            [tf, cap] = evalRel(node, p, ctx);
        case 'not'
            tf  = ~evalNode(node.kid, p, ctx);
            cap = NaN;
        case 'and'
            tf = true; cap = NaN;
            for k = 1:numel(node.kids)
                [t, c] = evalNode(node.kids{k}, p, ctx);
                tf = tf && t;
                if isnan(cap) && ~isnan(c); cap = c; end
            end
            if ~tf; cap = NaN; end
        case 'or'
            tf = false; cap = NaN;
            for k = 1:numel(node.kids)
                [t, c] = evalNode(node.kids{k}, p, ctx);
                if t
                    tf = true;
                    if isnan(cap) && ~isnan(c); cap = c; end
                end
            end
        otherwise
            throw(MException('Alakazam:DefineBins', ...
                'Internal error: unknown node ''%s''', node.op));
    end
end

function [tf, cap] = evalRel(node, p, ctx)
    n     = numel(ctx.lat);
    codes = node.codes;
    iv    = node.interval;
    found = 0;

    switch node.quant
        case 'next'
            for q = p+1:n
                if matchCode(ctx.typ(q), codes); found = q; break; end
            end
        case 'prev'
            for q = p-1:-1:1
                if matchCode(ctx.typ(q), codes); found = q; break; end
            end
        case 'adjacent'
            if p+1 <= n && matchCode(ctx.typ(p+1), codes); found = p+1; end
        case 'any'
            for q = 1:n
                if q ~= p && matchCode(ctx.typ(q), codes) ...
                        && inInterval(delta(q, p, ctx, iv), iv)
                    found = q; break;
                end
            end
    end

    tf  = false;
    cap = NaN;
    if found > 0
        if strcmp(node.quant, 'any') || isempty(iv) ...
                || inInterval(delta(found, p, ctx, iv), iv)
            tf  = true;
            cap = ctx.lat(found);
        end
    end
end

function d = delta(q, p, ctx, iv)
    d = ctx.lat(q) - ctx.lat(p);
    if isempty(iv) || ~strcmp(iv.unit, 'samples')
        d = d / ctx.srate * 1000;   % ms
    end
end

function tf = inInterval(d, iv)
    if iv.loOpen; loOK = d > iv.lo; else; loOK = d >= iv.lo; end
    if iv.hiOpen; hiOK = d < iv.hi; else; hiOK = d <= iv.hi; end
    tf = loOK && hiOK;
end

% ======================================================================= %
%  Epoching
% ======================================================================= %
function [EEG, bindesc] = cutEpochs(EEG, bindesc, win)
%CUTEPOCHS  Cut a chan x time x trials stack around every matched anchor.
%   The union of all bins' matched events becomes the trial set (an event in
%   several bins is one trial carrying several bin tags). Windows that run off
%   either end of the recording are padded with NaN. Produces an EPOCHED
%   dataset that plots with EpochView and can later be averaged per bin.
    if ~isfield(EEG, 'data') || isempty(EEG.data)
        throw(MException('Alakazam:DefineBins', ...
            'epoch requested but the dataset has no continuous data.'));
    end
    if ~ismatrix(EEG.data) || (isfield(EEG, 'DataFormat') && ...
            strcmpi(EEG.DataFormat, 'EPOCHED'))
        throw(MException('Alakazam:DefineBins', ...
            'epoch requested but the data is already epoched.'));
    end

    srate = EEG.srate;
    if strcmpi(win.unit, 'samples')
        loS = round(win.lo);  hiS = round(win.hi);
    else
        loS = round(win.lo / 1000 * srate);
        hiS = round(win.hi / 1000 * srate);
    end
    pnts = hiS - loS;
    if pnts <= 0
        throw(MException('Alakazam:DefineBins', ...
            'epoch window is empty (%g to %g %s).', win.lo, win.hi, win.unit));
    end

    allEvents = unique([bindesc.events]);
    if isempty(allEvents)
        throw(MException('Alakazam:DefineBins', ...
            'no events matched any bin, so there is nothing to epoch.'));
    end

    nchan = size(EEG.data, 1);
    total = size(EEG.data, 2);
    ntr   = numel(allEvents);
    lat   = round([EEG.event.latency]);

    data = nan(nchan, pnts, ntr);
    for k = 1:ntr
        ei = allEvents(k);
        if isnan(lat(ei)); continue; end
        a = lat(ei) + loS;              % first sample of the epoch (1-based)
        b = a + pnts - 1;
        srcA = max(a, 1);  srcB = min(b, total);
        if srcB < srcA; continue; end   % epoch entirely outside the data
        dstA = srcA - a + 1;
        dstB = dstA + (srcB - srcA);
        data(:, dstA:dstB, k) = EEG.data(:, srcA:srcB);
    end

    times = ((loS + (0:pnts - 1)) / srate) * 1000;   % ms, t = 0 at the anchor

    EEG.data       = data;
    EEG.pnts       = pnts;
    EEG.trials     = ntr;
    EEG.times      = times;
    EEG.xmin       = times(1) / 1000;
    EEG.xmax       = times(end) / 1000;
    EEG.DataFormat = 'EPOCHED';

    % Per-trial epoch table and bin -> trial index mapping.
    trialOf = zeros(1, max(allEvents));
    trialOf(allEvents) = 1:ntr;
    EEG.epoch = struct('event', {}, 'eventtype', {}, ...
                       'eventlatency', {}, 'bini', {});
    for k = 1:ntr
        ei = allEvents(k);
        EEG.epoch(k).event        = ei;
        EEG.epoch(k).eventtype    = EEG.event(ei).type;
        EEG.epoch(k).eventlatency = 0;
        EEG.epoch(k).bini         = EEG.event(ei).bini;
    end
    for b = 1:numel(bindesc)
        if isempty(bindesc(b).events)
            bindesc(b).trials = [];
        else
            bindesc(b).trials = trialOf(bindesc(b).events);
        end
    end
end

% ======================================================================= %
%  Parser: script -> spec with .bins {index,label,text,expr} and .epoch window
% ======================================================================= %
function spec = parseSpec(script)
    script = char(script);
    toks   = tokenize(script);

    % Statements start at each top-level 'bin' or 'epoch' keyword.
    isStart = arrayfun(@(t) t.kind == "kw" && ...
        (t.val == "bin" || t.val == "epoch"), toks);
    starts = find(isStart);
    if isempty(starts)
        throw(MException('Alakazam:DefineBins', ...
            'No bin definitions found. Each line is:  bin <n> "label" : <expr>'));
    end

    bins = struct('index', {}, 'label', {}, 'text', {}, 'expr', {});
    epochWin = [];
    for s = 1:numel(starts)
        first = starts(s);
        if s < numel(starts); last = starts(s+1) - 1; else; last = numel(toks); end
        stmt = toks(first:last);

        if stmt(1).val == "epoch"
            if ~isempty(epochWin)
                throw(MException('Alakazam:DefineBins', ...
                    'Only one ''epoch'' window may be given.'));
            end
            epochWin = parseEpochDirective(stmt);
        else
            bins(end + 1) = parseBinStatement(stmt, script); %#ok<AGROW>
        end
    end

    spec.bins  = bins;
    spec.epoch = epochWin;
end

function bin = parseBinStatement(stmt, script)
    % bin <num> "<label>" [:] <expr>
    [~,     stmt] = expectTok(stmt, "kw", "bin", 'the keyword ''bin''');
    [idx,   stmt] = expectTok(stmt, "num", 'a bin number after ''bin''');
    [label, stmt] = expectTok(stmt, "str", 'a quoted label');
    % The ':' separating the label from the expression is optional.
    if ~isempty(stmt) && stmt(1).kind == "punc" && stmt(1).val == ":"
        stmt = stmt(2:end);
    end
    if isempty(stmt)
        throw(MException('Alakazam:DefineBins', ...
            'bin %g "%s": expression is empty.', idx.val, label.val));
    end
    bin.index = round(idx.val);
    bin.label = char(label.val);
    bin.text  = char(strtrim(sliceSource(script, stmt)));
    bin.expr  = parseExprTokens(stmt);
end

function iv = parseEpochDirective(stmt)
    % epoch <window>, e.g.  epoch [-200,800] ms
    T = stmt(2:end);                                  % drop the 'epoch' keyword
    if isempty(T)
        throw(MException('Alakazam:DefineBins', ...
            '''epoch'' needs a window, e.g.  epoch [-200,800] ms'));
    end
    [iv, k] = scanInterval(T, 1);
    if k <= numel(T)
        throw(MException('Alakazam:DefineBins', ...
            'Parse error near column %d: unexpected token after epoch window.', ...
            T(k).pos));
    end
end

% Standalone interval scanner, shared by the epoch directive and the
% expression parser's within-window. Returns the window and the next cursor.
function [iv, k] = scanInterval(T, k)
    o = tokAt(T, k);
    if ~(o.kind == "punc" && (o.val == "(" || o.val == "["))
        throw(MException('Alakazam:DefineBins', ...
            'Parse error near column %d: expected ''('' or ''['' to open a window.', ...
            o.pos));
    end
    loOpen = (o.val == "("); k = k + 1;
    [lo, k] = scanNum(T, k);
    cComma = tokAt(T, k);
    if ~(cComma.kind == "punc" && cComma.val == ",")
        throw(MException('Alakazam:DefineBins', ...
            'Parse error near column %d: expected '','' in the window.', cComma.pos));
    end
    k = k + 1;
    [hi, k] = scanNum(T, k);
    c = tokAt(T, k);
    if ~(c.kind == "punc" && (c.val == ")" || c.val == "]"))
        throw(MException('Alakazam:DefineBins', ...
            'Parse error near column %d: expected '')'' or '']'' to close a window.', ...
            c.pos));
    end
    hiOpen = (c.val == ")"); k = k + 1;
    unit = 'ms';
    u = tokAt(T, k);
    if u.kind == "kw" && (u.val == "ms" || u.val == "samples")
        unit = char(u.val); k = k + 1;
    end
    if lo > hi
        throw(MException('Alakazam:DefineBins', ...
            'Window low bound (%g) exceeds high bound (%g).', lo, hi));
    end
    iv = struct('lo', lo, 'hi', hi, 'loOpen', loOpen, 'hiOpen', hiOpen, 'unit', unit);
end

function [v, k] = scanNum(T, k)
    t = tokAt(T, k);
    if t.kind ~= "num"
        throw(MException('Alakazam:DefineBins', ...
            'Parse error near column %d: expected a number.', t.pos));
    end
    v = t.val; k = k + 1;
end

function t = tokAt(T, k)
    if k >= 1 && k <= numel(T); t = T(k);
    else; t = struct('kind', "eof", 'val', "", 'pos', -1, 'len', 0); end
end

function [tok, rest] = expectTok(toks, kind, varargin)
    % expectTok(toks, kind, what) or expectTok(toks, kind, value, what)
    if numel(varargin) == 2
        wantVal = string(varargin{1}); what = varargin{2};
    else
        wantVal = ""; what = varargin{1};
    end
    if isempty(toks) || toks(1).kind ~= kind ...
            || (wantVal ~= "" && toks(1).val ~= wantVal)
        throw(MException('Alakazam:DefineBins', ...
            'Parse error near column %d: expected %s.', tokCol(toks), what));
    end
    tok  = toks(1);
    rest = toks(2:end);
end

function c = tokCol(toks)
    if isempty(toks); c = -1; else; c = toks(1).pos; end
end

function txt = sliceSource(script, stmt)
    if isempty(stmt); txt = ''; return; end
    a = stmt(1).pos;
    b = stmt(end).pos + stmt(end).len - 1;
    txt = script(a:min(b, numel(script)));
end

% Recursive-descent expression parser over a token subarray.
function node = parseExprTokens(T)
    k = 1;
    node = pOr();
    if k <= numel(T)
        throw(MException('Alakazam:DefineBins', ...
            'Parse error near column %d: unexpected token.', T(k).pos));
    end

    function nd = pOr()
        kids = {pAnd()};
        while isKw('or'); advance(); kids{end+1} = pAnd(); end
        if numel(kids) == 1; nd = kids{1};
        else; nd.op = 'or'; nd.kids = kids; end
    end

    function nd = pAnd()
        % 'and' is explicit or implied: two adjacent terms are and-ed, so
        % `"s??" not {…}` means `"s??" and not {…}`.
        kids = {pNot()};
        while isKw('and') || startsTerm()
            if isKw('and'); advance(); end
            kids{end+1} = pNot();
        end
        if numel(kids) == 1; nd = kids{1};
        else; nd.op = 'and'; nd.kids = kids; end
    end

    function tf = startsTerm()
        t = cur();
        tf = (t.kind == "num") || (t.kind == "str") ...
            || (t.kind == "kw" && any(t.val == ...
                    ["not","next","prev","adjacent","any"])) ...
            || (t.kind == "punc" && (t.val == "(" || t.val == "{"));
    end

    function nd = pNot()
        if isKw('not')
            advance();
            nd.op = 'not'; nd.kid = pNot();
        else
            nd = pPrimary();
        end
    end

    function nd = pPrimary()
        if isPunc('(')
            advance(); nd = pOr(); expectPunc(')');
        elseif isKw('next') || isKw('prev') || isKw('adjacent') || isKw('any')
            nd = pRelation();
        else
            nd.op = 'anchor'; nd.codes = pCodeset();
        end
    end

    function nd = pRelation()
        quant = char(cur().val); advance();
        expectPunc('(');
        codes = pCodeset();
        expectPunc(')');
        iv = [];
        if isKw('within'); advance(); iv = pInterval(); end
        if strcmp(quant, 'any') && isempty(iv)
            throw(MException('Alakazam:DefineBins', ...
                'any(...) requires a ''within'' window (near column %d).', ...
                curCol()));
        end
        nd.op = 'rel'; nd.quant = quant; nd.codes = codes; nd.interval = iv;
    end

    function codes = pCodeset()
        if isPunc('{')
            advance();
            codes = strings(1, 0);
            while ~isPunc('}')
                if cur().kind == "eof"
                    throw(MException('Alakazam:DefineBins', ...
                        'Unterminated ''{'' code list.'));
                end
                if isPunc(','); advance(); continue; end   % optional separators
                codes(end+1) = codeElem();
            end
            advance();                                     % consume '}'
            if isempty(codes)
                throw(MException('Alakazam:DefineBins', ...
                    'Empty ''{}'' code list near column %d.', curCol()));
            end
        else
            codes = codeElem();
            while isPunc('|'); advance(); codes(end+1) = codeElem(); end
        end
    end

    function e = codeElem()
        t = cur();
        if t.kind == "num"
            e = canonType(t.val); advance();
        elseif t.kind == "str"
            e = canonType(t.val); advance();
        else
            throw(MException('Alakazam:DefineBins', ...
                'Parse error near column %d: expected a marker code.', curCol()));
        end
    end

    function iv = pInterval()
        [iv, k] = scanInterval(T, k);   % shared scanner; advances the cursor
    end

    % --- token cursor helpers ---
    function t = cur()
        if k <= numel(T); t = T(k);
        else; t = struct('kind', "eof", 'val', "", 'pos', -1, 'len', 0); end
    end
    function c = curCol(); c = cur().pos; end
    function advance(); k = k + 1; end
    function tf = isKw(w);   t = cur(); tf = t.kind == "kw"   && t.val == w; end
    function tf = isPunc(w); t = cur(); tf = t.kind == "punc" && t.val == w; end
    function expectPunc(w)
        if ~isPunc(w)
            throw(MException('Alakazam:DefineBins', ...
                'Parse error near column %d: expected ''%s''.', curCol(), w));
        end
        advance();
    end
end

% ======================================================================= %
%  Tokenizer
% ======================================================================= %
function toks = tokenize(s)
    keywords = ["bin","epoch","and","or","not","next","prev","adjacent","any", ...
                "within","ms","samples"];
    toks = struct('kind', {}, 'val', {}, 'pos', {}, 'len', {});
    i = 1; n = numel(s);
    while i <= n
        c = s(i);
        if isspace(c)
            i = i + 1;
        elseif c == '%' || c == '#'
            while i <= n && s(i) ~= newline; i = i + 1; end
        elseif c == '"'
            j = i + 1;
            while j <= n && s(j) ~= '"'; j = j + 1; end
            if j > n
                throw(MException('Alakazam:DefineBins', ...
                    'Unterminated string starting at column %d.', i));
            end
            toks(end+1) = mkTok("str", string(s(i+1:j-1)), i, j-i+1);
            i = j + 1;
        elseif isdigit(c) || (c == '-' && i < n && isdigit(s(i+1)))
            j = i + 1;
            while j <= n && (isdigit(s(j)) || s(j) == '.'); j = j + 1; end
            toks(end+1) = mkTok("num", str2double(s(i:j-1)), i, j-i);
            i = j;
        elseif isletter(c) || c == '_'
            j = i + 1;
            while j <= n && (isletter(s(j)) || isdigit(s(j)) || s(j) == '_')
                j = j + 1;
            end
            word = s(i:j-1);
            if any(strcmpi(word, keywords))
                toks(end+1) = mkTok("kw", lower(string(word)), i, j-i);
            else
                throw(MException('Alakazam:DefineBins', ...
                    'Unknown word ''%s'' at column %d. Quote text markers as "%s".', ...
                    word, i, word));
            end
            i = j;
        elseif any(c == '()[]{}|,:')
            toks(end+1) = mkTok("punc", string(c), i, 1);
            i = i + 1;
        else
            throw(MException('Alakazam:DefineBins', ...
                'Unexpected character ''%s'' at column %d.', c, i));
        end
    end
end

function t = mkTok(kind, val, pos, len)
    t = struct('kind', kind, 'val', val, 'pos', pos, 'len', len);
end

function tf = isdigit(c)
    tf = c >= '0' && c <= '9';
end
