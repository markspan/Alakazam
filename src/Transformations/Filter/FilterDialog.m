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
%       High-pass / Low-pass / Notch enable tickbox, frequency and dB each
%       -- the same {enable, freq, db} triple the global panel uses, just
%       once per channel, so a channel's three filters are independent of
%       each other: unticking just Notch, say, leaves that channel's own
%       High-pass and Low-pass running. A frequency of 0 (or blank) also
%       leaves that one filter off, so an old row saved before these
%       tickboxes existed still replays correctly (see seedTable/FieldOr).
%       "Copy settings" overwrites EVERY row (unlike the automatic
%       first-switch reseed, which leaves an already-customised row
%       alone) -- a deliberate, repeatable "make every channel match the
%       panel above, right now" action.
%   Everything else about the FIR design is worked out by Filter.m.
%
%   In global mode, a plot under the three filters shows the frequency
%   response of the enabled ones together (filterFrequencyResponse, from the
%   same kernels Filter applies): the gain in dB from 0 Hz to Nyquist, with a
%   dotted line at -6 dB, the level at which each cutoff is defined. It shows
%   which frequencies pass, where they are cut off, and how far the rest is
%   attenuated, and is redrawn whenever a filter is ticked or a frequency or
%   dB changes. A setting Filter would refuse is shown there instead, with
%   the reason. Per-channel mode has no such plot, since every channel may
%   have its own filters.
%
%   SRATE is the sample rate (for validating against Nyquist); LABELS the
%   channel labels (for the per-channel table); STORED a previous run's options
%   (or [] on first use). Returns the options struct (.perChannel, the global
%   .highpass/.lowpass/.notch each {enabled,freq,db}, and .perChannelRows -- a
%   struct array {label, hpEnabled, hpFreq, hpDb, lpEnabled, lpFreq, lpDb,
%   notchEnabled, notchFreq, notchDb}), or [] on cancel.
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

    COLS = {'Channel', 'HP?', 'HP (Hz)', 'HP dB', 'LP?', 'LP (Hz)', 'LP dB', 'Notch?', 'Notch (Hz)', 'Notch dB'};

    fig = uifigure('Name', 'Filter', 'Position', fitOnScreen([100 100 700 620]), 'Color', bgColor);
    root = uigridlayout(fig, [2 1], 'RowHeight', {40, '1x'}, 'Padding', [0 0 0 0], 'RowSpacing', 0);
    uilabel(root, 'Text', '  Filter', 'FontSize', 14, 'FontWeight', 'bold', ...
        'FontColor', [1 1 1], 'BackgroundColor', accentColor, 'VerticalAlignment', 'center');
    % Every row below is given an EXPLICIT Layout.Row (not left to
    % uigridlayout's own auto-placement): globalPanel/copyRow/chanTable's
    % visibility and even row HEIGHT change at runtime (see refreshMode),
    % which is only safe to reason about when nothing relies on an
    % implicit "next slot" placement alongside them.
    outer = uigridlayout(root, [7 1], 'RowHeight', {'fit', 'fit', 'fit', '1x', 'fit', '1x', 'fit'}, 'Padding', [10 10 10 10]);

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
        cb.ValueChangedFcn = @(src, ~) onFilterToggled(f, d, src.Value);
        f.ValueChangedFcn = @(~, ~) updateResponse();
        d.ValueChangedFcn = @(~, ~) updateResponse();
        setRowEnabled(f, d, cb.Value);
        ctl.(key) = struct('cb', cb, 'freq', f, 'db', d);
    end

    % --- Frequency response of the global filters together (row 4, global
    % mode only; the per-channel table has a filter per channel instead).
    % The row takes all the height the global mode has left, so the plot
    % shrinks with the window rather than overflow it. ---
    responsePanel = uigridlayout(outer, [2 1], 'RowHeight', {'fit', '1x'}, ...
        'RowSpacing', 2, 'Padding', [0 0 0 0]);
    responsePanel.Layout.Row = 4;
    frequencyCaption = uilabel(responsePanel, 'Text', '', 'WordWrap', 'on', 'FontSize', 11, ...
        'Tag', 'FrequencyCaption');
    frequencyAxes = uiaxes(responsePanel, 'FontSize', 9, 'Tag', 'FrequencyAxes');
    xlabel(frequencyAxes, 'Frequency (Hz)');
    ylabel(frequencyAxes, 'Gain (dB)');
    box(frequencyAxes, 'on');

    % --- "Copy settings" (row 5, per-channel mode only) ---
    copyRow = uigridlayout(outer, [1 2], 'ColumnWidth', {140, '1x'}, 'Padding', [0 0 0 0]);
    copyRow.Layout.Row = 5;
    uibutton(copyRow, 'Text', 'Copy settings', ...
        'Tooltip', 'Copy the panel above to every channel below, replacing its current settings.', ...
        'ButtonPushedFcn', @(~, ~) onCopySettings());
    uilabel(copyRow, 'Text', '');

    % --- Per-channel table (row 6, per-channel mode only) ---
    chanTable = uitable(outer, 'ColumnName', COLS, 'ColumnEditable', [false true(1, 9)], ...
        'ColumnFormat', {'char', 'logical', 'numeric', 'numeric', 'logical', 'numeric', 'numeric', 'logical', 'numeric', 'numeric'}, ...
        'Data', seedTable(labels, seed, stored));
    chanTable.Layout.Row = 6;

    buttons = uigridlayout(outer, [1 3], 'ColumnWidth', {'1x', 90, 90}, 'Padding', [0 4 0 0]);
    buttons.Layout.Row = 7;
    uilabel(buttons, 'Text', '');
    uibutton(buttons, 'Text', 'Cancel', 'ButtonPushedFcn', @(~, ~) onCancel());
    uibutton(buttons, 'Text', 'OK', 'BackgroundColor', accentColor, ...
        'FontColor', [1 1 1], 'ButtonPushedFcn', @(~, ~) onOK());
    fig.CloseRequestFcn = @(~, ~) onCancel();

    refreshMode();
    updateResponse();
    uiwait(fig);

    function refreshMode()
        % globalPanel stays visible in both modes now -- it doubles as the
        % per-channel table's own "Copy settings" template, so hiding it
        % there would hide the very thing that button reads from.
        per = logical(perChanBox.Value);
        onoff = {'on', 'off'};
        copyRow.Visible       = onoff{2 - per};
        chanTable.Visible     = onoff{2 - per};
        responsePanel.Visible = onoff{1 + per};
        if per
            outer.RowHeight{4} = 0;
            outer.RowHeight{5} = 'fit';
            outer.RowHeight{6} = '1x';
        else
            outer.RowHeight{4} = '1x';
            outer.RowHeight{5} = 0;
            outer.RowHeight{6} = 0;
        end
    end

    function onFilterToggled(freqField, dbField, on)
        setRowEnabled(freqField, dbField, on);
        updateResponse();
    end

    function updateResponse()
    %UPDATERESPONSE  Redraw the frequency response of the ticked filters, or
    %   say in its caption why it cannot be drawn: none ticked, or a setting
    %   Filter would refuse (the message is Filter's own).
        cla(frequencyAxes);
        settings = currentGlobalSeed();
        if ~any(cellfun(@(key) settings.(key).enabled, {'highpass', 'lowpass', 'notch'}))
            frequencyCaption.Text = 'No filter is ticked, so the data are left as they are.';
            return;
        end
        try
            [frequencies, gain] = filterFrequencyResponse(settings, srate);
        catch err
            frequencyCaption.Text = err.message;
            return;
        end

        plotFrequencyResponse(frequencyAxes, frequencies, gain, gainFloorDb(settings), accentColor);
        frequencyCaption.Text = sprintf(['Frequency response of the ticked filters together, ' ...
            'from 0 Hz to Nyquist (%g Hz). The dotted line is at %.0f dB, where each cutoff sits.'], ...
            nyq, cutoffLevelDb());
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

        % Per-channel rows. Each filter has its own tickbox now (columns
        % 2/5/8), independent of the other two on the same channel -- a
        % row's own frequency/dB pair is only validated when ITS tickbox
        % is ticked AND its frequency is nonzero; an unticked filter's
        % leftover numbers do not matter, same reasoning as the global
        % panel's own disabled fields.
        data = chanTable.Data;
        rows = repmat(struct('label', '', 'hpEnabled', true, 'hpFreq', 0, 'hpDb', 0, ...
            'lpEnabled', true, 'lpFreq', 0, 'lpDb', 0, ...
            'notchEnabled', true, 'notchFreq', 0, 'notchDb', 0), 1, size(data, 1));
        trip = {'High-pass', 'x', 2, 3, 4; 'Low-pass', 'x', 5, 6, 7; 'Notch', 'notch', 8, 9, 10};
        for r = 1:size(data, 1)
            lab = char(string(data{r, 1}));
            en = false(1, 3); fr = zeros(1, 3); db = zeros(1, 3);
            for t = 1:3
                en(t) = logical(data{r, trip{t, 3}});
                fr(t) = num0(data{r, trip{t, 4}});
                db(t) = num0(data{r, trip{t, 5}});
                if per && en(t) && fr(t) > 0
                    if ~validOne(sprintf('%s %s', lab, trip{t, 1}), trip{t, 2}, fr(t), db(t))
                        return;
                    end
                end
            end
            rows(r) = struct('label', lab, ...
                'hpEnabled', en(1), 'hpFreq', fr(1), 'hpDb', db(1), ...
                'lpEnabled', en(2), 'lpFreq', fr(2), 'lpDb', db(2), ...
                'notchEnabled', en(3), 'notchFreq', fr(3), 'notchDb', db(3));
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
%   else every channel seeded from the global settings -- BOTH the enable
%   tickbox and the frequency/dB carry straight across per filter (unlike
%   the old single-checkbox design, a disabled global filter's own
%   frequency/dB are not lost, just shown unticked, so re-enabling a
%   channel's copy of it does not need retyping). TransTools.FieldOr
%   covers a stored row saved before these three tickboxes existed (the
%   original design's single .enabled, or no enable concept at all),
%   which has no .hpEnabled/.lpEnabled/.notchEnabled of its own to read --
%   defaults to true, matching a frequency-of-0-means-off row's own
%   existing behaviour (see Filter.m's applyPerChannel).
    n = numel(labels);
    data = cell(n, 10);
    storedRows = [];
    if isstruct(stored) && isfield(stored, 'perChannelRows') && ~isempty(stored.perChannelRows)
        storedRows = stored.perChannelRows;
    end
    for i = 1:n
        row = {labels{i}, seed.highpass.enabled, seed.highpass.freq, seed.highpass.db, ...
                          seed.lowpass.enabled,  seed.lowpass.freq,  seed.lowpass.db, ...
                          seed.notch.enabled,    seed.notch.freq,    seed.notch.db};
        if ~isempty(storedRows)
            hit = find(strcmpi({storedRows.label}, labels{i}), 1);
            if ~isempty(hit)
                s = storedRows(hit);
                row = {labels{i}, TransTools.FieldOr(s, 'hpEnabled', true),    s.hpFreq,    s.hpDb, ...
                                   TransTools.FieldOr(s, 'lpEnabled', true),    s.lpFreq,    s.lpDb, ...
                                   TransTools.FieldOr(s, 'notchEnabled', true), s.notchFreq, s.notchDb};
            end
        end
        data(i, :) = row;
    end
end

function plotFrequencyResponse(ax, f, gain, floorDb, color)
%PLOTFREQUENCYRESPONSE  Draw a linear GAIN against F (Hz) on AX as dB.
%   The frequency axis runs from F(1), 0 Hz, to F(end), the Nyquist
%   frequency. The gain axis runs from FLOORDB to a little above 0 dB, and
%   the gain is clamped to FLOORDB, since a stopband's exact zeros are -Inf
%   dB and would leave gaps in the curve. A dotted line marks the cutoff
%   level (cutoffLevelDb) under the curve, where it can be read off.
    HEADROOM_DB = 5;   % room above 0 dB for passband ripple
    gainDb = max(20 * log10(gain), floorDb);

    plot(ax, [f(1), f(end)], [1, 1] * cutoffLevelDb(), ':', ...
        'Color', [0.5 0.5 0.5], 'LineWidth', 1, 'Tag', 'CutoffLevel');
    hold(ax, 'on');
    plot(ax, f, gainDb, 'Color', color, 'LineWidth', 1, 'Tag', 'FrequencyResponse');
    hold(ax, 'off');
    xlim(ax, [f(1), f(end)]);
    ylim(ax, [floorDb, HEADROOM_DB]);
    grid(ax, 'on');
end

function floorDb = gainFloorDb(settings)
%GAINFLOORDB  The bottom of the gain axis for the global SETTINGS: 20 dB
%   below the deepest attenuation among the ticked filters, rounded down to
%   a multiple of 10 dB, so each stopband is seen in full with room below
%   its ripple.
    MARGIN_DB = 20;
    deepest = 0;
    for key = {'highpass', 'lowpass', 'notch'}
        s = settings.(key{1});
        if s.enabled
            deepest = max(deepest, s.db);
        end
    end
    floorDb = -10 * ceil((deepest + MARGIN_DB) / 10);
end

function level = cutoffLevelDb()
%CUTOFFLEVELDB  The gain, in dB, at which a windowed-sinc filter's cutoff
%   is defined: one half, or about -6 dB, the centre of its transition band
%   (Widmann et al., 2015), as designFilterKernel designs it.
    level = 20 * log10(0.5);
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
            % Only a positive value is taken: the fields refuse 0, and a
            % filter that is off is often stored with 0 by a script (Filter
            % never reads the numbers of a filter that is off), which used
            % to stop this dialog from opening at all.
            if isfield(s, 'freq') && isnumeric(s.freq) && isscalar(s.freq) && s.freq > 0; seed.(k).freq = s.freq; end
            if isfield(s, 'db')   && isnumeric(s.db)   && isscalar(s.db)   && s.db > 0;   seed.(k).db   = s.db;   end
        end
    end
end
