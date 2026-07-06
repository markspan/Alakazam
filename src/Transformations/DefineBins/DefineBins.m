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
        [script, epochWin] = promptForScript();
        spec   = parseSpec(script);              % may throw parse errors
        % Remember the last valid script so it prefills the editor next time.
        setpref('Alakazam', 'DefineBinsScript', script);
        options = struct('script', script, 'bins', spec.bins, 'epoch', epochWin);
    elseif isstruct(options) && isfield(options, 'script') && ~isfield(options, 'bins')
        % Script mode: parse a supplied script without a dialog (for scripting
        % and tests). Optionally carries an 'epoch' window struct.
        script = char(options.script);
        spec   = parseSpec(script);
        if isfield(options, 'epoch'); epochWin = options.epoch; else; epochWin = []; end
        options = struct('script', script, 'bins', spec.bins, 'epoch', epochWin);
    else
        if ~isstruct(options) || ~isfield(options, 'bins')
            throw(MException('Alakazam:DefineBins', ...
                'Problem in DefineBins: invalid stored options'));
        end
        spec.bins = options.bins;
        if isfield(options, 'epoch'); epochWin = options.epoch; else; epochWin = []; end
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
    % The sample each event's epoch is centred on. Defaults to the event's own
    % latency; a 'timelock' bin overrides it with a neighbour's latency.
    centerLat  = round([EEG.event.latency]);
    bindesc = struct('index', {}, 'label', {}, 'script', {}, 'plan', {}, ...
                     'combo', {}, 'events', {}, 'rt', {}, 'n', {});

    for b = 1:numel(bins)
        if ~isempty(bins(b).combo)
            % Combination (difference) bin: no event predicate; the Average
            % step computes it from the referenced bins' averages.
            bindesc(b) = binRecord(bins(b), [], [], bins(b).combo);
            continue;
        end

        matchedOrig = [];
        rts = [];
        for p = 1:nEv
            [tf, capLat] = evalNode(bins(b).expr, p, ctx);
            if ~tf; continue; end

            if isnan(capLat)
                rtMs = NaN;
            else
                rtMs = (capLat - ctx.lat(p)) / ctx.srate * 1000;
            end

            % 'rt within W': keep the match only if its reaction time is in W.
            if ~isempty(bins(b).rtWindow) ...
                    && (isnan(rtMs) || ~inInterval(rtMs, bins(b).rtWindow))
                continue;
            end

            % 'timelock <rel>': centre the epoch on a neighbour, not the anchor.
            if ~isempty(bins(b).timelock)
                [okTL, tlLat] = evalRel(bins(b).timelock, p, ctx);
                if ~okTL; continue; end          % nothing to lock to -> drop
                centerLat(order(p)) = round(tlLat);
            end

            matchedOrig(end+1)   = order(p);
            rts(end+1)           = rtMs;
            membership{p}(end+1) = bins(b).index;
        end
        bindesc(b) = binRecord(bins(b), matchedOrig, rts, []);
    end

    %% Tag events with their bin membership (ERPLAB-style .bini)
    for p = 1:nEv
        EEG.event(order(p)).bini = membership{p};
    end

    %% Cut epochs when an epoch window was given (dialog), so the result plots
    %  as an epoched dataset (EpochView). Without it, the data stays continuous
    %  and only the bin tags are added.
    if ~isempty(epochWin)
        [EEG, bindesc] = cutEpochs(EEG, bindesc, epochWin, centerLat);
    end
    EEG.bindesc = bindesc;

    %% Interactive summary
    if interactive
        reportBins(bindesc, EEG);
    end
end

function rec = binRecord(bin, events, rts, combo)
%BINRECORD  Build one EEG.bindesc entry with a stable field order.
    rec.index  = bin.index;
    rec.label  = bin.label;
    rec.script = bin.text;
    rec.plan   = bin.expr;
    rec.combo  = combo;
    rec.events = events;
    rec.rt     = rts;
    rec.n      = numel(events);
end

