function windows = MeasureDialog(chanlocs, priorWindows)
%MEASUREDIALOG  Modal editor for Measure's window definitions: an
%   editable table (Add/Remove-row buttons), one row per measurement
%   window (name, start/stop ms, measure type, polarity, optional
%   reference channel, channel selection).
%
%   CHANLOCS is the target dataset's own EEG.chanlocs, used only to
%   validate typed channel/reference-channel labels immediately (a
%   friendly error naming the bad label(s), rather than waiting until
%   Measure actually runs -- Measure.m's own resolveChannelList repeats
%   this validation at replay time too, since a saved window definition
%   can end up applied to a dataset whose channels differ from whatever
%   was validated here). PRIORWINDOWS (a cell array in the same shape
%   this function returns, or {} on first use) pre-fills the table --
%   passed in by Measure.m from TransformSettings (a fresh interactive
%   run) or by Alakazam.recalculateTransformNode (editing one specific
%   node's own stored windows), matching DefineBins' own promptForScript/
%   GrandAverageDialog's own PREFILLSPEC pattern.
%
%   Returns a 1xN cell array of scalar structs (.label, .start, .stop,
%   .measure, .polarity, .refChannel, .channels -- see Measure.m's own
%   header comment for why a cell array, never a struct array, and why
%   .channels is always a cellstr), or [] if the dialog was cancelled --
%   the same "empty means cancel" contract GrandAverageDialog/
%   TransformOptionsDialog use.

    MEASURE_CHOICES  = {'Mean Amplitude', 'Peak'};
    POLARITY_CHOICES = {'Positive', 'Negative'};
    COLUMN_NAMES     = {'Label', 'Start (ms)', 'Stop (ms)', 'Measure', 'Polarity', ...
        'Reference channel', 'Channels'};
    COLUMN_WIDTHS    = {110, 80, 80, 120, 85, 130, 150};

    windows = [];  % returned only on OK; stays [] on Cancel
    allLabels = string({chanlocs.labels});
    selectedRow = 0; % 1-based row last clicked in the table, 0 = none

    fig = uifigure('Name', 'Measure', 'Position', [100 100 780 420]);
    outer = uigridlayout(fig, [4 1], 'RowHeight', {'fit', '1x', 'fit', 44});

    uilabel(outer, 'Text', [ ...
        'Define one or more measurement windows. "Channels" blank = every channel, ' ...
        'or a comma-separated list (e.g. Pz, Cz). "Peak" always exports both an ' ...
        'amplitude and a latency value; "Reference channel" locks every selected ' ...
        'channel''s readout to that one channel''s own found latency.'], ...
        'WordWrap', 'on');

    table = uitable(outer, 'ColumnName', COLUMN_NAMES, 'ColumnEditable', true(1, 7), ...
        'ColumnFormat', {'char', 'numeric', 'numeric', MEASURE_CHOICES, POLARITY_CHOICES, 'char', 'char'}, ...
        'ColumnWidth', COLUMN_WIDTHS, 'Data', rowsFromWindows(priorWindows));
    table.Layout.Row = 2;
    table.CellSelectionCallback = @(~, event) onCellSelected(event);

    rowButtons = uigridlayout(outer, [1, 3], 'ColumnWidth', {110, 130, '1x'}, 'Padding', [0 0 0 0]);
    rowButtons.Layout.Row = 3;
    uibutton(rowButtons, 'Text', 'Add Window', 'ButtonPushedFcn', @(~, ~) addRow());
    uibutton(rowButtons, 'Text', 'Remove Selected', 'ButtonPushedFcn', @(~, ~) removeSelectedRow());

    % Save/Load on the left, Cancel/OK right-aligned -- the same row
    % layout DefineBins' own dialog uses for its Save.../Load... +
    % Cancel/OK row.
    buttons = uigridlayout(outer, [1 5], 'ColumnWidth', {90, 90, '1x', 90, 90}, 'Padding', [8 6 8 6]);
    buttons.Layout.Row = 4;
    saveBtn = uibutton(buttons, 'Text', 'Save...', 'ButtonPushedFcn', @(~, ~) onSaveMeasures());
    saveBtn.Layout.Column = 1;
    loadBtn = uibutton(buttons, 'Text', 'Load...', 'ButtonPushedFcn', @(~, ~) onLoadMeasures());
    loadBtn.Layout.Column = 2;
    cancelBtn = uibutton(buttons, 'Text', 'Cancel', 'ButtonPushedFcn', @(~, ~) onCancel());
    cancelBtn.Layout.Column = 4;
    okBtn = uibutton(buttons, 'Text', 'OK', 'ButtonPushedFcn', @(~, ~) onOK());
    okBtn.Layout.Column = 5;
    fig.CloseRequestFcn = @(~, ~) onCancel();

    uiwait(fig);

    function onCellSelected(event)
        if ~isempty(event.Indices)
            selectedRow = event.Indices(1, 1);
        end
    end

    function addRow()
        newRow = {'New Window', 0, 500, MEASURE_CHOICES{1}, POLARITY_CHOICES{1}, '', ''};
        table.Data = [table.Data; newRow];
    end

    function removeSelectedRow()
        if selectedRow < 1 || selectedRow > size(table.Data, 1)
            uialert(fig, 'Click a row first, then Remove Selected.', 'No row selected');
            return;
        end
        table.Data(selectedRow, :) = [];
        selectedRow = 0;
    end

    function onOK()
        data = table.Data;
        if isempty(data)
            uialert(fig, 'Add at least one measurement window.', 'No windows defined');
            return;
        end
        [built, errMsg] = windowsFromRows(data, allLabels);
        if ~isempty(errMsg)
            uialert(fig, errMsg, 'Check the window definitions');
            return;
        end
        windows = built;
        uiresume(fig);
        delete(fig);
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
        [file, path] = uiextras.uiputfile2('*.alzmeasures', 'Save measurement windows as');
        if isequal(file, 0); return; end
        try
            writeMeasuresFile(fullfile(path, file), table.Data);
        catch err
            uialert(fig, err.message, 'Save failed');
        end
    end

    function onLoadMeasures()
        [file, path] = uiextras.uigetfile2('*.alzmeasures', 'Load measurement windows');
        if isequal(file, 0); return; end
        try
            table.Data = readMeasuresFile(fullfile(path, file));
            selectedRow = 0;
        catch err
            uialert(fig, err.message, 'Load failed');
        end
    end
end

% ======================================================================= %
%  Table <-> windows conversion
% ======================================================================= %
function data = rowsFromWindows(priorWindows)
%ROWSFROMWINDOWS  PRIORWINDOWS (a cell array of window structs, or {}) as
%   a uitable-compatible cell array of rows, one row per window.
    data = cell(numel(priorWindows), 7);
    for i = 1:numel(priorWindows)
        w = priorWindows{i};
        data(i, :) = {w.label, w.start, w.stop, w.measure, w.polarity, w.refChannel, ...
            strjoin(cellstr(w.channels), ', ')};
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
            errMsg = sprintf('Row %d needs a label.', r);
            return;
        end

        startMs = data{r, 2};
        stopMs  = data{r, 3};
        if ~isnumeric(startMs) || ~isnumeric(stopMs) || isnan(startMs) || isnan(stopMs)
            errMsg = sprintf('Window "%s" needs numeric Start/Stop times.', label);
            return;
        end
        if startMs > stopMs
            errMsg = sprintf('Window "%s": Start (%.4g ms) must not be after Stop (%.4g ms).', ...
                label, startMs, stopMs);
            return;
        end

        [channels, chanErr] = parseChannelSpec(data{r, 7}, allLabels);
        if ~isempty(chanErr)
            errMsg = sprintf('Window "%s": %s', label, chanErr);
            return;
        end

        refChannel = strtrim(char(string(data{r, 6})));
        if ~isempty(refChannel) && ~any(strcmpi(allLabels, refChannel))
            errMsg = sprintf('Window "%s" names a reference channel ("%s") not in this dataset.', ...
                label, refChannel);
            return;
        end

        windows{r} = struct('label', label, 'start', double(startMs), 'stop', double(stopMs), ...
            'measure', char(string(data{r, 4})), 'polarity', char(string(data{r, 5})), ...
            'refChannel', refChannel, 'channels', {channels});
    end
end

function [channels, errMsg] = parseChannelSpec(spec, allLabels)
%PARSECHANNELSPEC  A table cell's typed "Channels" text (comma/space-
%   separated labels, or blank for "every channel") parsed into a cellstr
%   in ALLLABELS' own canonical casing -- ALWAYS a cellstr, even for one
%   channel or none (see Measure.m's own header comment on why a bare
%   char is never used for a list-shaped field). ERRMSG names any
%   requested label not found in ALLLABELS, case-insensitively matched.
    text = strtrim(char(string(spec)));
    if isempty(text)
        channels = {};
        errMsg = '';
        return;
    end
    parts = strtrim(strsplit(text, {',', ' '}));
    parts = parts(~cellfun(@isempty, parts)); % collapse repeated separators/whitespace

    channels = cell(1, numel(parts));
    missing = {};
    for i = 1:numel(parts)
        match = find(strcmpi(allLabels, parts{i}), 1);
        if isempty(match)
            missing{end + 1} = parts{i}; %#ok<AGROW>
        else
            channels{i} = char(allLabels(match));
        end
    end
    if isempty(missing)
        errMsg = '';
    else
        errMsg = sprintf('names channel(s) not in this dataset: %s.', strjoin(missing, ', '));
    end
