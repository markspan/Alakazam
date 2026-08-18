function [EEG, options] = DefineBins(input, varargin)
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
%                takes an optional unit (ms, the default; samples; or events,
%                an ordinal count in the event stream instead of elapsed time
%                -- within [-2,-2] events means "exactly two events before",
%                immune to jitter in the interval itself, e.g. from variable
%                RTs). Windows are signed, so [-1200,-200) means "before".
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
            ['DefineBins needs a dataset to work on, and none was given. ' ...
             'This usually means it was called directly instead of being run ' ...
             'from the Alakazam gallery (or dragged onto a dataset) -- try that instead.']));
    end

    EEG = input;

    %% Mode: interactive (Init) or replay (stored options struct)
    % nargin is already known >= 1 (see the guard above), so InitGuard's own
    % "no dataset" check never fires here -- this call only supplies the
    % opts-default-to-'Init'/interactive-flag half of what it does, kept
    % separate from DefineBins' own more specific "needs a dataset" message.
    [options, interactive] = TransTools.InitGuard(nargin, 'Alakazam:DefineBins', varargin{:});

    if interactive
        [script, epochWin] = promptForScript();
        spec   = parseSpec(script);              % may throw parse errors
        % Remember the last valid script so it prefills the editor next time
        % (in this workspace -- see TransformSettings).
        stored = TransformSettings.get('DefineBins');
        if isempty(stored); stored = struct(); end
        stored.script = script;
        TransformSettings.set('DefineBins', stored);
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
                ['DefineBins was asked to replay a previous run, but the stored ' ...
                 'settings it was given do not look like ones DefineBins itself ' ...
                 'produced (no .bins field). This normally cannot happen from ' ...
                 'the gallery or drag-and-drop; if you are calling DefineBins ' ...
                 'programmatically, pass either the char/string it should parse ' ...
                 'as a script (struct(''script'', ...)), or the exact options ' ...
                 'struct DefineBins previously returned.']));
        end
        spec.bins = options.bins;
        if isfield(options, 'epoch'); epochWin = options.epoch; else; epochWin = []; end
    end
    bins = spec.bins;

    if isempty(bins)
        throw(MException('Alakazam:DefineBins', ...
            ['Your script does not define any bins, so there is nothing for ' ...
             'DefineBins to do. Add at least one line like:' newline newline ...
             '    bin 1 "My first bin" 112' newline newline ...
             '(bin number, a quoted label, then which events belong to it).']));
    end

    %% Validate events
    if ~isfield(EEG, 'event') || isempty(EEG.event) ...
            || ~isfield(EEG.event, 'type') || ~isfield(EEG.event, 'latency')
        throw(MException('Alakazam:DefineBins', ...
            ['This dataset has no usable events for DefineBins to match against ' ...
             '(EEG.event is empty, or missing the .type/.latency fields every ' ...
             'event needs). Check that the recording was imported with its event ' ...
             'markers intact, and that no earlier step removed them.']));
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
        '% Relations: next(c) prev(c) adjacent(c) any(c) within (lo,hi] ms/samples/events.' newline ...
        '% let names a reusable expression (codes or relations); = makes a difference bin.' newline ...
        'let related = {"s11" "s22" "s33" "s44" "s55"}'                                    newline ...
        'bin 1 "Related"    related           and next("S201") within (200,1200] ms'       newline ...
        'bin 2 "Unrelated"  "s??" not related and next("S201") within (200,1200] ms'       newline ...
        'bin 3 "Effect"     = bin 1 - bin 2' ];

    % Prefill with the last script and epoch bounds the user ran in this
    % workspace (see TransformSettings), falling back to the built-in
    % template on first use (a fresh workspace, or one where DefineBins has
    % never run interactively yet).
    stored = TransformSettings.get('DefineBins');
    if isempty(stored) || ~isfield(stored, 'script')
        default = template;
    else
        default = stored.script;
    end
    if isempty(stored) || ~isfield(stored, 'epochStart')
        prevEpoch = {'-200', '800'};
    else
        prevEpoch = {stored.epochStart, stored.epochStop};
    end

    % The epoch window (ms, cut around each matched event) is a per-run choice,
    % so it is two small fields above the script rather than a keyword. Leave
    % both blank to keep the data continuous (tag events only).
    result = showDefineBinsDialog(default, prevEpoch);
    if isempty(result)
        throw(MException('Alakazam:DefineBins', ...
            'No problem -- you cancelled the DefineBins dialog, so nothing was changed.'));
    end

    script   = result.script;
    epochWin = parseEpochBounds(result.start, result.stop);

    % Remember the epoch bounds regardless of whether the script itself
    % turns out to be valid (see the caller, which separately remembers the
    % script only once it parses) -- a typo elsewhere in the script is no
    % reason to discard separately-fine epoch bounds.
    stored = TransformSettings.get('DefineBins');
    if isempty(stored); stored = struct(); end
    stored.epochStart = result.start;
    stored.epochStop  = result.stop;
    TransformSettings.set('DefineBins', stored);
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

    % Row 3: Save / Load / Import on the left, OK / Cancel right-aligned.
    buttons = uigridlayout(outer, [1 6], 'ColumnWidth', {90, 90, 120, '1x', 90, 90}, ...
        'Padding', [8 6 8 6]);
    buttons.Layout.Row = 3;
    saveBtn = uibutton(buttons, 'Text', 'Save...', 'ButtonPushedFcn', @(~,~) onSave());
    saveBtn.Layout.Column = 1;
    loadBtn = uibutton(buttons, 'Text', 'Load...', 'ButtonPushedFcn', @(~,~) onLoad());
    loadBtn.Layout.Column = 2;
    importBtn = uibutton(buttons, 'Text', 'Import BDF...', 'ButtonPushedFcn', @(~,~) onImportBdf(), ...
        'Tooltip', 'Import an ERPLAB bin descriptor file and translate it to this language');
    importBtn.Layout.Column = 3;
    cancelBtn = uibutton(buttons, 'Text', 'Cancel', 'ButtonPushedFcn', @(~,~) onCancel());
    cancelBtn.Layout.Column = 5;
    okBtn = uibutton(buttons, 'Text', 'OK', 'ButtonPushedFcn', @(~,~) onOK());
    okBtn.Layout.Column = 6;
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

    function onImportBdf()
        % Import an ERPLAB bin descriptor file and translate it into this
        % language (see erplabBdfToBinScript). Fills the script editor; the
        % epoch bounds are ERPLAB's separate step, so they are left untouched.
        [file, path] = uiextras.uigetfile2( ...
            {'*.txt;*.bdf', 'ERPLAB bin descriptor file (*.txt, *.bdf)'}, ...
            'Import ERPLAB bin descriptor file');
        if isequal(file, 0); return; end
        try
            [script, warnings] = erplabBdfToBinScript(fileread(fullfile(path, file)));
            scriptArea.Value = splitlines(script);
        catch err
            uialert(fig, err.message, 'Import failed');
            return;
        end
        if ~isempty(warnings)
            uialert(fig, sprintf(['Imported with %d note(s) -- review the lines marked ' ...
                'WARNING in the script:\n\n%s'], numel(warnings), strjoin(warnings, newline)), ...
                'Imported with notes', 'Icon', 'warning');
        end
    end