% ======================================================================= %
%  Interactive prompt
% ======================================================================= %
function [script, epochWin] = promptForScript()
    template = [ ...
        '% Codes are markers; ? = any char; { } lists alternatives; | is or.'              newline ...
        '% Relations: next(c) prev(c) adjacent(c) any(c) within (lo,hi] unit.'             newline ...
        '% let names a code set; = makes a difference bin; rt / timelock refine a bin.'    newline ...
        'let related = {"s11" "s22" "s33" "s44" "s55"}'                                    newline ...
        'bin 1 "Related"    related           and next("S201") within (200,1200] ms'       newline ...
        'bin 2 "Unrelated"  "s??" not related and next("S201") within (200,1200] ms'       newline ...
        'bin 3 "Effect"     = bin 1 - bin 2' ];

    % Prefill with the last script and epoch bounds the user ran (remembered
    % across sessions), falling back to the built-in template on first use.
    default   = getpref('Alakazam', 'DefineBinsScript', template);
    prevEpoch = getpref('Alakazam', 'DefineBinsEpoch', {'-200', '800'});

    % The epoch window (ms, cut around each matched event) is a per-run choice,
    % so it is two small fields above the script rather than a keyword. Leave
    % both blank to keep the data continuous (tag events only).
    result = showDefineBinsDialog(default, prevEpoch);
    if isempty(result)
        throw(MException('Alakazam:DefineBins', 'DefineBins cancelled.'));
    end

    script   = result.script;
    epochWin = parseEpochBounds(result.start, result.stop);
    setpref('Alakazam', 'DefineBinsEpoch', {result.start, result.stop});
end

function result = showDefineBinsDialog(defaultScript, prevEpoch)
%SHOWDEFINEBINSDIALOG  Modal editor: epoch start/stop side by side, script below.
%   Returns a struct with .start, .stop (raw text) and .script, or [] if the
%   user cancelled or closed the window.
    result = [];

    fig = uifigure('Name', 'DefineBins', 'Position', [100 100 640 480]);
    outer = uigridlayout(fig, [3 1], 'RowHeight', {'fit', '1x', 44});

    % Row 1: epoch start/stop fields, side by side.
    epochRow = uigridlayout(outer, [1 4], ...
        'ColumnWidth', {'fit', 90, 'fit', 90}, 'Padding', [8 8 8 0]);
    epochRow.Layout.Row = 1;
    uilabel(epochRow, 'Text', 'Epoch start (ms):');
    startField = uieditfield(epochRow, 'text', 'Value', prevEpoch{1});
    uilabel(epochRow, 'Text', 'Epoch stop (ms):');
    stopField = uieditfield(epochRow, 'text', 'Value', prevEpoch{2});

    % Row 2: bin definitions, a multi-line text area.
    scriptArea = uitextarea(outer, 'Value', strsplit(defaultScript, newline), ...
        'FontName', 'Consolas');
    scriptArea.Layout.Row = 2;

    % Row 3: Save / Load on the left, OK / Cancel right-aligned.
    buttons = uigridlayout(outer, [1 5], 'ColumnWidth', {90, 90, '1x', 90, 90}, ...
        'Padding', [8 6 8 6]);
    buttons.Layout.Row = 3;
    saveBtn = uibutton(buttons, 'Text', 'Save...', 'ButtonPushedFcn', @(~,~) onSave());
    saveBtn.Layout.Column = 1;
    loadBtn = uibutton(buttons, 'Text', 'Load...', 'ButtonPushedFcn', @(~,~) onLoad());
    loadBtn.Layout.Column = 2;
    cancelBtn = uibutton(buttons, 'Text', 'Cancel', 'ButtonPushedFcn', @(~,~) onCancel());
    cancelBtn.Layout.Column = 4;
    okBtn = uibutton(buttons, 'Text', 'OK', 'ButtonPushedFcn', @(~,~) onOK());
    okBtn.Layout.Column = 5;
    fig.CloseRequestFcn = @(~,~) onCancel();

    uiwait(fig);

    function onOK()
        result = struct('start', strtrim(startField.Value), ...
            'stop', strtrim(stopField.Value), ...
            'script', strjoin(scriptArea.Value, newline));
        uiresume(fig);
        delete(fig);
    end

    function onCancel()
        uiresume(fig);
        delete(fig);
    end

    function onSave()
        % Save the epoch bounds and script text together, so a saved file
        % restores the dialog exactly as it was when saved.
        [file, path] = uiextras.uiputfile2('*.binscript', 'Save bin definitions as');
        if isequal(file, 0); return; end
        try
            writeScriptFile(fullfile(path, file), strtrim(startField.Value), ...
                strtrim(stopField.Value), strjoin(scriptArea.Value, newline));
        catch err
            uialert(fig, err.message, 'Save failed');
        end
    end

    function onLoad()
        [file, path] = uiextras.uigetfile2('*.binscript', 'Load bin definitions');
        if isequal(file, 0); return; end
        try
            [startStr, stopStr, script] = readScriptFile(fullfile(path, file));
            startField.Value = startStr;
            stopField.Value  = stopStr;
            scriptArea.Value = splitlines(script);
        catch err
            uialert(fig, err.message, 'Load failed');
        end
    end
