function [windows, derivations] = MeasureDialog(chanlocs, priorWindows, priorDerivations)
%MEASUREDIALOG  Modal editor for Measure's window definitions: an
%   editable table (Add/Remove-row buttons), one row per measurement
%   window (name, start/stop ms, measure type, polarity, optional
%   reference channel, channel selection), plus a "let" field for derived
%   channels.
%
%   CHANLOCS is the target dataset's own EEG.chanlocs, used only to
%   validate typed channel/reference-channel labels immediately (a
%   friendly error naming the bad label(s), rather than waiting until
%   Measure actually runs -- the shared measureChannelSpecs parser
%   repeats this validation at replay time too, since a saved window
%   definition can end up applied to a dataset whose channels differ from
%   whatever was validated here). PRIORWINDOWS (a cell array in the same
%   shape this function returns, or {} on first use) pre-fills the table
%   -- passed in by Measure.m from TransformSettings (a fresh interactive
%   run) or by Alakazam.recalculateTransformNode (editing one specific
%   node's own stored windows), matching DefineBins' own promptForScript/
%   GrandAverageDialog's own PREFILLSPEC pattern. PRIORDERIVATIONS (a char
%   block, or '' on first use) pre-fills the derived-channels field.
%
%   Returns WINDOWS, a 1xN cell array of scalar structs (.label, .start,
%   .stop, .measure, .polarity, .width, .localPoints, .fraction, .areaMode,
%   .baseline, .refChannel, .channels -- see Measure.m's own header comment
%   for why a cell array, never a struct array), and DERIVATIONS, the
%   derived-channels "let" text (see measureDerivations.m); or [] and '' if
%   the dialog was cancelled -- the same "empty means cancel" contract
%   GrandAverageDialog/TransformOptionsDialog use. Derived-channel names are
%   valid channel references in the table, so they are validated together at
%   OK time (a name may be measured only if its own let statement parses).
    if nargin < 3
        priorDerivations = '';
    end

    MEASURE_CHOICES   = {'Mean Amplitude', 'Peak', 'Area', ...
        'Fractional Peak Latency', 'Fractional Area Latency'};
    POLARITY_CHOICES  = {'Positive', 'Negative'};
    AREA_MODE_CHOICES = {'Signed', 'Rectified', 'Positive', 'Negative'};
    COLUMN_NAMES     = {'Label', 'Start (ms)', 'Stop (ms)', 'Measure', 'Polarity', ...
        'Width (ms)', 'Local pts', 'Fraction', 'Area mode', 'Baseline (ms)', ...
        'Reference channel', 'Channels'};
    % Proportional ('Nx') widths, not fixed pixels, so the columns share
    % and fill the table's width and grow/shrink with the window (the
    % table itself already fills its '1x' grid row). Weights roughly keep
    % the earlier readable proportions (Label/Measure/Reference/Channels
    % wider than the numeric fields).
    COLUMN_WIDTHS    = {'3x', '2x', '2x', '4x', '2x', '2x', '2x', '2x', '2x', '2x', '3x', '4x'};

    windows = [];       % returned only on OK; stays [] on Cancel
    derivations = '';   % the "let" block; set on OK, stays '' on Cancel
    allLabels = string({chanlocs.labels});
    selectedRow = 0; % 1-based row last clicked in the table, 0 = none

    [accentColor, bgColor] = dialogChromeColors();
    fig = uifigure('Name', 'Measure', 'Position', [100 100 1160 550], 'Color', bgColor);
    root = uigridlayout(fig, [2 1], 'RowHeight', {40, '1x'}, 'Padding', [0 0 0 0], 'RowSpacing', 0);
    uilabel(root, 'Text', '  Measure', 'FontSize', 14, 'FontWeight', 'bold', ...
        'FontColor', [1 1 1], 'BackgroundColor', accentColor, 'VerticalAlignment', 'center');
    outer = uigridlayout(root, [5 1], 'RowHeight', {'fit', 66, '1x', 'fit', 44});

    uilabel(outer, 'Text', [ ...
        'Define one or more measurement windows over the Start-Stop range. Measures: ' ...
        'Mean Amplitude; Peak (amplitude + latency); Area (its "Area mode" -- Signed / ' ...
        'Rectified / Positive / Negative -- over the whole window when "Width" is 0, or over a ' ...
        '"Width" ms band centred on the peak when Width > 0); Fractional Peak / Area Latency ' ...
        '(the "Fraction", 0-1, e.g. 0.5 for the 50% latency). "Local pts" 0 = absolute peak, ' ...
        'N = the most extreme local peak. "Baseline (ms)" (e.g. "-100 0") is subtracted before ' ...
        'measuring; blank = none. "Channels" blank = every channel, a list = each separately, ' ...
        'braces pool into one virtual channel ("{Pz POz CPz}" = their mean). "Reference ' ...
        'channel" (Peak / peak-band Area) locks every channel to one found peak latency.'], ...
        'WordWrap', 'on');

    % Derived channels: a block of "let" statements (see measureDerivations).
    % Each defines a new channel by an elementwise formula over existing (or
    % earlier-derived) channels, usable by name in any Channels/Reference
    % cell -- e.g. "let LRP = C3 - C4" for the lateralised readiness
    % potential's motor difference. Appended to the dataset, so they also
    % show on the ERP plot and in grand averages.
    derivGrid = uigridlayout(outer, [1 2], 'ColumnWidth', {250, '1x'}, ...
        'Padding', [0 0 0 0], 'ColumnSpacing', 6);
    derivGrid.Layout.Row = 2;
    uilabel(derivGrid, 'Text', sprintf(['Derived channels (optional), one "let" per line,\n' ...
        'usable by name in Channels/Reference:\ne.g.  let LRP = C3 - C4']), ...
        'WordWrap', 'on', 'VerticalAlignment', 'top');
    derivArea = uitextarea(derivGrid, 'Value', linesFromText(priorDerivations));

    table = uitable(outer, 'ColumnName', COLUMN_NAMES, 'ColumnEditable', true(1, 12), ...
        'ColumnFormat', {'char', 'numeric', 'numeric', MEASURE_CHOICES, POLARITY_CHOICES, ...
            'numeric', 'numeric', 'numeric', AREA_MODE_CHOICES, 'char', 'char', 'char'}, ...
        'ColumnWidth', COLUMN_WIDTHS, 'Data', rowsFromWindows(priorWindows));
    table.Layout.Row = 3;
    table.CellSelectionCallback = @(~, event) onCellSelected(event);
    table.CellEditCallback = @(~, event) onCellEdit(event);
    applyGreying();

    rowButtons = uigridlayout(outer, [1, 3], 'ColumnWidth', {110, 130, '1x'}, 'Padding', [0 0 0 0]);
    rowButtons.Layout.Row = 4;
    uibutton(rowButtons, 'Text', 'Add Window', 'ButtonPushedFcn', @(~, ~) addRow());
    uibutton(rowButtons, 'Text', 'Remove Selected', 'ButtonPushedFcn', @(~, ~) removeSelectedRow());

    % Save/Load on the left, Cancel/OK right-aligned -- the same row
    % layout DefineBins' own dialog uses for its Save.../Load... +
    % Cancel/OK row.
    buttons = uigridlayout(outer, [1 5], 'ColumnWidth', {90, 90, '1x', 90, 90}, 'Padding', [8 6 8 6]);
    buttons.Layout.Row = 5;
    saveBtn = uibutton(buttons, 'Text', 'Save...', 'ButtonPushedFcn', @(~, ~) onSaveMeasures());
    saveBtn.Layout.Column = 1;
    loadBtn = uibutton(buttons, 'Text', 'Load...', 'ButtonPushedFcn', @(~, ~) onLoadMeasures());
    loadBtn.Layout.Column = 2;
    cancelBtn = uibutton(buttons, 'Text', 'Cancel', 'ButtonPushedFcn', @(~, ~) onCancel());
    cancelBtn.Layout.Column = 4;
    okBtn = uibutton(buttons, 'Text', 'OK', 'BackgroundColor', accentColor, ...
        'FontColor', [1 1 1], 'ButtonPushedFcn', @(~, ~) onOK());
    okBtn.Layout.Column = 5;
    fig.CloseRequestFcn = @(~, ~) onCancel();

    uiwait(fig);

    function onCellSelected(event)
        if ~isempty(event.Indices)
            selectedRow = event.Indices(1, 1);
        end
    end

    function onCellEdit(event)
        % Changing a row's Measure changes which parameter cells apply, so
        % re-grey. (Cheap enough to just re-grey on any edit, but only the
        % Measure column can change relevance.)
        if ~isempty(event.Indices) && event.Indices(2) == 4
            applyGreying();
        end
    end

    function applyGreying()
        % Grey the parameter cells each row's Measure does not use, so a
        % row visibly shows only the parameters that apply to it (the
        % values stay, and are simply ignored by Measure.m -- see its own
        % header). Recomputed from scratch each call (removeStyle clears
        % all, then one addStyle over every irrelevant cell), so it stays
        % correct after adds/removes/loads that renumber rows.
        removeStyle(table);
        data = table.Data;
        greyCells = zeros(0, 2);
        for r = 1:size(data, 1)
            for cix = irrelevantParamCols(char(string(data{r, 4})))
                greyCells(end + 1, :) = [r, cix]; %#ok<AGROW>
            end
        end
        if ~isempty(greyCells)
            addStyle(table, uistyle('BackgroundColor', [0.94 0.94 0.94], 'FontColor', [0.6 0.6 0.6]), ...
                'cell', greyCells);
        end
    end

    function addRow()
        newRow = {'New Window', 0, 500, MEASURE_CHOICES{1}, POLARITY_CHOICES{1}, ...
            0, 0, 0.5, AREA_MODE_CHOICES{1}, '', '', ''};
        table.Data = [table.Data; newRow];
        applyGreying();
    end

    function removeSelectedRow()
        if selectedRow < 1 || selectedRow > size(table.Data, 1)
            uialert(fig, 'Would you click a row first, then Remove Selected?', 'No row selected');
            return;
        end
        table.Data(selectedRow, :) = [];
        selectedRow = 0;
        applyGreying();
    end

    function onOK()
        data = table.Data;
        if isempty(data)
            uialert(fig, 'This needs at least one measurement window before it can continue.', 'No windows defined');
            return;
        end
        % Validate the derived-channel block first (by running it on a tiny
        % dummy dataset built from this dataset's channels, so it parses
        % exactly as it will at measure time), and fold the derived names
        % into the label set the window rows are validated against, so a
        % window may name a channel that a "let" statement defines.
        derivText = textFromLines(derivArea.Value);
        try
            [~, derivedNames] = measureDerivations(dummyEEG(), derivText);
        catch err
            uialert(fig, err.message, 'Check the derived channels');
            return;
        end
        augLabels = allLabels;
        if ~isempty(derivedNames)
            augLabels = [allLabels, string(derivedNames)];
        end
        [built, errMsg] = windowsFromRows(data, augLabels);
        if ~isempty(errMsg)
            uialert(fig, errMsg, 'Check the window definitions');
            return;
        end
        windows = built;
        derivations = derivText;
        uiresume(fig);
        delete(fig);
    end

    function eeg = dummyEEG()
        % A minimal averaged dataset (this dataset's channels, two dummy
        % samples) so measureDerivations can parse/evaluate the let block at
        % OK time without needing the real data.
        eeg = struct('chanlocs', chanlocs, 'data', zeros(numel(chanlocs), 2), ...
            'nbchan', numel(chanlocs));
    end

    function onCancel()
        uiresume(fig);
        delete(fig);
    end

    function onSaveMeasures()
        % Saves the table's current rows exactly as they stand, valid or
        % not -- Save is a convenience for resuming the same setup later,
        % not a "this must already pass OK's validation" gate, matching
        % DefineBins' own Save (which saves whatever script text is
        % currently typed, unparsed). uiextras.uiputfile2 (not the plain
        % uiputfile Alakazam.onSaveTemplate/onExportGrandAverages use):
        % this is a standalone transform dialog with no Alakazam/Workspace
        % object to read a default export directory from (transforms only
        % ever receive an EEG struct, never the app), so it follows
        % DefineBins' own dialog -- the one other transform-level dialog
        % with a Save/Load pair -- which resolves this the same way.
        [file, path] = uiextras.uiputfile2('*.alm', 'Save measurement windows as');
        if isequal(file, 0); return; end
        try
            writeMeasuresFile(fullfile(path, file), table.Data, textFromLines(derivArea.Value));
        catch err
            uialert(fig, err.message, 'Save failed');
        end
    end

    function onLoadMeasures()
        [file, path] = uiextras.uigetfile2('*.alm', 'Load measurement windows');
        if isequal(file, 0); return; end
        try
            [loadedData, loadedDerivations] = readMeasuresFile(fullfile(path, file));
            table.Data = loadedData;
            derivArea.Value = linesFromText(loadedDerivations);
            selectedRow = 0;
            applyGreying();
        catch err
            uialert(fig, err.message, 'Load failed');
        end
    end
