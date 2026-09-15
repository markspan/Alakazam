function options = FilterDialog(srate, labels, stored)
%FILTERDIALOG  Modal editor for the Filter transform. Two modes, switched by
%   a "Per-channel settings" tickbox:
%     * global (default) -- three filters (high-pass, low-pass, notch), each an
%       enable tickbox plus a frequency (Hz) and a dB rating (stopband
%       attenuation), applied to every channel;
%     * per-channel -- the same global panel STAYS visible (it is the
%       template the "Copy settings" button below it copies from, and
%       editing it live still reseeds an untouched table the first time
%       this session switches into per-channel mode -- see
%       onPerChanToggled), plus a table, one row per channel, with its own
%       leading "Filter?" tickbox (default on) plus a High-pass / Low-pass
%       / Notch frequency and dB each; a frequency of 0 (or blank) leaves
%       that one filter off for that channel, while unticking "Filter?"
%       skips the channel entirely regardless of what its own frequencies
%       say -- the direct way to mark "this channel does not need
%       filtering" at all, rather than zeroing out three fields to the
%       same effect. "Copy settings" overwrites EVERY row (unlike the
%       automatic first-switch reseed, which leaves an already-customised
%       row alone) -- a deliberate, repeatable "make every channel match
%       the panel above, right now" action.
%   Everything else about the FIR design is worked out by Filter.m.
%
%   SRATE is the sample rate (for validating against Nyquist); LABELS the
%   channel labels (for the per-channel table); STORED a previous run's options
%   (or [] on first use). Returns the options struct (.perChannel, the global
%   .highpass/.lowpass/.notch each {enabled,freq,db}, and .perChannelRows -- a
%   struct array {label, enabled, hpFreq, hpDb, lpFreq, lpDb, notchFreq,
%   notchDb}), or [] on cancel.
    nyq = srate / 2;
    labels = cellfun(@(s) char(string(s)), labels, 'UniformOutput', false);
    [accentColor, bgColor] = dialogChromeColors();
    options = [];

    defaults = struct( ...
        'highpass', struct('enabled', false, 'freq', 0.1, 'db', 40), ...
        'lowpass',  struct('enabled', false, 'freq', 30,  'db', 40), ...
        'notch',    struct('enabled', false, 'freq', 50,  'db', 40));
    seed = mergeSeed(defaults, stored);
    seedPerChannel = (isstruct(stored) && isfield(stored, 'perChannel') && logical(stored.perChannel));

    COLS = {'Filter?', 'Channel', 'High-pass (Hz)', 'HP dB', 'Low-pass (Hz)', 'LP dB', 'Notch (Hz)', 'Notch dB'};

    fig = uifigure('Name', 'Filter', 'Position', fitOnScreen([100 100 620 560]), 'Color', bgColor);
    root = uigridlayout(fig, [2 1], 'RowHeight', {40, '1x'}, 'Padding', [0 0 0 0], 'RowSpacing', 0);
    uilabel(root, 'Text', '  Filter', 'FontSize', 14, 'FontWeight', 'bold', ...
        'FontColor', [1 1 1], 'BackgroundColor', accentColor, 'VerticalAlignment', 'center');
    % Every row below is given an EXPLICIT Layout.Row (not left to
    % uigridlayout's own auto-placement): globalPanel/copyRow/chanTable's
    % visibility and even row HEIGHT change at runtime (see refreshMode),
    % which is only safe to reason about when nothing relies on an
    % implicit "next slot" placement alongside them.
    outer = uigridlayout(root, [6 1], 'RowHeight', {'fit', 'fit', 'fit', 'fit', '1x', 'fit'}, 'Padding', [10 10 10 10]);

    descLabel = uilabel(outer, 'Text', [ ...
        'FIR windowed-sinc, zero-phase filtering. Give each filter a frequency and a dB rating ' ...
        '(the stopband attenuation); the order and transition band are automatic. Filter the ' ...
        'continuous recording before epoching.'], 'WordWrap', 'on');
    descLabel.Layout.Row = 1;

    perChanBox = uicheckbox(outer, 'Text', 'Per-channel settings', 'Value', seedPerChannel);
    perChanBox.Layout.Row = 2;
    perChanBox.ValueChangedFcn = @(~, ~) onPerChanToggled();
    hasReseededFromGlobal = false; % see onPerChanToggled

    % --- Global panel (row 3, ALWAYS visible -- also per-channel mode's
    % "Copy settings" template, see copyRow below) ---
    globalPanel = uigridlayout(outer, [4 3], 'ColumnWidth', {150, '1x', '1x'}, ...
        'RowHeight', repmat({'fit'}, 1, 4), 'RowSpacing', 6, 'ColumnSpacing', 10, 'Padding', [0 0 0 0]);
    globalPanel.Layout.Row = 3;
    uilabel(globalPanel, 'Text', '');
    uilabel(globalPanel, 'Text', 'Frequency (Hz)', 'FontWeight', 'bold', 'HorizontalAlignment', 'center');
    uilabel(globalPanel, 'Text', 'Attenuation (dB)', 'FontWeight', 'bold', 'HorizontalAlignment', 'center');
    rowDefs = struct('key', {'highpass', 'lowpass', 'notch'}, 'label', {'High-pass', 'Low-pass', 'Notch'});
    ctl = struct();
    for i = 1:numel(rowDefs)
        key = rowDefs(i).key;
        cb = uicheckbox(globalPanel, 'Text', rowDefs(i).label, 'Value', seed.(key).enabled);
        f  = uieditfield(globalPanel, 'numeric', 'Value', seed.(key).freq, 'Limits', [0 Inf], 'LowerLimitInclusive', 'off');
        d  = uieditfield(globalPanel, 'numeric', 'Value', seed.(key).db,   'Limits', [0 Inf], 'LowerLimitInclusive', 'off');
        cb.ValueChangedFcn = @(src, ~) setRowEnabled(f, d, src.Value);
        setRowEnabled(f, d, cb.Value);
        ctl.(key) = struct('cb', cb, 'freq', f, 'db', d);
    end

    % --- "Copy settings" (row 4, per-channel mode only) ---
    copyRow = uigridlayout(outer, [1 2], 'ColumnWidth', {140, '1x'}, 'Padding', [0 0 0 0]);
    copyRow.Layout.Row = 4;
    uibutton(copyRow, 'Text', 'Copy settings', ...
        'Tooltip', 'Copy the panel above to every channel below, replacing its current settings.', ...
        'ButtonPushedFcn', @(~, ~) onCopySettings());
    uilabel(copyRow, 'Text', '');

    % --- Per-channel table (row 5, per-channel mode only) ---
    chanTable = uitable(outer, 'ColumnName', COLS, 'ColumnEditable', [true false true(1, 6)], ...
        'ColumnFormat', {'logical', 'char', 'numeric', 'numeric', 'numeric', 'numeric', 'numeric', 'numeric'}, ...
        'Data', seedTable(labels, seed, stored));
    chanTable.Layout.Row = 5;

    buttons = uigridlayout(outer, [1 3], 'ColumnWidth', {'1x', 90, 90}, 'Padding', [0 4 0 0]);
    buttons.Layout.Row = 6;
    uilabel(buttons, 'Text', '');
    uibutton(buttons, 'Text', 'Cancel', 'ButtonPushedFcn', @(~, ~) onCancel());
    uibutton(buttons, 'Text', 'OK', 'BackgroundColor', accentColor, ...
        'FontColor', [1 1 1], 'ButtonPushedFcn', @(~, ~) onOK());
    fig.CloseRequestFcn = @(~, ~) onCancel();

    refreshMode();
    uiwait(fig);

    function refreshMode()
        % globalPanel stays visible in both modes now -- it doubles as the
        % per-channel table's own "Copy settings" template, so hiding it
        % there would hide the very thing that button reads from.
        per = logical(perChanBox.Value);
        onoff = {'on', 'off'};
        copyRow.Visible   = onoff{2 - per};
        chanTable.Visible = onoff{2 - per};
        if per
            outer.RowHeight{4} = 'fit';
            outer.RowHeight{5} = '1x';
        else
            outer.RowHeight{4} = 0;
            outer.RowHeight{5} = 0;
        end
    end

    function onCopySettings()
        % Unlike onPerChanToggled's automatic first-switch reseed (which
        % leaves an already-customised row alone), this is a deliberate,
        % repeatable action: overwrite EVERY row with the panel above,
        % right now -- so stored.perChannelRows is deliberately not
        % consulted here (pass [] where onPerChanToggled passes stored).
        chanTable.Data = seedTable(labels, currentGlobalSeed(), []);
    end

    function onPerChanToggled()
        % The table was seeded once, at construction, from STORED (the
        % last run's remembered settings) -- so switching to per-channel
        % after editing the global fields would silently show whatever was
        % remembered, not what was just typed. Reseed from the CURRENT
        % (live) global control values the first time this session
        % switches into per-channel mode, so those edits carry over as
        % every channel's starting default -- stored.perChannelRows, when
        % present, still wins per channel by label, same as at
        % construction (see seedTable). Only the FIRST such switch:
        % toggling back to global and forward again must not silently
        % discard a per-channel edit made in between.
        if logical(perChanBox.Value) && ~hasReseededFromGlobal
            chanTable.Data = seedTable(labels, currentGlobalSeed(), stored);
            hasReseededFromGlobal = true;
        end
        refreshMode();
    end

    function s = currentGlobalSeed()
        s = struct();
        for k = 1:numel(rowDefs)
            key = rowDefs(k).key;
            s.(key) = struct('enabled', logical(ctl.(key).cb.Value), ...
                'freq', ctl.(key).freq.Value, 'db', ctl.(key).db.Value);
        end
    end

    function onOK()
        per = logical(perChanBox.Value);
        out = struct('perChannel', per);

        % Always carry the global settings through (so the panel round-trips).
        for k = 1:numel(rowDefs)
            key = rowDefs(k).key;
            en = logical(ctl.(key).cb.Value); f = ctl.(key).freq.Value; d = ctl.(key).db.Value;
            if ~per && en && ~validOne(rowDefs(k).label, key, f, d); return; end
            out.(key) = struct('enabled', en, 'freq', f, 'db', d);
        end

        % Per-channel rows. Column 1 is the "Filter?" tickbox: unticked
        % skips the channel entirely, so its own frequency/dB fields are
        % not even validated -- whatever is left in them does not matter
        % once the channel is marked as not needing filtering.
        data = chanTable.Data;
        rows = repmat(struct('label', '', 'enabled', true, 'hpFreq', 0, 'hpDb', 0, 'lpFreq', 0, 'lpDb', 0, ...
            'notchFreq', 0, 'notchDb', 0), 1, size(data, 1));
        for r = 1:size(data, 1)
            en  = logical(data{r, 1});
            lab = char(string(data{r, 2}));
            trip = {'High-pass', 'x', 3, 4; 'Low-pass', 'x', 5, 6; 'Notch', 'notch', 7, 8};
            for t = 1:3
                fr = num0(data{r, trip{t, 3}}); db = num0(data{r, trip{t, 4}});
                if per && en && fr > 0
                    if ~validOne(sprintf('%s %s', lab, trip{t, 1}), trip{t, 2}, fr, db)
                        return;
                    end
                end
            end
            rows(r) = struct('label', lab, 'enabled', en, 'hpFreq', num0(data{r, 3}), 'hpDb', num0(data{r, 4}), ...
                'lpFreq', num0(data{r, 5}), 'lpDb', num0(data{r, 6}), ...
                'notchFreq', num0(data{r, 7}), 'notchDb', num0(data{r, 8}));
        end
        out.perChannelRows = rows;

        options = out;
        uiresume(fig); delete(fig);
    end

    function ok = validOne(name, key, f, d)
        ok = false;
        if ~(f > 0 && f < nyq)
            uialert(fig, sprintf('I''m afraid %s frequency (%.4g Hz) needs to sit between 0 and Nyquist (%.4g Hz).', ...
                name, f, nyq), 'Check the filters'); return;
        end
        if strcmp(key, 'notch') && (f - 1 <= 0 || f + 1 >= nyq)
            uialert(fig, sprintf('I''m afraid %s (%.4g Hz) sits too close to 0 or Nyquist to use for a notch.', name, f), ...
                'Check the filters'); return;
        end
        if ~(d > 0)
            uialert(fig, sprintf('I''m afraid %s attenuation (dB) needs to be a positive value.', name), 'Check the filters'); return;
        end
        ok = true;
    end

    function onCancel()
        uiresume(fig); delete(fig);
    end
end

% ======================================================================= %
function data = seedTable(labels, seed, stored)
%SEEDTABLE  Per-channel table data: from a stored per-channel set if present,
%   else every channel seeded from the global settings (0 = off). The
%   leading "Filter?" column defaults to true (every channel filtered) --
%   TransTools.FieldOr covers a stored row saved before that column
%   existed, which has no .enabled field of its own to read.
    n = numel(labels);
    data = cell(n, 8);
    storedRows = [];
    if isstruct(stored) && isfield(stored, 'perChannelRows') && ~isempty(stored.perChannelRows)
        storedRows = stored.perChannelRows;
    end
    gHp = seed.highpass.enabled * seed.highpass.freq;
    gLp = seed.lowpass.enabled  * seed.lowpass.freq;
    gNo = seed.notch.enabled    * seed.notch.freq;
    for i = 1:n
        row = {true, labels{i}, gHp, seed.highpass.db, gLp, seed.lowpass.db, gNo, seed.notch.db};
        if ~isempty(storedRows)
            hit = find(strcmpi({storedRows.label}, labels{i}), 1);
            if ~isempty(hit)
                s = storedRows(hit);
                row = {TransTools.FieldOr(s, 'enabled', true), labels{i}, s.hpFreq, s.hpDb, s.lpFreq, s.lpDb, s.notchFreq, s.notchDb};
            end
        end
        data(i, :) = row;
    end
end

function setRowEnabled(freqField, dbField, on)
    state = 'off'; if on; state = 'on'; end
    freqField.Enable = state; dbField.Enable = state;
end

function v = num0(x)
    if isnumeric(x) && ~isempty(x) && ~isnan(x); v = double(x); else; v = 0; end
end

function seed = mergeSeed(defaults, stored)
    seed = defaults;
    if ~isstruct(stored); return; end
    for key = {'highpass', 'lowpass', 'notch'}
        k = key{1};
        if isfield(stored, k) && isstruct(stored.(k))
            s = stored.(k);
            if isfield(s, 'enabled'); seed.(k).enabled = logical(s.enabled); end
            if isfield(s, 'freq') && isnumeric(s.freq) && ~isempty(s.freq); seed.(k).freq = s.freq; end
            if isfield(s, 'db')   && isnumeric(s.db)   && ~isempty(s.db);   seed.(k).db   = s.db;   end
        end
    end
end