end

function writeScriptFile(filePath, startStr, stopStr, script)
%WRITESCRIPTFILE  Save epoch bounds + script text as a small header + body.
    fid = fopen(filePath, 'w');
    if fid < 0
        throw(MException('Alakazam:DefineBins', 'Could not write %s.', filePath));
    end
    cleanup = onCleanup(@() fclose(fid));
    fprintf(fid, '%% epoch_start_ms: %s\n', startStr);
    fprintf(fid, '%% epoch_stop_ms: %s\n', stopStr);
    fprintf(fid, '%s', script);
end

function [startStr, stopStr, script] = readScriptFile(filePath)
%READSCRIPTFILE  Inverse of writeScriptFile; tolerates a body with no header.
    lines = splitlines(fileread(filePath));
    startStr = '';
    stopStr  = '';
    i = 1;
    if numel(lines) >= i
        tok = regexp(lines{i}, '^%\s*epoch_start_ms:\s*(.*)$', 'tokens', 'once');
        if ~isempty(tok); startStr = strtrim(tok{1}); i = i + 1; end
    end
    if numel(lines) >= i
        tok = regexp(lines{i}, '^%\s*epoch_stop_ms:\s*(.*)$', 'tokens', 'once');
        if ~isempty(tok); stopStr = strtrim(tok{1}); i = i + 1; end
    end
    script = strjoin(lines(i:end), newline);
end

function win = parseEpochBounds(startStr, stopStr)
%PARSEEPOCHBOUNDS  Turn the dialog's start/stop text (ms) into an epoch window.
%   Both blank means no epoching ([]); otherwise both bounds are required and
%   the window is inclusive, in milliseconds.
    if isempty(startStr) && isempty(stopStr)
        win = [];
        return;
    end
    lo = epochNum(startStr, 'start');
    hi = epochNum(stopStr,  'stop');
    if hi <= lo
        throw(MException('Alakazam:DefineBins', ...
            'Epoch stop (%g ms) must be after the start (%g ms).', hi, lo));
    end
    win = struct('lo', lo, 'hi', hi, 'unit', 'ms');
end