end

function cols = irrelevantParamCols(measure)
%IRRELEVANTPARAMCOLS  Which of the "sometimes" parameter columns
%   ([5..11] = Polarity, Width, Local pts, Fraction, Area mode, Baseline,
%   Reference) a MEASURE does NOT use, so applyGreying can grey them.
%   Label/Start/Stop/Measure/Channels (1-4,12) are always relevant, and so
%   is Baseline (10, every measure honours it). Keep in step with
%   Measure.m's computeWindow. Area's Width/Polarity/Local pts/Reference
%   matter only for its peak-band scope, but greying is per-measure (it
%   cannot see the Width value), so they stay shown for Area.
    switch lower(strtrim(measure))
        case 'mean amplitude';          relevant = 10;              % baseline
        case 'peak';                    relevant = [5 7 10 11];     % polarity, local pts, baseline, reference
        case {'area', 'peak area', 'integral'}
                                        relevant = [5 6 7 9 10 11]; % + width, area mode
        case 'fractional peak latency'; relevant = [5 7 8 10];      % polarity, local pts, fraction, baseline
        case 'fractional area latency'; relevant = [8 10];          % fraction, baseline
        otherwise;                      relevant = 5:11;            % unknown -> grey nothing
    end
    cols = setdiff(5:11, relevant);