end

% ======================================================================= %
%  Save.../Load... file I/O
% ======================================================================= %
function writeMeasuresFile(filePath, data)
%WRITEMEASURESFILE  Save DATA (the table's own row-per-window cell array,
%   as-is -- see onSaveMeasures for why unvalidated) as a small JSON file.
%   ROWS is deliberately a 1xN CELL array of scalar structs, never a
%   struct array: jsonencode collapses a 1-element struct array embedded
%   in another struct's field to a bare JSON object instead of a single-
%   element array -- the same gotcha Measure.m's own header comment
%   documents for .windows, and worked around in Alakazam.onSaveTemplate
%   -- which would otherwise silently break loading a one-window file
%   back. A single fwrite, not fprintf: the JSON text is already fully
%   formatted, so there is no format-string/argument split to make.
    rows = cell(1, size(data, 1));
    for i = 1:size(data, 1)
        rows{i} = struct('label', char(string(data{i, 1})), 'start', data{i, 2}, ...
            'stop', data{i, 3}, 'measure', char(string(data{i, 4})), ...
            'polarity', char(string(data{i, 5})), 'refChannel', char(string(data{i, 6})), ...
            'channels', char(string(data{i, 7})));
    end
    file = struct('alakazamMeasures', true, 'version', 1, 'rows', {rows});
    % ConvertInfAndNaN=false: see Alakazam.onSaveTemplate's own note --
    % the default (true) silently turns NaN into JSON null, which
    % jsondecode then reads back as [] (empty), not NaN.
    json = jsonencode(file, 'PrettyPrint', true, 'ConvertInfAndNaN', false);

    fid = fopen(filePath, 'w');
    if fid < 0
        throw(MException('Alakazam:MeasureDialog', ...
            ['Could not save to %s -- the folder might be read-only, the disk might be ' ...
             'full, or another program might have the file open. Try a different ' ...
             'location or filename.'], filePath));
    end
    cleanupFid = onCleanup(@() fclose(fid));
    fwrite(fid, json, 'char');
end

function data = readMeasuresFile(filePath)
%READMEASURESFILE  Inverse of writeMeasuresFile: a uitable-compatible
%   cell array of rows. Throws a friendly error if FILEPATH is not a
%   recognisable saved-measures file.
    raw = jsondecode(fileread(filePath));
    if ~isstruct(raw) || ~isfield(raw, 'alakazamMeasures') ...
            || ~isequal(raw.alakazamMeasures, true) || ~isfield(raw, 'rows')
        throw(MException('Alakazam:MeasureDialog', ...
            'This does not look like a saved Measure window file.'));
    end
    n = numel(raw.rows);
    data = cell(n, 7);
    for i = 1:n
        r = raw.rows(i);
        data(i, :) = {r.label, r.start, r.stop, r.measure, r.polarity, r.refChannel, r.channels};
    end
end