function v = epochNum(str, which)
    if isempty(str)
        throw(MException('Alakazam:DefineBins', ...
            'Give both an epoch start and stop, or leave both blank (the %s is missing).', which));
    end
    v = str2double(str);
    if isnan(v)
        throw(MException('Alakazam:DefineBins', ...
            'Epoch %s "%s" is not a number of milliseconds.', which, str));
    end
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
    n       = numel(ctx.lat);
    matcher = node.matcher;
    iv      = node.interval;
    found   = 0;

    switch node.quant
        case 'next'
            for q = p+1:n
                if evalNode(matcher, q, ctx); found = q; break; end
            end
        case 'prev'
            for q = p-1:-1:1
                if evalNode(matcher, q, ctx); found = q; break; end
            end
        case 'adjacent'
            if p+1 <= n && evalNode(matcher, p+1, ctx); found = p+1; end
        case 'any'
            for q = 1:n
                if q ~= p && evalNode(matcher, q, ctx) ...
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
function [EEG, bindesc] = cutEpochs(EEG, bindesc, win, centerLat)
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
    lat   = centerLat;   % sample to centre each epoch on (timelock-aware)

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

    % Statements start at a 'let', or at a 'bin <num> "<label>"' (a bare
    % 'bin <num>' inside a combination, = bin 1 - bin 2, is not a statement).
    isStart = false(1, numel(toks));
    for i = 1:numel(toks)
        if toks(i).kind ~= "kw"; continue; end
        if toks(i).val == "let"
            isStart(i) = true;
        elseif toks(i).val == "bin"
            isStart(i) = (i + 2 <= numel(toks)) ...
                && toks(i+1).kind == "num" && toks(i+2).kind == "str";
        end
    end
    starts = find(isStart);
    if isempty(starts)
        throw(MException('Alakazam:DefineBins', ...
            'No bin definitions found. Each line is:  bin <n> "label" : <expr>'));
    end

    stmts = cell(1, numel(starts));
    for s = 1:numel(starts)
        first = starts(s);
        if s < numel(starts); last = starts(s+1) - 1; else; last = numel(toks); end
        stmts{s} = toks(first:last);
    end

    % First pass: collect 'let' aliases, in file order, so a later alias may
    % reference any earlier one (a forward-reference or a cycle is an
    % "unknown name" error from the alias not existing yet).
    aliases = struct();
    for s = 1:numel(stmts)
        if stmts{s}(1).val == "let"
            [name, node] = parseLetStatement(stmts{s}, aliases);
            if isfield(aliases, name)
                throw(MException('Alakazam:DefineBins', ...
                    'Alias ''%s'' is defined more than once.', name));
            end
            aliases.(name) = node;
        end
    end

    % Second pass: the bins.
    bins = struct('index', {}, 'label', {}, 'text', {}, ...
                  'expr', {}, 'combo', {}, 'rtWindow', {}, 'timelock', {});
    for s = 1:numel(stmts)
        if stmts{s}(1).val == "bin"
            bins(end + 1) = parseBinStatement(stmts{s}, script, aliases);
        end
    end
    spec.bins = bins;
end

function bin = parseBinStatement(stmt, script, aliases)
    % bin <num> "<label>" [:] <expr> [rt within W] [timelock <rel>]
    %   or   bin <num> "<label>" = <combination>
    [~,     rest] = expectTok(stmt, "kw", "bin", 'the keyword ''bin''');
    [idx,   rest] = expectTok(rest, "num", 'a bin number after ''bin''');
    [label, rest] = expectTok(rest, "str", 'a quoted label');

    bin.index    = round(idx.val);
    bin.label    = char(label.val);
    bin.text     = char(strtrim(sliceSource(script, rest)));
    bin.expr     = [];
    bin.combo    = [];
    bin.rtWindow = [];
    bin.timelock = [];

    % A '=' after the label makes this a combination (difference) bin, defined
    % from earlier bins' averages rather than by an event predicate.
    if ~isempty(rest) && rest(1).kind == "punc" && rest(1).val == "="
        bin.combo = parseCombo(rest(2:end), bin.index, bin.label);
        return;
    end

    % Otherwise an optional ':' then a predicate, with optional suffixes.
    if ~isempty(rest) && rest(1).kind == "punc" && rest(1).val == ":"
        rest = rest(2:end);
    end
    if isempty(rest)
        throw(MException('Alakazam:DefineBins', ...
            'bin %g "%s": expression is empty.', idx.val, label.val));
    end
    [bin.expr, k] = parseExprTokens(rest, aliases);

    % Suffixes (either order): rt within <window>, timelock <relation>.
    while k <= numel(rest)
        t = rest(k);
        if t.kind == "kw" && t.val == "rt"
            [bin.rtWindow, k] = scanRtWindow(rest, k + 1, bin.index);
        elseif t.kind == "kw" && t.val == "timelock"
            [bin.timelock, k] = parseTimelock(rest, k + 1, aliases, bin.index);
        else
            throw(MException('Alakazam:DefineBins', ...
                'Parse error near column %d: unexpected token after the expression.', t.pos));
        end
    end
end