end

% ======================================================================= %
%  Table <-> windows conversion
% ======================================================================= %
function data = rowsFromWindows(priorWindows)
%ROWSFROMWINDOWS  PRIORWINDOWS (a cell array of window structs, or {}) as
%   a uitable-compatible cell array of rows, one row per window. Fields
%   absent from a window stored before they existed default so the columns
%   are never empty, and the pre-unification Peak Area / Integral measures
%   are migrated to Area (see migrateMeasureWidth) so the Measure dropdown
%   never shows a value it no longer offers.
%
%   PRIORWINDOWS is normalised to a cell array here too, not just by
%   Measure.m's own callers: a struct array (Apply Template's jsonencode/
%   jsondecode round trip turns a cell array of same-shaped structs back
%   into one -- see Measure.m's own header comment) would otherwise break
%   the priorWindows{i} indexing below with "Brace indexing is not
%   supported for variables of type struct" before the dialog even
%   finishes building, regardless of which caller let it through
%   un-normalised.
    if isstruct(priorWindows)
        priorWindows = num2cell(priorWindows);
    end
    data = cell(numel(priorWindows), 12);
    for i = 1:numel(priorWindows)
        w = priorWindows{i};
        [measure, width] = migrateMeasureWidth(char(string(w.measure)), numField(w, 'width', 0));
        data(i, :) = {w.label, w.start, w.stop, measure, w.polarity, width, ...
            numField(w, 'localPoints', 0), numField(w, 'fraction', 0.5), ...
            normAreaMode(w), baselineText(w), w.refChannel, channelsText(w.channels)};
    end
