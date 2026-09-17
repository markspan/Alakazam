function [rows, fundamentals, refChannel, method, nTapers, snrN, snrGuard, crossf] = ...
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
%   'Multitaper'), NTAPERS, SNRN (neighbour bins each side), SNRGUARD
%   (guard bins) and CROSSF (a struct: .enabled plus, when enabled,
%   .WinSize/.PadRatio/.TimesOut/.MinFreq/.MaxFreq/.TimeStart/.TimeStop --
%   see SpectralMeasure's own header comment for what each means); or
%   [] / '' on Cancel, the same "empty means cancel" contract
%   MeasureDialog/GrandAverageDialog use.
    METHOD_CHOICES = {'Hann', 'Multitaper'};
    COLUMN_NAMES   = {'Label', 'Frequency', 'Channels'};
    COLUMN_WIDTHS  = {'2x', '3x', '4x'};

    rows = []; fundamentals = ''; refChannel = ''; method = 'Hann';
    nTapers = 3; snrN = 10; snrGuard = 1;               % returned only on OK
    crossf = struct('enabled', false);
    allLabels = string({chanlocs.labels});
    selectedRow = 0;

    % Seed from STORED (or sensible first-run defaults).
    seedRows = {{'f1', 'f1', ''}};
    seedFund = 'let f1 = 60';
    seedRef = ''; seedMethod = 'Hann'; seedTapers = 3; seedN = 10; seedGuard = 1;
    seedCrossf = struct('enabled', false, 'WinSize', 510, 'PadRatio', 4, 'TimesOut', 500, ...
        'MinFreq', [], 'MaxFreq', [], 'TimeStart', [], 'TimeStop', []);
    if isstruct(stored) && isfield(stored, 'rows') && ~isempty(stored.rows)
        storedRows = stored.rows;
        if isstruct(storedRows)
            % A node created (or recalculated) before this normalisation
            % existed can still have a struct-array .rows baked into its
            % own saved .params -- recalculateTransformNode seeds
            % TransformSettings straight from that node's own file, so
            % this reaches here un-normalised on the very first
            % Recalculate. cellfun below requires a cell array; normalise
            % here so reopening an old node's dialog self-heals it
            % instead of crashing (same gotcha as Measure.m's own
            % options.windows -- see its header comment).
            storedRows = num2cell(storedRows);
        end
        seedRows = cellfun(@(r) {char(string(r.label)), char(string(r.freq)), ...
            char(string(r.channels))}, storedRows, 'UniformOutput', false);
        seedFund   = getField(stored, 'fundamentals', seedFund);
        seedRef    = getField(stored, 'refChannel', '');
        seedMethod = getField(stored, 'method', 'Hann');
        seedTapers = getField(stored, 'tapers', 3);
        seedN      = getField(stored, 'snrNeighbours', 10);
        seedGuard  = getField(stored, 'snrGuard', 1);
        storedCrossf = getField(stored, 'crossf', struct());
        seedCrossf.enabled   = logical(getField(storedCrossf, 'enabled', false));
        seedCrossf.WinSize   = getField(storedCrossf, 'WinSize', 510);
        seedCrossf.PadRatio  = getField(storedCrossf, 'PadRatio', 4);
        seedCrossf.TimesOut  = getField(storedCrossf, 'TimesOut', 500);
        seedCrossf.MinFreq   = getField(storedCrossf, 'MinFreq', []);
        seedCrossf.MaxFreq   = getField(storedCrossf, 'MaxFreq', []);
        seedCrossf.TimeStart = getField(storedCrossf, 'TimeStart', []);
        seedCrossf.TimeStop  = getField(storedCrossf, 'TimeStop', []);
    end
    tableData = vertcat(seedRows{:});

    [accentColor, bgColor] = dialogChromeColors();
    fig = uifigure('Name', 'SpectralMeasure', 'Position', fitOnScreen([100 100 900 640]), 'Color', bgColor);
    root = uigridlayout(fig, [2 1], 'RowHeight', {40, '1x'}, 'Padding', [0 0 0 0], 'RowSpacing', 0);
    uilabel(root, 'Text', '  Spectral measure', 'FontSize', 14, 'FontWeight', 'bold', ...
        'FontColor', [1 1 1], 'BackgroundColor', accentColor, 'VerticalAlignment', 'center');
    outer = uigridlayout(root, [6 1], 'RowHeight', {'fit', 'fit', 'fit', '1x', 'fit', 44});

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

    % Coherence via newcrossf: a checkbox plus its own compact strip of
    % newcrossf parameters, enabled/disabled together with it. Only
    % coherence/phase-lag are affected -- see SpectralMeasure's own header
    % comment for why this exists (the default single-window coherence is a
    % biased estimator) and needs EEGLAB (checked at compute time, not here,
    % so this dialog itself works without EEGLAB on the path).
    crossfPanel = uigridlayout(outer, [2 1], 'RowHeight', {'fit', 'fit'}, ...
        'Padding', [0 0 0 0], 'RowSpacing', 2);
    crossfPanel.Layout.Row = 3;
    crossfCheck = uicheckbox(crossfPanel, 'Text', [ ...
        'Compute coherence / phase-lag via EEGLAB''s newcrossf (sliding-window, trial- and ' ...
        'frame-averaged) instead of the single-window default; needs EEGLAB.'], ...
        'Value', seedCrossf.enabled);
    crossfFields = uigridlayout(crossfPanel, [2 7], 'ColumnWidth', repmat({'1x'}, 1, 7), ...
        'RowHeight', {'fit', 'fit'}, 'Padding', [24 0 0 0], 'ColumnSpacing', 6);
    crossfLabels = {'Window (samples)', 'Pad ratio', 'Time points', 'Min freq (Hz)', ...
        'Max freq (Hz)', 'Window start (ms)', 'Window stop (ms)'};
    for i = 1:numel(crossfLabels)
        uilabel(crossfFields, 'Text', crossfLabels{i}, 'FontSize', 10);
    end
    winSizeField   = uieditfield(crossfFields, 'numeric', 'Value', seedCrossf.WinSize, ...
        'Limits', [4 Inf], 'RoundFractionalValues', 'on');
    padRatioField  = uieditfield(crossfFields, 'numeric', 'Value', seedCrossf.PadRatio, ...
        'Limits', [1 Inf], 'RoundFractionalValues', 'on');
    timesOutField  = uieditfield(crossfFields, 'numeric', 'Value', seedCrossf.TimesOut, ...
        'Limits', [2 Inf], 'RoundFractionalValues', 'on');
    minFreqField   = uieditfield(crossfFields, 'numeric', 'Value', seedCrossf.MinFreq, ...
        'AllowEmpty', 'on', 'Placeholder', 'auto');
    maxFreqField   = uieditfield(crossfFields, 'numeric', 'Value', seedCrossf.MaxFreq, ...
        'AllowEmpty', 'on', 'Placeholder', 'auto');
    timeStartField = uieditfield(crossfFields, 'numeric', 'Value', seedCrossf.TimeStart, ...
        'AllowEmpty', 'on', 'Placeholder', 'whole epoch');
    timeStopField  = uieditfield(crossfFields, 'numeric', 'Value', seedCrossf.TimeStop, ...
        'AllowEmpty', 'on', 'Placeholder', 'whole epoch');
    crossfCheck.ValueChangedFcn = @(~, ~) setCrossfFieldsEnabled(crossfCheck.Value);
    setCrossfFieldsEnabled(seedCrossf.enabled);

    table = uitable(outer, 'ColumnName', COLUMN_NAMES, 'ColumnEditable', true(1, 3), ...
        'ColumnFormat', {'char', 'char', 'char'}, 'ColumnWidth', COLUMN_WIDTHS, 'Data', tableData);
    table.Layout.Row = 4;
    table.CellSelectionCallback = @(~, event) onCellSelected(event);

    rowButtons = uigridlayout(outer, [1 3], 'ColumnWidth', {110, 130, '1x'}, 'Padding', [0 0 0 0]);
    rowButtons.Layout.Row = 5;
    uibutton(rowButtons, 'Text', 'Add Frequency', 'ButtonPushedFcn', @(~, ~) addRow());
    uibutton(rowButtons, 'Text', 'Remove Selected', 'ButtonPushedFcn', @(~, ~) removeSelectedRow());

    buttons = uigridlayout(outer, [1 5], 'ColumnWidth', {90, 90, '1x', 90, 90}, 'Padding', [8 6 8 6]);
    buttons.Layout.Row = 6;
    b1 = uibutton(buttons, 'Text', 'Save...', 'ButtonPushedFcn', @(~, ~) onSave());  b1.Layout.Column = 1;
    b2 = uibutton(buttons, 'Text', 'Load...', 'ButtonPushedFcn', @(~, ~) onLoad());  b2.Layout.Column = 2;
    b3 = uibutton(buttons, 'Text', 'Cancel', 'ButtonPushedFcn', @(~, ~) onCancel()); b3.Layout.Column = 4;
    b4 = uibutton(buttons, 'Text', 'OK', 'BackgroundColor', accentColor, ...
        'FontColor', [1 1 1], 'ButtonPushedFcn', @(~, ~) onOK());                    b4.Layout.Column = 5;
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
            uialert(fig, 'Would you click a row first, then Remove Selected?', 'No row selected');
            return;
        end
        table.Data(selectedRow, :) = [];
        selectedRow = 0;
    end

    function onOK()
        data = table.Data;
        if isempty(data)
            uialert(fig, 'This needs at least one frequency before it can continue.', 'No frequencies defined');
            return;
        end
        for r = 1:size(data, 1)
            if isempty(strtrim(char(string(data{r, 1}))))
                uialert(fig, sprintf('Row %d is missing a label -- would you give it one?', r), 'Check the frequencies'); return;
            end
            if isempty(strtrim(char(string(data{r, 2}))))
                uialert(fig, sprintf('I''m afraid row "%s" needs a frequency expression.', ...
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
            uialert(fig, sprintf('I''m afraid reference channel "%s" is not in this dataset.', ref), ...
                'Check the reference channel'); return;
        end
        newCrossf = crossfFromFields();
        if newCrossf.enabled
            if ~isempty(newCrossf.MinFreq) && ~isempty(newCrossf.MaxFreq) && newCrossf.MinFreq >= newCrossf.MaxFreq
                uialert(fig, 'Min freq must be less than Max freq for the newcrossf coherence band.', ...
                    'Check the newcrossf settings'); return;
            end
            if ~isempty(newCrossf.TimeStart) && ~isempty(newCrossf.TimeStop) && newCrossf.TimeStart >= newCrossf.TimeStop
                uialert(fig, 'Window start must be before Window stop for the newcrossf averaging window.', ...
                    'Check the newcrossf settings'); return;
            end
        end

        rows = rowsFromData(data);
        fundamentals = fundText;
        refChannel = ref;
        method = methodDrop.Value;
        nTapers = tapersField.Value;
        snrN = neighField.Value;
        snrGuard = guardField.Value;
        crossf = newCrossf;
        uiresume(fig); delete(fig);
    end

    function onCancel()
        uiresume(fig); delete(fig);
    end

    function c = crossfFromFields()
    %CROSSFFROMFIELDS  The crossf struct from the dialog's own fields --
    %   MinFreq/MaxFreq/TimeStart/TimeStop stay [] ("auto"/"whole epoch")
    %   when their field was left empty, same "empty means unset" contract
    %   SpectralMeasure.m's own numOr expects.
        c = struct('enabled', logical(crossfCheck.Value), ...
            'WinSize', winSizeField.Value, 'PadRatio', padRatioField.Value, ...
            'TimesOut', timesOutField.Value, 'MinFreq', minFreqField.Value, ...
            'MaxFreq', maxFreqField.Value, 'TimeStart', timeStartField.Value, ...
            'TimeStop', timeStopField.Value);
    end

    function setCrossfFieldsEnabled(tf)
        state = matlab.lang.OnOffSwitchState(tf);
        winSizeField.Enable = state; padRatioField.Enable = state; timesOutField.Enable = state;
        minFreqField.Enable = state; maxFreqField.Enable = state;
        timeStartField.Enable = state; timeStopField.Enable = state;
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
            'crossf', crossfFromFields(), 'rows', {rowStructs});
        json = jsonencode(file, 'PrettyPrint', true, 'ConvertInfAndNaN', false);
        fid = fopen(filePath, 'w');
        if fid < 0
            throw(MException('Alakazam:SpectralMeasureDialog', ...
                'I''m afraid this could not be saved to %s (the folder may be read-only, the disk full, or the file open elsewhere).', filePath));
        end
        c = onCleanup(@() fclose(fid));
        fwrite(fid, json, 'char');
    end

    function readFile(filePath)
        raw = jsondecode(fileread(filePath));
        if ~isstruct(raw) || ~isfield(raw, 'alakazamSpectral') ...
                || ~isequal(raw.alakazamSpectral, true) || ~isfield(raw, 'rows')
            throw(MException('Alakazam:SpectralMeasureDialog', ...
                'I''m afraid this does not look like a saved SpectralMeasure settings file.'));
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
        loadedCrossf = getField(raw, 'crossf', struct());
        crossfCheck.Value  = logical(getField(loadedCrossf, 'enabled', false));
        winSizeField.Value   = getField(loadedCrossf, 'WinSize', 510);
        padRatioField.Value  = getField(loadedCrossf, 'PadRatio', 4);
        timesOutField.Value  = getField(loadedCrossf, 'TimesOut', 500);
        minFreqField.Value   = getField(loadedCrossf, 'MinFreq', []);
        maxFreqField.Value   = getField(loadedCrossf, 'MaxFreq', []);
        timeStartField.Value = getField(loadedCrossf, 'TimeStart', []);
        timeStopField.Value  = getField(loadedCrossf, 'TimeStop', []);
        setCrossfFieldsEnabled(crossfCheck.Value);
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

% linesFromText/textFromLines (src/Support/) used to be duplicated locally here.