function [name, node] = parseLetStatement(stmt, aliases)
    % let <ident> = <expr>   (codes combined with not/and/or/parens; may
    % reference any alias defined earlier in the script, but not relations
    % such as next(...)/prev(...), which belong in the bin's own expression).
    [~,     rest] = expectTok(stmt, "kw", "let", 'the keyword ''let''');
    [nameT, rest] = expectTok(rest, "ident", 'an alias name after ''let''');
    name = char(nameT.val);
    if isempty(rest) || ~(rest(1).kind == "punc" && rest(1).val == "=")
        throw(MException('Alakazam:DefineBins', ...
            'let %s: expected ''='' after the alias name.', name));
    end
    rest = rest(2:end);
    if isempty(rest)
        throw(MException('Alakazam:DefineBins', ...
            'let %s: expected a code or code expression after ''=''.', name));
    end
    [node, k] = parseExprTokens(rest, aliases);
    if k <= numel(rest)
        throw(MException('Alakazam:DefineBins', ...
            'let %s: unexpected token near column %d.', name, rest(k).pos));
    end
    forbidRelations(node, name);
end

function forbidRelations(node, name)
%FORBIDRELATIONS  A let's body may combine codes with not/and/or/parens, but
%   not relations (next/prev/adjacent/any); those stay in the bin's own
%   expression, where "which event's neighbour" is unambiguous.
    switch node.op
        case 'rel'
            throw(MException('Alakazam:DefineBins', ...
                'let %s: relations like next(...)/prev(...) are not allowed here; write them in the bin''s own expression.', ...
                name));
        case 'not'
            forbidRelations(node.kid, name);
        case {'and', 'or'}
            for i = 1:numel(node.kids); forbidRelations(node.kids{i}, name); end
    end
end

function combo = parseCombo(T, binIndex, label)
    % <coeff>? bin <n> ( ('+'|'-') <coeff>? bin <n> )*  -> struct(coeff, bin)
    combo = struct('coeff', {}, 'bin', {});
    k = 1; sgn = 1;
    while true
        coeff = sgn;
        t = tokAt(T, k);
        if t.kind == "num"; coeff = sgn * t.val; k = k + 1; t = tokAt(T, k); end
        if ~(t.kind == "kw" && t.val == "bin")
            throw(MException('Alakazam:DefineBins', ...
                'bin %g "%s": expected ''bin <n>'' in the combination near column %d.', ...
                binIndex, label, t.pos));
        end
        k = k + 1;
        [num, k] = scanNum(T, k);
        combo(end+1) = struct('coeff', coeff, 'bin', round(num));
        op = tokAt(T, k);
        if op.kind == "eof"
            break;
        elseif op.kind == "punc" && op.val == "+"
            sgn = 1; k = k + 1;
        elseif op.kind == "punc" && op.val == "-"
            sgn = -1; k = k + 1;
        else
            throw(MException('Alakazam:DefineBins', ...
                'bin %g "%s": expected ''+'' or ''-'' in the combination near column %d.', ...
                binIndex, label, op.pos));
        end
    end
end

function [iv, k] = scanRtWindow(T, k, binIndex)
    t = tokAt(T, k);
    if ~(t.kind == "kw" && t.val == "within")
        throw(MException('Alakazam:DefineBins', ...
            'bin %g: ''rt'' must be followed by ''within (lo,hi] ms''.', binIndex));
    end
    [iv, k] = scanInterval(T, k + 1);
end

function [rel, k] = parseTimelock(T, kStart, aliases, binIndex)
    % timelock <relation>  -- reuse the expression parser, require one relation.
    [node, kLocal] = parseExprTokens(T(kStart:end), aliases);
    if ~isstruct(node) || ~strcmp(node.op, 'rel')
        throw(MException('Alakazam:DefineBins', ...
            'bin %g: ''timelock'' must be a single relation, e.g. timelock next(118).', binIndex));
    end
    rel = node;
    k   = kStart + kLocal - 1;
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

% Recursive-descent expression parser over a token subarray. Returns the parsed
% node and the cursor after it; the caller handles any trailing tokens (bin
% suffixes such as rt/timelock, or its own error).
function [node, k] = parseExprTokens(T, aliases)
    k = 1;
    node = pOr();

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
            nd = pCodeset();   % already a fully-formed anchor/not/and/or node
        end
    end

    function nd = pRelation()
        quant = char(cur().val); advance();
        expectPunc('(');
        matcher = pCodeset();
        expectPunc(')');
        iv = [];
        if isKw('within'); advance(); iv = pInterval(); end
        if strcmp(quant, 'any') && isempty(iv)
            throw(MException('Alakazam:DefineBins', ...
                'any(...) requires a ''within'' window (near column %d).', ...
                curCol()));
        end
        nd.op = 'rel'; nd.quant = quant; nd.matcher = matcher; nd.interval = iv;
    end

    function node = pCodeset()
        [node, k] = scanCodeset(T, k, aliases);   % shared scanner; advances k
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

% Standalone codeset scanner, shared by the expression parser and 'let'.
% Expands identifiers (alias references) to their expression node, which may
% itself be compound (not/and/or) rather than a flat code list. Returns a node
% (op 'anchor', with the common case a flat .codes list; or 'not'/'and'/'or'
% when an alias expands to a combination) and the next cursor.
function [node, k] = scanCodeset(T, k, aliases)
    o = tokAt(T, k);
    if o.kind == "punc" && o.val == "{"
        k = k + 1;
        kids = {};
        while ~(tokAt(T, k).kind == "punc" && tokAt(T, k).val == "}")
            if tokAt(T, k).kind == "eof"
                throw(MException('Alakazam:DefineBins', 'Unterminated ''{'' code list.'));
            end
            if tokAt(T, k).kind == "punc" && tokAt(T, k).val == ","
                k = k + 1; continue;                       % optional separators
            end
            [c, k] = scanCodeElem(T, k, aliases);
            kids{end + 1} = c;
        end
        k = k + 1;                                          % consume '}'
        if isempty(kids)
            throw(MException('Alakazam:DefineBins', ...
                'Empty ''{}'' code list near column %d.', tokAt(T, k).pos));
        end
        node = combineOr(kids);
    else
        [first, k] = scanCodeElem(T, k, aliases);
        kids = {first};
        while tokAt(T, k).kind == "punc" && tokAt(T, k).val == "|"
            k = k + 1;
            [c, k] = scanCodeElem(T, k, aliases);
            kids{end + 1} = c;
        end
        node = combineOr(kids);
    end
end

function node = combineOr(kids)
%COMBINEOR  OR together codeset terms, merging adjacent literal ('anchor')
%   nodes into one flat code list. A plain pipe/brace list of literals (and/or
%   aliases that are themselves plain code lists) therefore still collapses to
%   a single 'anchor' node, exactly as before; only a compound alias (one
%   built with not/and/or) produces a richer tree.
    merged = {};
    litAcc = strings(1, 0);
    for i = 1:numel(kids)
        kid = kids{i};
        if strcmp(kid.op, 'anchor')
            litAcc = [litAcc, kid.codes];
        else
            if ~isempty(litAcc)
                merged{end + 1} = anchorNode(litAcc);
                litAcc = strings(1, 0);
            end
            merged{end + 1} = kid;
        end
    end
    if ~isempty(litAcc)
        merged{end + 1} = anchorNode(litAcc);
    end
    if numel(merged) == 1
        node = merged{1};
    else
        node.op = 'or'; node.kids = merged;
    end
end

function node = anchorNode(codes)
    node.op = 'anchor'; node.codes = codes;
end

function [node, k] = scanCodeElem(T, k, aliases)
    t = tokAt(T, k);
    if t.kind == "num" || t.kind == "str"
        node = anchorNode(canonType(t.val)); k = k + 1;
    elseif t.kind == "ident"
        name = char(t.val);
        if ~isfield(aliases, name)
            throw(MException('Alakazam:DefineBins', ...
                'Unknown name ''%s'' near column %d. Define it with ''let %s = ...'', or quote a text marker as "%s".', ...
                name, t.pos, name, name));
        end
        node = aliases.(name); k = k + 1;                   % splice in the alias's expression
    else
        throw(MException('Alakazam:DefineBins', ...
            'Parse error near column %d: expected a marker code.', t.pos));
    end
end

% ======================================================================= %
%  Tokenizer
% ======================================================================= %
function toks = tokenize(s)
    keywords = ["bin","let","rt","timelock","and","or","not", ...
                "next","prev","adjacent","any","within","ms","samples"];
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
                % A bare word is an identifier (an alias name); the parser
                % reports "quote text markers" if it is used where a code is
                % expected and is not a defined alias.
                toks(end+1) = mkTok("ident", string(word), i, j-i);
            end
            i = j;
        elseif any(c == '()[]{}|,:=+-')
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
