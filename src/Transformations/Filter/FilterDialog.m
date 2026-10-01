function options = FilterDialog(srate, labels, stored)
%FILTERDIALOG  Modal editor for the Filter transform. Two modes, switched by
%   a "Per-channel settings" tickbox:
%     * global (default) -- three filters (high-pass, low-pass, notch), each an
%       enable tickbox plus a frequency (Hz) and a dB rating (stopband
%       attenuation), and the rest of its design (see DESIGN below), applied
%       to every channel, and a fourth, a filter made in MATLAB's Filter
%       Designer (see DESIGNED below);
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
%   DESIGN. Each global filter also shows its transition band, passband
%   ripple and order, and a notch its stop band's width (filterDesign).
%   With Automatic ticked, as by default, the transition band and the order
%   follow from the frequency and the attenuation as they always have. With
%   it unticked they can be set, and the others follow as EEGLAB's firfilt
%   ties them: the attenuation and the ripple are one deviation in two
%   units, an edited transition band, attenuation or ripple gives the order
%   it needs (firwsord), and an edited order the transition band it implies
%   (invfirwsord), the attenuation kept. The per-channel table designs
%   automatically.
%
%   DESIGNED. "Open Filter Designer" starts MATLAB's Filter Designer app;
%   "Use exported filter" takes a filter it exported (a digitalFilter, in
%   the workspace or a MAT-file, pickDesignedFilter), which Filter applies
%   after the other three, to every channel in either mode. Its
%   coefficients are kept in the options, so replaying needs neither the app
%   nor the object.
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
%   .highpass/.lowpass/.notch each {enabled,freq,db,auto,transition,order}
%   (the notch also .width), .designed (designedFilterFromObject's struct,
%   or one with enabled false), and .perChannelRows -- a
%   struct array {label, hpEnabled, hpFreq, hpDb, lpEnabled, lpFreq, lpDb,
%   notchEnabled, notchFreq, notchDb}), or [] on cancel.
    nyq = srate / 2;
    labels = cellfun(@(s) char(string(s)), labels, 'UniformOutput', false);
    [accentColor, bgColor] = dialogChromeColors();
    options = [];

    defaults = struct( ...
        'highpass', struct('enabled', false, 'freq', 0.1, 'db', 40, 'auto', true, 'transition', [], 'order', []), ...
        'lowpass',  struct('enabled', false, 'freq', 30,  'db', 40, 'auto', true, 'transition', [], 'order', []), ...
        'notch',    struct('enabled', false, 'freq', 50,  'db', 40, 'auto', true, 'transition', [], 'order', [], 'width', 2));
    seed = mergeSeed(defaults, stored);
    designed = struct('enabled', false);
    if isstruct(stored) && isfield(stored, 'designed') && isstruct(stored.designed) ...
            && isfield(stored.designed, 'kind')
        designed = stored.designed;
    end
    seedPerChannel = (isstruct(stored) && isfield(stored, 'perChannel') && logical(stored.perChannel));

    COLS = {'Channel', 'HP?', 'HP (Hz)', 'HP dB', 'LP?', 'LP (Hz)', 'LP dB', 'Notch?', 'Notch (Hz)', 'Notch dB'};

    fig = uifigure('Name', 'Filter', 'Position', fitOnScreen([100 100 940 680]), 'Color', bgColor);
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
        '(the stopband attenuation). With Automatic ticked the transition band and the order follow; ' ...
        'untick it to set them, and the rest follows as EEGLAB''s firfilt ties them. A filter made ' ...
        'in MATLAB''s Filter Designer can be added below. Filter the continuous recording before ' ...
        'epoching.'], 'WordWrap', 'on');
    descLabel.Layout.Row = 1;

    perChanBox = uicheckbox(outer, 'Text', 'Per-channel settings', 'Value', seedPerChannel);
    perChanBox.Layout.Row = 2;
    perChanBox.ValueChangedFcn = @(~, ~) onPerChanToggled();
    hasReseededFromGlobal = false; % see onPerChanToggled

    % --- Global panel (row 3, ALWAYS visible -- also per-channel mode's
    % "Copy settings" template, see copyRow below) ---
    globalPanel = uigridlayout(outer, [5 8], 'ColumnWidth', {110, '1x', 72, '1x', '1x', '1x', '1x', '1x'}, ...
        'RowHeight', repmat({'fit'}, 1, 5), 'RowSpacing', 6, 'ColumnSpacing', 8, 'Padding', [0 0 0 0]);
    globalPanel.Layout.Row = 3;
    headers = {'', 'Frequency (Hz)', 'Automatic', 'Transition (Hz)', 'Attenuation (dB)', ...
        'Ripple (dB)', 'Order', 'Stop width (Hz)'};
    tips = {'', 'The cutoff, where the gain is one half (-6 dB); for the notch, the centre of its stop band.', ...
        'Ticked: the transition band and the order follow from the frequency and the attenuation.', ...
        'The width of the band in which the gain falls from passband to stopband.', ...
        'How far the stopband is attenuated.', ...
        'The largest deviation in the passband; the same deviation as the attenuation, in other units.', ...
        'The filter order: the kernel has this many taps plus one. Always even.', ...
        'The notch''s stop band.'};
    for h = 1:numel(headers)
        uilabel(globalPanel, 'Text', headers{h}, 'FontWeight', 'bold', 'HorizontalAlignment', 'center', ...
            'WordWrap', 'on', 'Tooltip', tips{h});
    end
    rowDefs = struct('key', {'highpass', 'lowpass', 'notch'}, 'label', {'High-pass', 'Low-pass', 'Notch'}, ...
        'type', {'high', 'low', 'notch'});
    ctl = struct();
    for i = 1:numel(rowDefs)
        key = rowDefs(i).key;
        c = struct();
        c.cb = uicheckbox(globalPanel, 'Text', rowDefs(i).label, 'Value', seed.(key).enabled);
        c.freq = numberField(globalPanel, seed.(key).freq, [0 Inf], '%.4g', [key 'Freq']);
        c.auto = uicheckbox(globalPanel, 'Text', '', 'Value', logical(seed.(key).auto), 'Tag', [key 'Auto']);
        c.trans = numberField(globalPanel, 1, [0 Inf], '%.4g', [key 'Transition']);
        c.db = numberField(globalPanel, seed.(key).db, [0 Inf], '%.4g', [key 'Db']);
        c.ripple = numberField(globalPanel, 0.1, [0 Inf], '%.3g', [key 'Ripple']);
        c.order = numberField(globalPanel, 2, [2 Inf], '%d', [key 'Order']);
        c.order.RoundFractionalValues = 'on';
        if strcmp(key, 'notch')
            c.width = numberField(globalPanel, seed.notch.width, [0 Inf], '%.4g', 'notchWidth');
        else
            c.width = [];
            uilabel(globalPanel, 'Text', '');
        end
        ctl.(key) = c;
        ctl.(key).cb.ValueChangedFcn = @(~, ~) onFilterToggled(key);
        ctl.(key).freq.ValueChangedFcn = @(~, ~) onEdited(key, 'freq');
        ctl.(key).auto.ValueChangedFcn = @(~, ~) onEdited(key, 'auto');
        ctl.(key).trans.ValueChangedFcn = @(~, ~) onEdited(key, 'transition');
        ctl.(key).db.ValueChangedFcn = @(~, ~) onEdited(key, 'db');
        ctl.(key).ripple.ValueChangedFcn = @(~, ~) onEdited(key, 'ripple');
        ctl.(key).order.ValueChangedFcn = @(~, ~) onEdited(key, 'order');
        if ~isempty(c.width)
            ctl.(key).width.ValueChangedFcn = @(~, ~) onEdited(key, 'width');
        end
        showDesign(key, seed.(key));
    end

    % The fourth filter: one made in MATLAB's Filter Designer.
    designedBox = uicheckbox(globalPanel, 'Text', 'Designed', 'Value', logical(designed.enabled), ...
        'Tag', 'designedEnabled', 'Tooltip', 'A filter made in MATLAB''s Filter Designer, applied after the three above.');
    designedSummary = uilabel(globalPanel, 'Text', '', 'WordWrap', 'on', 'Tag', 'designedSummary');
    designedSummary.Layout.Column = [2 6];
    uibutton(globalPanel, 'Text', 'Open designer', 'Tag', 'openFilterDesigner', ...
        'Tooltip', 'Start MATLAB''s Filter Designer app.', 'ButtonPushedFcn', @(~, ~) onOpenDesigner());
    uibutton(globalPanel, 'Text', 'Use exported...', 'Tag', 'useDesignedFilter', ...
        'Tooltip', 'Take a filter the Filter Designer exported to the workspace or a MAT-file.', ...
        'ButtonPushedFcn', @(~, ~) onUseExported());
    designedBox.ValueChangedFcn = @(~, ~) onDesignedToggled();
    showDesignedSummary();

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

    function onFilterToggled(key)
        setRowEnabled(ctl.(key));
        updateResponse();
    end

    function onEdited(key, what)
    %ONEDITED  Recompute KEY's design after WHAT was edited, keeping what the
    %   user set and changing what follows from it (see the header: DESIGN).
        c = ctl.(key);
        spec = struct('freq', c.freq.Value, 'db', c.db.Value, 'auto', logical(c.auto.Value), ...
            'transition', c.trans.Value, 'order', c.order.Value);
        if ~isempty(c.width)
            spec.width = c.width.Value;
        end
        switch what
            case 'ripple'
                deviation = 10 ^ (c.ripple.Value / 20) - 1;
                if ~(deviation > 0 && deviation < 1)
                    frequencyCaption.Text = 'The ripple has to be above 0 dB and below 6 dB.';
                    return;
                end
                spec.db = -20 * log10(deviation);
                spec.order = [];                       % the order follows the new deviation
            case {'db', 'transition'}
                spec.order = [];                       % the order follows
            case 'order'
                spec.transition = [];                  % the transition band follows
        end
        try
            design = filterDesign(rowDefs(strcmp({rowDefs.key}, key)).type, spec, srate);
        catch err
            frequencyCaption.Text = err.message;
            return;
        end
        showDesign(key, design);
        updateResponse();
    end

    function showDesign(key, spec)
    %SHOWDESIGN  Put SPEC's design (filterDesign's, or a stored setting from
    %   which it is worked out) into KEY's fields.
        c = ctl.(key);
        if ~isfield(spec, 'order') || ~isfield(spec, 'ripple')
            try
                spec = filterDesign(rowDefs(strcmp({rowDefs.key}, key)).type, spec, srate);
            catch
                setRowEnabled(c);
                return;                                % shown as it is; the plot says why
            end
        end
        c.db.Value = spec.db;
        c.ripple.Value = spec.ripple;
        c.trans.Value = spec.transition;
        c.order.Value = spec.order;
        if ~isempty(c.width) && ~isempty(spec.width)
            c.width.Value = spec.width;
        end
        setRowEnabled(c);
    end

    function onDesignedToggled()
        if designedBox.Value && ~isfield(designed, 'kind')
            designedBox.Value = false;
            uialert(fig, ['There is no designed filter yet. Open the Filter Designer, design and ' ...
                'export a filter, then press Use exported.'], 'No designed filter');
            return;
        end
        designed.enabled = logical(designedBox.Value);
        updateResponse();
    end

    function onOpenDesigner()
        try
            filterDesigner;
        catch err
            uialert(fig, sprintf('The Filter Designer could not be started: %s', err.message), ...
                'Filter Designer');
            return;
        end
        uialert(fig, sprintf(['Design the filter for a sample rate of %g Hz, the data''s. Then ' ...
            'export it as a Digital Filter Object to the workspace (or save it in a MAT-file), and ' ...
            'press Use exported.'], srate), 'Filter Designer', 'Icon', 'info');
    end

    function onUseExported()
        picked = pickDesignedFilter(srate);
        figure(fig);
        if isempty(picked)
            return;
        end
        designed = picked;
        designedBox.Value = true;
        showDesignedSummary();
        updateResponse();
    end

    function showDesignedSummary()
        if ~isfield(designed, 'kind')
            designedSummary.Text = 'None yet: open the designer, export a filter, and use it.';
            return;
        end
        how = 'applied once, zero-phase, as the filters above';
        if designedFilterPasses(designed) == 2
            how = 'applied forward and backward, zero-phase, so its attenuation doubles in dB';
        end
        designedSummary.Text = sprintf('%s: %s %s, order %d, %g Hz; %s.', designed.source, ...
            upper(designed.kind), designed.response, designed.order, designed.srate, how);
    end

    function updateResponse()
    %UPDATERESPONSE  Redraw the frequency response of the ticked filters, or
    %   say in its caption why it cannot be drawn: none ticked, or a setting
    %   Filter would refuse (the message is Filter's own).
        cla(frequencyAxes);
        settings = currentGlobalSeed();
        if ~any(cellfun(@(key) settings.(key).enabled, {'highpass', 'lowpass', 'notch', 'designed'}))
            frequencyCaption.Text = 'No filter is ticked, so the data are left as they are.';
            return;
        end
        try
            [frequencies, gain] = filterFrequencyResponse(settings, srate);
        catch err
            frequencyCaption.Text = err.message;
            return;
        end

        floorDb = gainFloorDb(settings);
        if settings.designed.enabled
            % A designed filter's depth is not one of the dB settings: the
            % axis reaches 20 dB below the deepest point of the curve itself,
            % to at most -200 dB.
            floorDb = min(floorDb, max(-200, -10 * ceil((20 - 20 * log10(max(min(gain), 1e-10))) / 10)));
        end
        plotFrequencyResponse(frequencyAxes, frequencies, gain, floorDb, accentColor);
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
            c = ctl.(key);
            s.(key) = struct('enabled', logical(c.cb.Value), 'freq', c.freq.Value, 'db', c.db.Value, ...
                'auto', logical(c.auto.Value), 'transition', c.trans.Value, 'order', c.order.Value);
            if ~isempty(c.width)
                s.(key).width = c.width.Value;
            end
        end
        s.designed = designed;
        s.designed.enabled = logical(designedBox.Value) && isfield(designed, 'kind');
    end

    function onOK()
        per = logical(perChanBox.Value);
        out = struct('perChannel', per);

        % Always carry the global settings through (so the panel round-trips).
        live = currentGlobalSeed();
        for k = 1:numel(rowDefs)
            key = rowDefs(k).key;
            row = live.(key);
            if ~per && row.enabled
                if ~validOne(rowDefs(k).label, key, row.freq, row.db); return; end
                try
                    filterDesign(rowDefs(k).type, row, srate);
                catch err
                    uialert(fig, err.message, 'Check the filters'); return;
                end
            end
            out.(key) = row;
        end
        out.designed = live.designed;

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

function setRowEnabled(c)
%SETROWENABLED  A filter's fields follow its tickbox; its transition band
%   and order are editable only with Automatic unticked.
    on = logical(c.cb.Value);
    manual = on && ~logical(c.auto.Value);
    state = {'off', 'on'};
    fields = {c.freq, c.auto, c.db, c.ripple, c.width};
    for k = 1:numel(fields)
        if ~isempty(fields{k})
            fields{k}.Enable = state{1 + on};
        end
    end
    c.trans.Enable = state{1 + manual};
    c.order.Enable = state{1 + manual};
end

function field = numberField(parent, value, limits, format, tag)
%NUMBERFIELD  A numeric field: above LIMITS(1) when that is 0 (a frequency, a
%   width, dB), at least LIMITS(1) otherwise (an order of at least 2).
    inclusive = {'off', 'on'};
    field = uieditfield(parent, 'numeric', 'Value', value, 'Limits', limits, ...
        'LowerLimitInclusive', inclusive{1 + (limits(1) > 0)}, 'ValueDisplayFormat', format, 'Tag', tag);
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
            % The rest of the design, where a stored setting has it; one from
            % before it existed stays automatic.
            if isfield(s, 'auto') && ~isempty(s.auto); seed.(k).auto = logical(s.auto); end
            for name = {'transition', 'order', 'width'}
                if isfield(s, name{1}) && isnumeric(s.(name{1})) && isscalar(s.(name{1})) && s.(name{1}) > 0
                    seed.(k).(name{1}) = s.(name{1});
                end
            end
        end
    end
end