end

function writeScriptFile(filePath, startStr, stopStr, script)
%WRITESCRIPTFILE  Save epoch bounds + script text as a small header + body.
    fid = fopen(filePath, 'w');
    if fid < 0
        throw(MException('Alakazam:DefineBins', ...
            ['Could not save to %s -- the folder might be read-only, the disk ' ...
             'might be full, or another program might have the file open. ' ...
             'Try a different location or filename.'], filePath));
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
            ['The Epoch stop field (%g ms) needs to come after Epoch start (%g ms), ' ...
             'so there is a positive stretch of time to cut around each event. ' ...
             'A window like -200 to 800 covers 200 ms before the event to 800 ms after it.'], ...
            hi, lo));
    end
    win = struct('lo', lo, 'hi', hi, 'unit', 'ms');
end

function v = epochNum(str, which)
    if isempty(str)
        throw(MException('Alakazam:DefineBins', ...
            ['The Epoch %s field is empty, but Epoch %s has a value. Fill in ' ...
             'both fields to segment the data (for example, -200 and 800), or ' ...
             'clear both to leave the data continuous and just tag the bins.'], ...
            which, otherEpochField(which)));
    end
    v = str2double(str);
    if isnan(v)
        throw(MException('Alakazam:DefineBins', ...
            ['Epoch %s is set to "%s", which is not a plain number of milliseconds ' ...
             '(no units, just a number -- e.g. -200, not "-200ms").'], which, str));
    end