end

function [measure, width] = migrateMeasureWidth(measure, width)
%MIGRATEMEASUREWIDTH  Fold the pre-unification measure names into Area:
%   Integral -> Area over the whole window (Width 0); Peak Area -> Area
%   over its peak band (Width kept). Any other name passes through. Keeps
%   old .alm files and stored settings loadable into the unified dropdown.
    if strcmpi(measure, 'Integral')
        measure = 'Area';
        width = 0;
    elseif strcmpi(measure, 'Peak Area')
        measure = 'Area';
    end
end

function s = normAreaMode(w)
%NORMAREAMODE  A window/row's area mode as one of the dropdown's exact
%   choices (default 'Signed'), so the uitable cell always holds a valid
%   value.
    s = 'Signed';
    if isfield(w, 'areaMode') && ~isempty(w.areaMode)
        switch lower(strtrim(char(string(w.areaMode))))
            case 'signed';    s = 'Signed';
            case 'rectified'; s = 'Rectified';
            case 'positive';  s = 'Positive';
            case 'negative';  s = 'Negative';
        end
    end
end

function txt = baselineText(w)
%BASELINETEXT  A window/row's baseline as display text ("" if none).
    if isfield(w, 'baseline') && ~isempty(w.baseline)
        txt = char(string(w.baseline));
    else
        txt = '';
    end
