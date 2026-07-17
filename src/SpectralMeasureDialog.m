function [rows, fundamentals, refChannel, method, nTapers, snrN, snrGuard] = ...
        SpectralMeasureDialog(chanlocs, stored)
%SPECTRALMEASUREDIALOG  Modal editor for SpectralMeasure's settings: a table
%   of named frequency rows (Label, Frequency expression, Channels), plus the
%   fundamentals block, an optional reference channel, the taper method, and
%   the SNR neighbour/guard band.
%
%   CHANLOCS is the dataset's EEG.chanlocs (for validating channel and
%   reference labels at OK time, via measureChannelSpecs / spectralFreqSpecs,
%   the same shared parsers SpectralMeasure uses to compute). STORED is the
%   options struct a previous run produced (or [] on first use), used to
%   pre-fill every control.
%
%   Returns ROWS (a 1xN cell of scalar structs .label/.freq/.channels),
%   FUNDAMENTALS (the "let f1 = 63" block), REFCHANNEL, METHOD ('Hann' or
%   'Multitaper'), NTAPERS, SNRN (neighbour bins each side) and SNRGUARD
%   (guard bins); or [] / '' on Cancel, the same "empty means cancel"
%   contract MeasureDialog/GrandAverageDialog use.
    METHOD_CHOICES = {'Hann', 'Multitaper'};
    COLUMN_NAMES   = {'Label', 'Frequency', 'Channels'};
    COLUMN_WIDTHS  = {'2x', '3x', '4x'};

    rows = []; fundamentals = ''; refChannel = ''; method = 'Hann';
    nTapers = 3; snrN = 10; snrGuard = 1;               % returned only on OK
    allLabels = string({chanlocs.labels});
    selectedRow = 0;

    % Seed from STORED (or sensible first-run defaults).
    seedRows = {{'f1', 'f1', ''}};
    seedFund = 'let f1 = 60';
    seedRef = ''; seedMethod = 'Hann'; seedTapers = 3; seedN = 10; seedGuard = 1;
    if isstruct(stored) && isfield(stored, 'rows') && ~isempty(stored.rows)
        seedRows = cellfun(@(r) {char(string(r.label)), char(string(r.freq)), ...
            char(string(r.channels))}, stored.rows, 'UniformOutput', false);
        seedFund   = getField(stored, 'fundamentals', seedFund);
        seedRef    = getField(stored, 'refChannel', '');
        seedMethod = getField(stored, 'method', 'Hann');
        seedTapers = getField(stored, 'tapers', 3);
        seedN      = getField(stored, 'snrNeighbours', 10);
        seedGuard  = getField(stored, 'snrGuard', 1);
    end
    tableData = vertcat(seedRows{:});

    fig = uifigure('Name', 'SpectralMeasure', 'Position', [100 100 900 520]);
    outer = uigridlayout(fig, [5 1], 'RowHeight', {'fit', 'fit', '1x', 'fit', 44});

    uilabel(outer, 'Text', [ ...
        'Quantify tagged responses at named frequencies. Declare fundamentals below ' ...
        '(e.g. "let f1 = 63"), then write each row''s Frequency as an expression over them ' ...
        '(f1, 2*f1 for a harmonic, f1+f2 / 2*f1-f2 for intermodulation). "Channels" blank = ' ...
        'every channel, a list = each separately, braces "{Pz POz}" = their mean. A ' ...
        'Reference channel (e.g. a photodiode) adds coherence + phase-lag; leave it blank for ' ...
        'power / SNR / phase-locking only.'], 'WordWrap', 'on');

    % Settings strip: fundamentals on the left, scalar controls on the right.
    settings = uigridlayout(outer, [1 2], 'ColumnWidth', {'1x', 340}, ...
        'Padding', [0 0 0 0], 'ColumnSpacing', 12);
    settings.Layout.Row = 2;

    fundGrid = uigridlayout(settings, [2 1], 'RowHeight', {'fit', 66}, 'Padding', [0 0 0 0], 'RowSpacing', 2);
    uilabel(fundGrid, 'Text', 'Fundamentals (one "let name = value" per line):');
    fundArea = uitextarea(fundGrid, 'Value', linesFromText(seedFund));

    ctrl = uigridlayout(settings, [5 2], 'ColumnWidth', {150, '1x'}, ...
        'RowHeight', repmat({'fit'}, 1, 5), 'Padding', [0 0 0 0], 'RowSpacing', 4);
    uilabel(ctrl, 'Text', 'Reference channel:');
    refField = uieditfield(ctrl, 'text', 'Value', char(string(seedRef)), 'Placeholder', 'optional, e.g. PD');
    uilabel(ctrl, 'Text', 'Taper method:');
    methodDrop = uidropdown(ctrl, 'Items', METHOD_CHOICES, 'Value', pickChoice(seedMethod, METHOD_CHOICES));
    uilabel(ctrl, 'Text', 'Multitaper tapers (K):');
    tapersField = uieditfield(ctrl, 'numeric', 'Value', seedTapers, 'Limits', [1 16], 'RoundFractionalValues', 'on');
    uilabel(ctrl, 'Text', 'SNR neighbour bins:');
    neighField = uieditfield(ctrl, 'numeric', 'Value', seedN, 'Limits', [1 100], 'RoundFractionalValues', 'on');
    uilabel(ctrl, 'Text', 'SNR guard bins:');
    guardField = uieditfield(ctrl, 'numeric', 'Value', seedGuard, 'Limits', [0 20], 'RoundFractionalValues', 'on');

    table = uitable(outer, 'ColumnName', COLUMN_NAMES, 'ColumnEditable', true(1, 3), ...
        'ColumnFormat', {'char', 'char', 'char'}, 'ColumnWidth', COLUMN_WIDTHS, 'Data', tableData);
    table.Layout.Row = 3;
    table.CellSelectionCallback = @(~, event) onCellSelected(event);

    rowButtons = uigridlayout(outer, [1 3], 'ColumnWidth', {110, 130, '1x'}, 'Padding', [0 0 0 0]);
    rowButtons.Layout.Row = 4;
    uibutton(rowButtons, 'Text', 'Add Frequency', 'ButtonPushedFcn', @(~, ~) addRow());
    uibutton(rowButtons, 'Text', 'Remove Selected', 'ButtonPushedFcn', @(~, ~) removeSelectedRow());

    buttons = uigridlayout(outer, [1 5], 'ColumnWidth', {90, 90, '1x', 90, 90}, 'Padding', [8 6 8 6]);
    buttons.Layout.Row = 5;
    b1 = uibutton(buttons, 'Text', 'Save...', 'ButtonPushedFcn', @(~, ~) onSave());  b1.Layout.Column = 1;
    b2 = uibutton(buttons, 'Text', 'Load...', 'ButtonPushedFcn', @(~, ~) onLoad());  b2.Layout.Column = 2;
    b3 = uibutton(buttons, 'Text', 'Cancel', 'ButtonPushedFcn', @(~, ~) onCancel()); b3.Layout.Column = 4;
    b4 = uibutton(buttons, 'Text', 'OK', 'ButtonPushedFcn', @(~, ~) onOK());         b4.Layout.Column = 5;
    fig.CloseRequestFcn = @(~, ~) onCancel();

    uiwait(fig);

    function onCellSelected(event)
        if ~isempty(event.Indices); selectedRow = event.Indices(1, 1); end
    end

    function addRow()
        table.Data = [table.Data; {'new', 'f1', ''}];
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
            uialert(fig, 'Add at least one frequency.', 'No frequencies defined');
            return;
        end
        for r = 1:size(data, 1)
            if isempty(strtrim(char(string(data{r, 1}))))
                uialert(fig, sprintf('Row %d needs a label.', r), 'Check the frequencies'); return;
            end
            if isempty(strtrim(char(string(data{r, 2}))))
                uialert(fig, sprintf('Row "%s" needs a frequency expression.', ...
                    char(string(data{r, 1}))), 'Check the frequencies'); return;
            end
        end
        fundText = textFromLines(fundArea.Value);
        try
            spectralFreqSpecs(data(:, 2), fundText);   % validates fundamentals + every expression
        catch ME
            uialert(fig, ME.message, 'Check the frequencies'); return;
        end
        for r = 1:size(data, 1)
            try
                measureChannelSpecs(strtrim(char(string(data{r, 3}))), allLabels, char(string(data{r, 1})));
            catch ME
                uialert(fig, ME.message, 'Check the channels'); return;
            end
        end
        ref = strtrim(char(string(refField.Value)));
        if ~isempty(ref) && ~any(strcmpi(allLabels, ref))
            uialert(fig, sprintf('Reference channel "%s" is not in this dataset.', ref), ...
                'Check the reference channel'); return;
        end

        rows = rowsFromData(data);
        fundamentals = fundText;
        refChannel = ref;
        method = methodDrop.Value;
        nTapers = tapersField.Value;
        snrN = neighField.Value;
        snrGuard = guardField.Value;
        uiresume(fig); delete(fig);
    end

    function onCancel()
        uiresume(fig); delete(fig);
    end

    function onSave()
        [file, path] = uiextras.uiputfile2('*.almf', 'Save spectral settings as');
        if isequal(file, 0); return; end
        try
            writeFile(fullfile(path, file));
        catch err
            uialert(fig, err.message, 'Save failed');
        end
    end

    function onLoad()
        [file, path] = uiextras.uigetfile2('*.almf', 'Load spectral settings');
        if isequal(file, 0); return; end
        try
            readFile(fullfile(path, file));
            selectedRow = 0;
        catch err
            uialert(fig, err.message, 'Load failed');
        end
    end

    function writeFile(filePath)
        data = table.Data;
        rowStructs = cell(1, size(data, 1));
        for i = 1:size(data, 1)
            rowStructs{i} = struct('label', char(string(data{i, 1})), ...
                'freq', char(string(data{i, 2})), 'channels', char(string(data{i, 3})));
        end
        file = struct('alakazamSpectral', true, 'version', 1, ...
            'fundamentals', textFromLines(fundArea.Value), ...
            'refChannel', strtrim(char(string(refField.Value))), ...
            'method', methodDrop.Value, 'tapers', tapersField.Value, ...
            'snrNeighbours', neighField.Value, 'snrGuard', guardField.Value, ...
            'rows', {rowStructs});
        json = jsonencode(file, 'PrettyPrint', true, 'ConvertInfAndNaN', false);
        fid = fopen(filePath, 'w');
        if fid < 0
            throw(MException('Alakazam:SpectralMeasureDialog', ...
                'Could not save to %s (folder read-only, disk full, or file open elsewhere).', filePath));
        end
        c = onCleanup(@() fclose(fid));
        fwrite(fid, json, 'char');
    end

    function readFile(filePath)
        raw = jsondecode(fileread(filePath));
        if ~isstruct(raw) || ~isfield(raw, 'alakazamSpectral') ...
                || ~isequal(raw.alakazamSpectral, true) || ~isfield(raw, 'rows')
            throw(MException('Alakazam:SpectralMeasureDialog', ...
                'This does not look like a saved SpectralMeasure settings file.'));
        end
        n = numel(raw.rows);
        d = cell(n, 3);
        for i = 1:n
            r = raw.rows(i);
            d(i, :) = {char(string(r.label)), char(string(r.freq)), char(string(r.channels))};
        end
        table.Data = d;
        fundArea.Value = linesFromText(getField(raw, 'fundamentals', ''));
        refField.Value = char(string(getField(raw, 'refChannel', '')));
        methodDrop.Value = pickChoice(getField(raw, 'method', 'Hann'), METHOD_CHOICES);
        tapersField.Value = getField(raw, 'tapers', 3);
        neighField.Value = getField(raw, 'snrNeighbours', 10);
        guardField.Value = getField(raw, 'snrGuard', 1);
    end
end

function rows = rowsFromData(data)
    rows = cell(1, size(data, 1));
    for i = 1:size(data, 1)
        rows{i} = struct('label', strtrim(char(string(data{i, 1}))), ...
            'freq', strtrim(char(string(data{i, 2}))), ...
            'channels', strtrim(char(string(data{i, 3}))));
    end
end

function v = getField(s, name, default)
    if isstruct(s) && isfield(s, name) && ~isempty(s.(name)); v = s.(name); else; v = default; end
end

function val = pickChoice(want, choices)
    hit = find(strcmpi(choices, char(string(want))), 1);
    if isempty(hit); val = choices{1}; else; val = choices{hit}; end
end

function lines = linesFromText(text)
    if isempty(char(string(text))); lines = {''}; else; lines = cellstr(splitlines(string(text))); end
end

function text = textFromLines(value)
    text = char(strjoin(string(value), newline));
end