end

function other = otherEpochField(which)
    if strcmp(which, 'start'); other = 'stop'; else; other = 'start'; end
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
%MATCHCODE  True when TYPSTR matches any entry in CODES (exact, case-
%   insensitive, numeric-equal, or wildcard). CODES is normally a
%   `string` array (the parser's own native shape, one element per
%   alternative -- see anchorNode), but may also arrive as a cell
%   array of char (or a single bare char row vector for a one-code
%   matcher) after a round trip through jsonencode/jsondecode -- e.g. a
%   template saved by Alakazam.onSaveTemplate and replayed later via
%   Apply Template/applyStepToTarget, which never touches the parser at
%   all, only jsondecode. Left unnormalised, a bare char row vector
%   (jsondecode's shape for what was originally a scalar string, e.g.
%   "201") is numel==3, not 1: the loop below would iterate over its
%   individual CHARACTERS ('2','0','1') as if they were three separate
%   one-character codes, so a single-code matcher could never actually
%   match anything post-round-trip -- every next(code)/prev(code)
%   relation using it would then scan the entire event list on every
%   call (see evalRel's unbounded search loops) instead of usually
%   breaking after one or two events, which is what actually explains an
%   applied template appearing to hang.
    if ischar(codes)
        codes = {codes};
    end
    for i = 1:numel(codes)
        if iscell(codes)
            c = codes{i};
        else
            c = codes(i);
        end
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
                ['Internal error: the compiled expression tree contains a node type ' ...
                 '(''%s'') the evaluator does not know how to handle. This should be ' ...
                 'impossible from any script the parser accepts, so it likely means a ' ...
                 'saved/replayed .bins struct was hand-edited or came from an ' ...
                 'incompatible version -- please report this as a bug.'], node.op));
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
    if ~isempty(iv) && strcmp(iv.unit, 'events')
        % Ordinal distance in the event stream, not elapsed time: immune to
        % RT/ISI jitter, unlike ms/samples -- e.g. within [-2,-2] events means
        % "exactly two events before", regardless of how long that took.
        d = q - p;
        return;
    end
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
            ['You gave an Epoch start/stop, so DefineBins tried to cut the data into ' ...
             'trials, but this dataset has no continuous EEG.data to cut from. ' ...
             'This normally means it was already segmented (or is missing data ' ...
             'entirely) before it reached DefineBins.']));
    end
    if ~ismatrix(EEG.data) || (isfield(EEG, 'DataFormat') && ...
            strcmpi(EEG.DataFormat, 'EPOCHED'))
        throw(MException('Alakazam:DefineBins', ...
            ['You gave an Epoch start/stop, but this dataset is already epoched ' ...
             '(channels x time x trials), and DefineBins only knows how to cut trials ' ...
             'out of continuous data. If you want to re-tag bins on data you have ' ...
             'already segmented, leave both Epoch fields blank.']));
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
            ['The epoch window (%g to %g %s) rounds to zero or a negative number ' ...
             'of samples at this dataset''s sampling rate (%g Hz), so there is ' ...
             'nothing to cut. Widen the window, or double-check the sampling rate ' ...
             'is what you expect.'], win.lo, win.hi, win.unit, srate));
    end

    allEvents = unique([bindesc.events]);
    if isempty(allEvents)
        throw(MException('Alakazam:DefineBins', ...
            ['None of your bins matched a single event in this dataset, so there is ' ...
             'nothing to epoch. Double-check the marker codes in your script against ' ...
             'the ones actually present in this recording (EEG.event(i).type), and ' ...
             'that any next(...)/prev(...)/within windows are wide enough to catch ' ...
             'the responses you expect.']));
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
%  Friendly error reporting
% ======================================================================= %
%  Every low-level parsing/tokenizing function below raises its errors with
%  throwParseError(col, what): col is the character offset into the script
%  where the trouble is (or -1 when nothing more specific than "somewhere in
%  this bin" applies), and what is a short, plain-English description, e.g.
%  'a closing '')'' to finish this window'. throwParseError never formats the
%  final message itself -- it just stashes col in the exception identifier
%  (a plain, un-escaped integer is safe there, unlike in the message text)
%  and lets whichever call wrapped the parse in a try/catch (parseSpec, or a
%  standalone caller replaying a script) turn it into the friendly,
%  in-context report below, once, in one place, for every one of these sites
%  at once. This is why the individual throwParseError call sites can stay
%  short: they describe the *specific* mistake, and the shared wrapper
%  supplies the warmth, the source snippet, and the caret.
function throwParseError(col, what)
    if isempty(col) || isnan(col); col = -1; end
    id = sprintf('Alakazam:DefineBins:ParseAtCol%d', max(round(col), 0));
    throw(MException(id, '%s', what));
end

function ME = wrapParseError(script, err)
%WRAPPARSEERROR  Turn a throwParseError (or any other) exception into a
%   warm, specific, example-rich one that shows exactly where the trouble is
%   in the analyst's own script -- or, if it is not one of ours (an
%   unexpected internal error), passes it through untouched.
    tok = regexp(err.identifier, '^Alakazam:DefineBins:ParseAtCol(\d+)$', 'tokens', 'once');
    if isempty(tok)
        ME = err;
        return;
    end
    col = str2double(tok{1});

    opener = "I got a little stuck reading your DefineBins script -- let's sort it out together.";
    if col > 0 && col <= numel(script)
        [lineTxt, lineNo, colInLine] = locateInScript(script, col);
        pointer = [repmat(' ', 1, colInLine - 1) '^-- right about here'];
        body = sprintf('%s\n\nLine %d:\n    %s\n    %s\n\n%s', ...
            opener, lineNo, lineTxt, pointer, char(err.message));
    else
        % No single column pinpoints this one (e.g. a mistake that spans
        % several statements); still explain what and why, just without a
        % snippet to point at.
        body = sprintf('%s\n\n%s', opener, char(err.message));
    end
    ME = MException('Alakazam:DefineBins', '%s', body);
