function options = FilterDialog(srate, labels, stored)
%FILTERDIALOG  Modal editor for the Filter transform. Two modes, switched by
%   a "Per-channel settings" tickbox:
%     * global (default) -- three filters (high-pass, low-pass, notch), each an
%       enable tickbox plus a frequency (Hz) and a dB rating (stopband
%       attenuation), applied to every channel;
%     * per-channel -- a table, one row per channel, with a High-pass /
%       Low-pass / Notch frequency and dB each; a frequency of 0 (or blank)
%       leaves that filter off for that channel.
%   Everything else about the FIR design is worked out by Filter.m.
%
%   SRATE is the sample rate (for validating against Nyquist); LABELS the
%   channel labels (for the per-channel table); STORED a previous run's options
%   (or [] on first use). Returns the options struct (.perChannel, the global
%   .highpass/.lowpass/.notch each {enabled,freq,db}, and .perChannelRows -- a
%   struct array {label, hpFreq, hpDb, lpFreq, lpDb, notchFreq, notchDb}), or []
%   on cancel.
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

    COLS = {'Channel', 'High-pass (Hz)', 'HP dB', 'Low-pass (Hz)', 'LP dB', 'Notch (Hz)', 'Notch dB'};

    fig = uifigure('Name', 'Filter', 'Position', [100 100 620 410], 'Color', bgColor);
    root = uigridlayout(fig, [2 1], 'RowHeight', {40, '1x'}, 'Padding', [0 0 0 0], 'RowSpacing', 0);
    uilabel(root, 'Text', '  Filter', 'FontSize', 14, 'FontWeight', 'bold', ...
        'FontColor', [1 1 1], 'BackgroundColor', accentColor, 'VerticalAlignment', 'center');
    outer = uigridlayout(root, [4 1], 'RowHeight', {'fit', 'fit', '1x', 'fit'}, 'Padding', [10 10 10 10]);

    uilabel(outer, 'Text', [ ...
        'FIR windowed-sinc, zero-phase filtering. Give each filter a frequency and a dB rating ' ...
        '(the stopband attenuation); the order and transition band are automatic. Filter the ' ...
        'continuous recording before epoching.'], 'WordWrap', 'on');

    perChanBox = uicheckbox(outer, 'Text', 'Per-channel settings', 'Value', seedPerChannel);
    perChanBox.ValueChangedFcn = @(~, ~) refreshMode();

    % --- Global panel (row 3) ---
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

    % --- Per-channel table (row 3, shown when toggled on) ---
    chanTable = uitable(outer, 'ColumnName', COLS, 'ColumnEditable', [false true(1, 6)], ...
        'ColumnFormat', {'char', 'numeric', 'numeric', 'numeric', 'numeric', 'numeric', 'numeric'}, ...
        'Data', seedTable(labels, seed, stored));
    chanTable.Layout.Row = 3;

    buttons = uigridlayout(outer, [1 3], 'ColumnWidth', {'1x', 90, 90}, 'Padding', [0 4 0 0]);
    uilabel(buttons, 'Text', '');
    uibutton(buttons, 'Text', 'Cancel', 'ButtonPushedFcn', @(~, ~) onCancel());
    uibutton(buttons, 'Text', 'OK', 'BackgroundColor', accentColor, ...
        'FontColor', [1 1 1], 'ButtonPushedFcn', @(~, ~) onOK());
    fig.CloseRequestFcn = @(~, ~) onCancel();

    refreshMode();
    uiwait(fig);

    function refreshMode()
        per = logical(perChanBox.Value);
        onoff = {'on', 'off'};
        globalPanel.Visible = onoff{1 + per};
        chanTable.Visible   = onoff{2 - per};
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

        % Per-channel rows.
        data = chanTable.Data;
        rows = repmat(struct('label', '', 'hpFreq', 0, 'hpDb', 0, 'lpFreq', 0, 'lpDb', 0, ...
            'notchFreq', 0, 'notchDb', 0), 1, size(data, 1));
        for r = 1:size(data, 1)
            lab = char(string(data{r, 1}));
            trip = {'High-pass', 'x', 2, 3; 'Low-pass', 'x', 4, 5; 'Notch', 'notch', 6, 7};
            for t = 1:3
                fr = num0(data{r, trip{t, 3}}); db = num0(data{r, trip{t, 4}});
                if per && fr > 0
                    if ~validOne(sprintf('%s %s', lab, trip{t, 1}), trip{t, 2}, fr, db)
                        return;
                    end
                end
            end
            rows(r) = struct('label', lab, 'hpFreq', num0(data{r, 2}), 'hpDb', num0(data{r, 3}), ...
                'lpFreq', num0(data{r, 4}), 'lpDb', num0(data{r, 5}), ...
                'notchFreq', num0(data{r, 6}), 'notchDb', num0(data{r, 7}));
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
%   else every channel seeded from the global settings (0 = off).
    n = numel(labels);
    data = cell(n, 7);
    storedRows = [];
    if isstruct(stored) && isfield(stored, 'perChannelRows') && ~isempty(stored.perChannelRows)
        storedRows = stored.perChannelRows;
    end
    gHp = seed.highpass.enabled * seed.highpass.freq;
    gLp = seed.lowpass.enabled  * seed.lowpass.freq;
    gNo = seed.notch.enabled    * seed.notch.freq;
    for i = 1:n
        row = {labels{i}, gHp, seed.highpass.db, gLp, seed.lowpass.db, gNo, seed.notch.db};
        if ~isempty(storedRows)
            hit = find(strcmpi({storedRows.label}, labels{i}), 1);
            if ~isempty(hit)
                s = storedRows(hit);
                row = {labels{i}, s.hpFreq, s.hpDb, s.lpFreq, s.lpDb, s.notchFreq, s.notchDb};
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