end

function txt = channelsText(channels)
%CHANNELSTEXT  A window's Channels field as display text for the table
%   cell: the raw text new windows store, or a comma-joined list for the
%   old cellstr form a window may carry from before pooling existed.
    if isempty(channels)
        txt = '';
    elseif iscell(channels)
        txt = strjoin(channels, ', ');
    elseif isstring(channels)
        txt = char(strjoin(channels, ', '));
    else
        txt = char(channels);
    end
end

function v = numField(w, name, default)
%NUMFIELD  W.(NAME) if present, non-empty and numeric, else DEFAULT.
    if isfield(w, name) && ~isempty(w.(name)) && isnumeric(w.(name))
        v = w.(name);
    else
        v = default;
    end
end

function [windows, errMsg] = windowsFromRows(data, allLabels)
%WINDOWSFROMROWS  DATA (a uitable's own row-per-window cell array) parsed
%   and validated into the 1xN cell-array-of-structs shape Measure.m
%   expects. ERRMSG is '' if every row is valid, otherwise a single
%   friendly message naming the first problem found (the analyst fixes
%   one thing at a time and re-clicks OK, matching TransformOptionsDialog/
%   GrandAverageDialog's own one-uialert-at-a-time validation style).
    errMsg = '';
    nRows = size(data, 1);
    windows = cell(1, nRows);

    for r = 1:nRows
        label = strtrim(char(string(data{r, 1})));
        if isempty(label)
            errMsg = sprintf('Row %d is missing a label -- would you give it one before continuing?', r);
            return;
        end

        startMs = data{r, 2};
        stopMs  = data{r, 3};
        if ~isnumeric(startMs) || ~isnumeric(stopMs) || isnan(startMs) || isnan(stopMs)
            errMsg = sprintf('I''m afraid window "%s" needs numeric Start/Stop times.', label);
            return;
        end
        if startMs > stopMs
            errMsg = sprintf('Window "%s": Start (%.4g ms) would need to come before Stop (%.4g ms), not after it.', ...
                label, startMs, stopMs);
            return;
        end

        measure = char(string(data{r, 4}));

        % Width (ms): for Area it is the scope switch (0/blank = whole
        % window, > 0 = a peak-locked band that wide) and needs no
        % validation; for the other measures it is unused. Blank defaults
        % to 0 so the column stays numeric.
        width = data{r, 6};
        if ~isnumeric(width) || isnan(width)
            width = 0;
        end

        % Local pts: a non-negative whole number (0 = absolute peak). Only
        % the peak-locating measures use it, and irrelevant cells are
        % greyed; an empty/blank cell defaults to 0 rather than erroring,
        % so a greyed value never blocks OK. A clearly-bad value (negative
        % or fractional) is still caught.
        localPoints = data{r, 7};
        if isnumeric(localPoints) && ~isnan(localPoints)
            if localPoints < 0 || mod(localPoints, 1) ~= 0
                errMsg = sprintf('I''m afraid window "%s": "Local pts" needs to be a whole number >= 0 (0 = absolute peak).', label);
                return;
            end
        else
            localPoints = 0;
        end

        % Fraction: required in (0,1) for the two fractional-latency
        % measures; carried through unvalidated otherwise.
        fraction = data{r, 8};
        isFractional = any(strcmpi(measure, {'Fractional Peak Latency', 'Fractional Area Latency'}));
        if isFractional && (~isnumeric(fraction) || isnan(fraction) || fraction <= 0 || fraction >= 1)
            errMsg = sprintf('Window "%s" is a %s measure, so it would need a Fraction strictly between 0 and 1 (e.g. 0.5).', ...
                label, measure);
            return;
        end
        if ~isnumeric(fraction) || isnan(fraction)
            fraction = 0.5; % keep the stored field numeric even for non-fractional rows
        end

        areaMode = char(string(data{r, 9}));   % dropdown, always a valid choice

        % Baseline (ms): blank, or exactly two numbers (e.g. "-100 0")
        % subtracted before measuring. Applies to any measure, so it is
        % validated for every row.
        baseline = strtrim(char(string(data{r, 10})));
        if ~isempty(baseline)
            nums = str2double(strtrim(strsplit(baseline, {',', ' '})));
            if sum(~isnan(nums)) ~= 2
                errMsg = sprintf('Window "%s": Baseline would need to be two numbers (e.g. "-100 0") or left blank.', label);
                return;
            end
        end

        % Channels: the raw text is stored as-is on the window (so pools
        % survive round-trips as text -- see measureChannelSpecs, the
        % shared parser); validate it here by parsing, surfacing the
        % parser's own friendly error (unknown channel, unbalanced brace)
        % which already names the window.
        chText = strtrim(char(string(data{r, 12})));
        try
            measureChannelSpecs(chText, allLabels, label);
        catch ME
            errMsg = ME.message;
            return;
        end

        refChannel = strtrim(char(string(data{r, 11})));
        if ~isempty(refChannel) && ~any(strcmpi(allLabels, refChannel))
            errMsg = sprintf('I''m afraid window "%s" names a reference channel ("%s") that is not in this dataset.', ...
                label, refChannel);
            return;
        end

        windows{r} = struct('label', label, 'start', double(startMs), 'stop', double(stopMs), ...
            'measure', measure, 'polarity', char(string(data{r, 5})), 'width', double(width), ...
            'localPoints', double(localPoints), 'fraction', double(fraction), ...
            'areaMode', areaMode, 'baseline', baseline, 'refChannel', refChannel, 'channels', chText);
    end
end

% ======================================================================= %
%  Save.../Load... file I/O
% ======================================================================= %
function writeMeasuresFile(filePath, data, derivations)
%WRITEMEASURESFILE  Save DATA (the table's own row-per-window cell array,
%   as-is -- see onSaveMeasures for why unvalidated) plus the DERIVATIONS
%   "let" block as a small JSON file. ROWS is deliberately a 1xN CELL array
%   of scalar structs, never a struct array: jsonencode collapses a
%   1-element struct array embedded in another struct's field to a bare JSON
%   object instead of a single-element array -- the same gotcha Measure.m's
%   own header comment documents for .windows, and worked around in
%   Alakazam.onSaveTemplate -- which would otherwise silently break loading
%   a one-window file back. A single fwrite, not fprintf: the JSON text is
%   already fully formatted, so there is no format-string/argument split to
%   make.
    rows = cell(1, size(data, 1));
    for i = 1:size(data, 1)
        rows{i} = struct('label', char(string(data{i, 1})), 'start', data{i, 2}, ...
            'stop', data{i, 3}, 'measure', char(string(data{i, 4})), ...
            'polarity', char(string(data{i, 5})), 'width', data{i, 6}, ...
            'localPoints', data{i, 7}, 'fraction', data{i, 8}, ...
            'areaMode', char(string(data{i, 9})), 'baseline', char(string(data{i, 10})), ...
            'refChannel', char(string(data{i, 11})), 'channels', char(string(data{i, 12})));
    end
    file = struct('alakazamMeasures', true, 'version', 1, ...
        'derivations', char(string(derivations)), 'rows', {rows});
    % ConvertInfAndNaN=false: see Alakazam.onSaveTemplate's own note --
    % the default (true) silently turns NaN into JSON null, which
    % jsondecode then reads back as [] (empty), not NaN.
    json = jsonencode(file, 'PrettyPrint', true, 'ConvertInfAndNaN', false);

    fid = fopen(filePath, 'w');
    if fid < 0
        throw(MException('Alakazam:MeasureDialog', ...
            ['I''m afraid this could not be saved to %s -- the folder might be read-only, ' ...
             'the disk might be full, or another program might have the file open. Would ' ...
             'you try a different location or filename?'], filePath));
    end
    cleanupFid = onCleanup(@() fclose(fid));
    fwrite(fid, json, 'char');
end

function [data, derivations] = readMeasuresFile(filePath)
%READMEASURESFILE  Inverse of writeMeasuresFile: a uitable-compatible
%   cell array of rows, plus the file's derived-channels "let" block ('' if
%   the file predates it). Throws a friendly error if FILEPATH is not a
%   recognisable saved-measures file.
    raw = jsondecode(fileread(filePath));
    if ~isstruct(raw) || ~isfield(raw, 'alakazamMeasures') ...
            || ~isequal(raw.alakazamMeasures, true) || ~isfield(raw, 'rows')
        throw(MException('Alakazam:MeasureDialog', ...
            'I''m afraid this does not look like a saved Measure window file.'));
    end
    derivations = '';
    if isfield(raw, 'derivations') && ~isempty(raw.derivations)
        derivations = char(string(raw.derivations));
    end
    n = numel(raw.rows);
    data = cell(n, 12);
    for i = 1:n
        r = raw.rows(i);
        % Tolerate a file saved before columns were added (default each),
        % and migrate the pre-unification Peak Area / Integral measures to
        % Area so they load into the current dropdown.
        [measure, width] = migrateMeasureWidth(char(string(r.measure)), rowNum(r, 'width', 0));
        data(i, :) = {r.label, r.start, r.stop, measure, r.polarity, width, ...
            rowNum(r, 'localPoints', 0), rowNum(r, 'fraction', 0.5), ...
            normAreaMode(r), baselineText(r), r.refChannel, r.channels};
    end
end

% linesFromText/textFromLines (src/Support/) used to be duplicated locally here.

function v = rowNum(r, name, default)
%ROWNUM  R.(NAME) if present, non-empty and numeric, else DEFAULT -- used
%   when loading a .alm file that predates a numeric column.
    if isfield(r, name) && ~isempty(r.(name)) && isnumeric(r.(name))
        v = r.(name);
    else
        v = default;
    end
end