end

function [lineTxt, lineNo, colInLine] = locateInScript(script, col)
%LOCATEINSCRIPT  The 1-based line number and in-line column for a character
%   offset into SCRIPT, plus that line's own text (so the caller can print a
%   caret directly under the mistake).
    col = min(max(round(col), 1), numel(script));
    upToHere  = script(1:col);
    lineNo    = 1 + numel(strfind(upToHere, newline));
    lastNL    = find(upToHere == newline, 1, 'last');
    if isempty(lastNL); lineStart = 1; else; lineStart = lastNL + 1; end
    afterHere = script(col:end);
    nextNL    = find(afterHere == newline, 1, 'first');
    if isempty(nextNL); lineEnd = numel(script); else; lineEnd = col + nextNL - 2; end
    lineTxt   = script(lineStart:lineEnd);
    colInLine = col - lineStart + 1;
end

% ======================================================================= %
%  Parser: script -> spec with .bins {index,label,text,expr} and .epoch window
% ======================================================================= %
function spec = parseSpec(script)
    script = char(script);
    try
        spec = parseSpecInner(script);
    catch err
        throw(wrapParseError(script, err));
    end
end

function spec = parseSpecInner(script)
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
        throwParseError(-1, [ ...
            'I could not find a single bin definition in this script (only ' ...
            'comments and/or let aliases, if anything). Every script needs at ' ...
            'least one line shaped like:' newline newline ...
            '    bin <number> "<label>" <expression>' newline newline ...
            'for example:' newline newline ...
            '    bin 1 "Targets" 112']);
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
                throwParseError(stmts{s}(1).pos, sprintf([ ...
                    '''%s'' is already defined earlier in this script as a let alias -- ' ...
                    'each alias name can only be defined once. Pick a different name for ' ...
                    'this one, or remove the earlier definition if it was a leftover.'], name));
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
    checkComboReferences(bins);
    spec.bins = bins;
end

function checkComboReferences(bins)
%CHECKCOMBOREFERENCES  Catch two combination-bin mistakes right after
%   parsing, rather than as an opaque error much later during Average: a
%   combination referencing a bin number that does not exist in the script,
%   and a circular reference (a bin that, directly or through others,
%   combines itself) -- a combination bin may reference another
%   combination bin (nested/interaction differences), so this is not just
%   "must reference an ordinary bin".
    byIndex = containers.Map('KeyType', 'double', 'ValueType', 'double');
    for i = 1:numel(bins); byIndex(bins(i).index) = i; end

    state = zeros(1, numel(bins));  % 0 unvisited, 1 visiting, 2 done

    function visit(i, path, atPos)
        if state(i) == 2; return; end
        if state(i) == 1
            throwParseError(atPos, sprintf([ ...
                'This combination forms a loop, so it can never be computed: %s. ' ...
                'Every combination bin needs to bottom out, eventually, in bins that ' ...
                'match events directly -- untangle that chain of references.'], ...
                strjoin([path, {sprintf('bin %g "%s"', bins(i).index, bins(i).label)}], ' -> ')));
        end
        if isempty(bins(i).combo); state(i) = 2; return; end
        state(i) = 1;
        for t = 1:numel(bins(i).combo)
            refIdx = bins(i).combo(t).bin;
            termPos = bins(i).combo(t).pos;
            if ~isKey(byIndex, refIdx)
                throwParseError(termPos, sprintf([ ...
                    'bin %g "%s" combines bin %g, but there is no bin %g in this script. ' ...
                    'Check for a typo in the bin number, or that bin %g is actually ' ...
                    'defined somewhere (combination bins may reference ordinary bins, ' ...
                    'or even other combination bins, declared anywhere in the script).'], ...
                    bins(i).index, bins(i).label, refIdx, refIdx, refIdx));
            end
            visit(byIndex(refIdx), [path, {sprintf('bin %g "%s"', bins(i).index, bins(i).label)}], termPos);
        end
        state(i) = 2;
    end
    for i = 1:numel(bins)
        visit(i, {}, -1);
    end
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
        throwParseError(label.pos + label.len, sprintf([ ...
            'bin %g "%s" has a label but nothing after it -- I need an expression ' ...
            'saying which events belong to this bin, e.g. bin %g "%s" 112, or ' ...
            'bin %g "%s" 112 and next(118) within (200,1200] ms.'], ...
            idx.val, label.val, idx.val, label.val, idx.val, label.val));
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
            throwParseError(t.pos, sprintf([ ...
                'bin %g "%s": I finished reading the expression, but there is ' ...
                'more text after it that I do not recognise as ''rt within ...'' or ' ...
                '''timelock ...''. Did you mean to combine two conditions? Adjacent ' ...
                'terms are automatically and-ed (e.g. 112 next(118)), or join them ' ...
                'explicitly with and/or.'], idx.val, label.val));
        end
    end
end

function [name, node] = parseLetStatement(stmt, aliases)
    % let <ident> = <expr>   (any bin expression: codes, relations,
    % not/and/or/parens, and earlier aliases). Spliced in wherever the alias
    % is referenced, so evalNode sees exactly the same tree it would if the
    % alias's text had been written out inline -- a relation inside an alias
    % is evaluated relative to whatever candidate event the reference site
    % is evaluated at, same as if it had not been factored out.
    [~,     rest] = expectTok(stmt, "kw", "let", 'the keyword ''let''');
    [nameT, rest] = expectTok(rest, "ident", 'a name for this alias, right after ''let''');
    name = char(nameT.val);
    if isempty(rest) || ~(rest(1).kind == "punc" && rest(1).val == "=")
        throwParseError(nameT.pos + nameT.len, sprintf([ ...
            'let %s needs an ''='' next, followed by what %s should stand for -- ' ...
            'e.g. let %s = 112, or let %s = next(118) within (200,1200] ms.'], ...
            name, name, name, name));
    end
    rest = rest(2:end);
    if isempty(rest)
        throwParseError(-1, sprintf([ ...
            'let %s = ... needs something after the ''='' -- a code, a code set, a ' ...
            'relation, or any combination of these with not/and/or, e.g. ' ...
            'let %s = {112 122} or let %s = next(118) within (200,1200] ms.'], ...
            name, name, name));
    end
    [node, k] = parseExprTokens(rest, aliases);
    if k <= numel(rest)
        throwParseError(rest(k).pos, sprintf([ ...
            'let %s: I understood everything up to here as one expression, but there ' ...
            'is more text after it that I could not fit in -- perhaps a stray ' ...
            'character, or two expressions that need ''and''/''or'' between them.'], name));
    end
end

function combo = parseCombo(T, binIndex, label)
    % <coeff>? bin <n> ( ('+'|'-') <coeff>? bin <n> )*  -> struct(coeff, bin, pos)
    combo = struct('coeff', {}, 'bin', {}, 'pos', {});
    k = 1; sgn = 1;
    while true
        coeff = sgn;
        t = tokAt(T, k);
        if t.kind == "num"; coeff = sgn * t.val; k = k + 1; t = tokAt(T, k); end
        if ~(t.kind == "kw" && t.val == "bin")
            throwParseError(t.pos, sprintf([ ...
                'bin %g "%s" is defined as a combination of other bins (it has an ' ...
                '''='' after its label), so I was expecting ''bin <number>'' here -- ' ...
                'e.g. bin 2 - bin 1 -- but found something else.'], binIndex, label));
        end
        termPos = t.pos;
        k = k + 1;
        [num, k] = scanNum(T, k);
        combo(end+1) = struct('coeff', coeff, 'bin', round(num), 'pos', termPos);
        op = tokAt(T, k);
        if op.kind == "eof"
            break;
        elseif op.kind == "punc" && op.val == "+"
            sgn = 1; k = k + 1;
        elseif op.kind == "punc" && op.val == "-"
            sgn = -1; k = k + 1;
        else
            throwParseError(op.pos, sprintf([ ...
                'bin %g "%s": after a ''bin <n>'' term in a combination, I need a ''+'' ' ...
                'or ''-'' to know how to combine the next one (or nothing, to end the ' ...
                'combination) -- e.g. bin 2 - bin 1 + bin 3.'], binIndex, label));
        end
    end
end

function [iv, k] = scanRtWindow(T, k, binIndex)
    t = tokAt(T, k);
    if ~(t.kind == "kw" && t.val == "within")
        throwParseError(t.pos, sprintf([ ...
            'bin %g: ''rt'' on its own is not enough -- it needs ''within (lo,hi] ms'' ' ...
            'right after it to say what reaction-time range to keep, e.g. ' ...
            'rt within (200,500] ms.'], binIndex));
    end
    [iv, k] = scanInterval(T, k + 1);
end

function [rel, k] = parseTimelock(T, kStart, aliases, binIndex)
    % timelock <relation>  -- reuse the expression parser, require one relation.
    [node, kLocal] = parseExprTokens(T(kStart:end), aliases);
    if ~isstruct(node) || ~strcmp(node.op, 'rel')
        throwParseError(tokAt(T, kStart).pos, sprintf([ ...
            'bin %g: ''timelock'' needs exactly one relation after it, to say which ' ...
            'neighbouring event to centre the epoch on -- e.g. timelock next(118). ' ...
            'A bare code, or a combination of terms, is not a relation on its own.'], ...
            binIndex));
    end
    rel = node;
    k   = kStart + kLocal - 1;
end

% Standalone interval scanner, shared by the epoch directive and the
% expression parser's within-window. Returns the window and the next cursor.
function [iv, k] = scanInterval(T, k)
    o = tokAt(T, k);
    if ~(o.kind == "punc" && (o.val == "(" || o.val == "["))
        throwParseError(o.pos, [ ...
            'A window needs to start with ''('' (exclusive bound) or ''['' ' ...
            '(inclusive bound), like within (200,1200] ms -- I could not find ' ...
            'either one here.']);
    end
    loOpen = (o.val == "("); k = k + 1;
    [lo, k] = scanNum(T, k);
    cComma = tokAt(T, k);
    if ~(cComma.kind == "punc" && cComma.val == ",")
        throwParseError(cComma.pos, [ ...
            'A window needs a comma between its low and high bound, e.g. ' ...
            'within (200,1200] ms -- I found the low bound, but no comma after it.']);
    end
    k = k + 1;
    [hi, k] = scanNum(T, k);
    c = tokAt(T, k);
    if ~(c.kind == "punc" && (c.val == ")" || c.val == "]"))
        throwParseError(c.pos, [ ...
            'A window needs to end with '')'' (exclusive bound) or '']'' ' ...
            '(inclusive bound), like within (200,1200] ms -- I could not find ' ...
            'either one here.']);
    end
    hiOpen = (c.val == ")"); k = k + 1;
    unit = 'ms';
    u = tokAt(T, k);
    if u.kind == "kw" && (u.val == "ms" || u.val == "samples" || u.val == "events")
        unit = char(u.val); k = k + 1;
    end
    if lo > hi
        throwParseError(o.pos, sprintf([ ...
            'This window''s low bound (%g) is greater than its high bound (%g), ' ...
            'so nothing could ever fall inside it. Windows are signed and measured ' ...
            'from the anchor (+ = later, - = earlier); did you mean %s?'], ...
            lo, hi, sprintf('(%g,%g]', min(lo,hi), max(lo,hi))));
    end
    iv = struct('lo', lo, 'hi', hi, 'loOpen', loOpen, 'hiOpen', hiOpen, 'unit', unit);
end

function [v, k] = scanNum(T, k)
    t = tokAt(T, k);
    if t.kind ~= "num"
        throwParseError(t.pos, 'I was expecting a plain number here (e.g. 200 or -1200), but did not find one.');
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
        throwParseError(tokCol(toks), sprintf('I was expecting %s here.', what));
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
        tf = (t.kind == "num") || (t.kind == "str") || (t.kind == "ident") ...
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
            throwParseError(curCol(), [ ...
                'any(code) always needs a ''within (lo,hi] ms'' window right after it ' ...
                '-- unlike next/prev/adjacent, "any" has no natural neighbour to fall ' ...
                'back on, so there is no sensible default window to search. ' ...
                'For example: any(200) within (-500,500] ms.']);
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
            throwParseError(curCol(), sprintf('I was expecting a ''%s'' right here.', w));
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
        openPos = o.pos;
        k = k + 1;
        kids = {};
        while ~(tokAt(T, k).kind == "punc" && tokAt(T, k).val == "}")
            if tokAt(T, k).kind == "eof"
                throwParseError(openPos, [ ...
                    'This ''{'' code list never closes -- I read all the way to the ' ...
                    'end of the script looking for its matching ''}''. Check for a ' ...
                    'missing closing brace, e.g. {"s11" "s22" "s33"}.']);
            end
            if tokAt(T, k).kind == "punc" && tokAt(T, k).val == ","
                k = k + 1; continue;                       % optional separators
            end
            [c, k] = scanCodeElem(T, k, aliases);
            kids{end + 1} = c;
        end
        k = k + 1;                                          % consume '}'
        if isempty(kids)
            throwParseError(openPos, [ ...
                'This ''{}'' code list is empty -- it needs at least one code inside, ' ...
                'e.g. {112 122} or {"s11" "s22"}. Remove it entirely if you meant to ' ...
                'leave this out.']);
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
            throwParseError(t.pos, sprintf([ ...
                'I don''t know what ''%s'' means -- there is no let alias by that name ' ...
                '(at least, not one defined earlier in the script). If you meant a text ' ...
                'marker, it needs quotes: "%s". If you meant an alias, define it first: ' ...
                'let %s = ...'], name, name, name));
        end
        node = aliases.(name); k = k + 1;                   % splice in the alias's expression
    else
        throwParseError(t.pos, [ ...
            'I was expecting a marker code here -- a number (112), a quoted text ' ...
            'marker ("S112"), a {...} or |-separated set of these, or the name of a ' ...
            'let alias.']);
    end
end

% ======================================================================= %
%  Tokenizer
% ======================================================================= %
function toks = tokenize(s)
    keywords = ["bin","let","rt","timelock","and","or","not", ...
                "next","prev","adjacent","any","within","ms","samples","events"];
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
                throwParseError(i, [ ...
                    'This quoted text marker never closes -- I read all the way to the ' ...
                    'end of the script looking for its matching ''"''. Check for a ' ...
                    'missing closing quote.']);
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
            throwParseError(i, sprintf([ ...
                'I don''t know what to do with the character ''%s'' here -- it is not ' ...
                'part of any code, keyword, or punctuation this language uses. If you ' ...
                'meant it as part of a text marker, wrap it in quotes, e.g. "%s".'], ...
                c, c));
        end
    end
end

function t = mkTok(kind, val, pos, len)
    t = struct('kind', kind, 'val', val, 'pos', pos, 'len', len);
end

function tf = isdigit(c)
    tf = c >= '0' && c <= '9';
end
