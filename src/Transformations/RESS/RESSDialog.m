function options = RESSDialog(EEG, stored)
%RESSDIALOG  Modal editor for RESS's settings.
%   OPTIONS = RESSDialog(EEG, STORED) shows a table of components (Label,
%   Frequency in Hz, the bins that build it) and the filter settings, seeded
%   from STORED (a previous run's options, or [] on first use), and returns
%   the options RESS takes, or [] on Cancel.
%
%   A FIRST RUN PROPOSES ONE ROW PER FREQUENCY the bin labels name
%   (TransTools.FrequencyFromLabel), with the bins that share a frequency
%   pooled: "RIFT 60Hz" and "RIFT 60Hz peripheral" build one 60 Hz filter.
%   That is the pooling RESS recommends; see its header.
%
%   OK checks the settings with RESSPlan, the same function RESS
%   applies them with, and says what to change rather than closing on
%   something RESS would refuse.
%
%   See also RESS, RESSPLAN.
    options = [];
    COLUMN_NAMES = {'Label', 'Frequency (Hz)', 'Build from bins (blank = all)'};

    seed = defaults(EEG);
    if isstruct(stored) && isfield(stored, 'rows') && ~isempty(stored.rows)
        for name = fieldnames(seed)'
            if isfield(stored, name{1}) && ~(isnumeric(stored.(name{1})) && isscalar(stored.(name{1})) && isnan(stored.(name{1})))
                seed.(name{1}) = stored.(name{1});
            end
        end
    end
    rows = seed.rows;
    if isstruct(rows)
        rows = num2cell(rows);
    end
    tableData = cell(numel(rows), 3);
    for k = 1:numel(rows)
        bins = TransTools.FieldOr(rows{k}, 'bins', '');
        if iscell(bins)
            bins = strjoin(cellstr(string(bins)), ', ');
        end
        tableData(k, :) = {char(string(TransTools.FieldOr(rows{k}, 'label', ''))), ...
            double(TransTools.FieldOr(rows{k}, 'freq', NaN)), char(string(bins))};
    end
    selectedRow = 0;

    [accentColor, bgColor] = dialogChromeColors();
    fig = uifigure('Name', 'RESS', 'Position', fitOnScreen([120 120 760 560]), 'Color', bgColor);
    root = uigridlayout(fig, [2 1], 'RowHeight', {40, '1x'}, 'Padding', [0 0 0 0], 'RowSpacing', 0);
    uilabel(root, 'Text', '  Rhythmic entrainment source separation', 'FontSize', 14, 'FontWeight', 'bold', ...
        'FontColor', [1 1 1], 'BackgroundColor', accentColor, 'VerticalAlignment', 'center');
    outer = uigridlayout(root, [6 1], 'RowHeight', {'fit', '1x', 'fit', 'fit', 'fit', 44});

    uilabel(outer, 'WordWrap', 'on', 'Text', [ ...
        'One component per row: the combination of the scalp channels with the most power at the ' ...
        'frequency relative to the frequencies beside it (Cohen & Gulbinaite, 2017). It is added as a ' ...
        'channel named by the label, which Spectral Measure can then read like an electrode. Each filter ' ...
        'is built from the pooled trials of the bins in its row and applied to every trial, so the other ' ...
        'bins show what it gives without the flicker it was built for.']);

    table = uitable(outer, 'ColumnName', COLUMN_NAMES, 'ColumnEditable', true(1, 3), ...
        'ColumnFormat', {'char', 'numeric', 'char'}, 'ColumnWidth', {'1x', 110, '2x'}, 'Data', tableData);
    table.CellSelectionCallback = @(~, event) onCellSelected(event);

    rowButtons = uigridlayout(outer, [1 3], 'ColumnWidth', {110, 130, '1x'}, 'Padding', [0 0 0 0]);
    uibutton(rowButtons, 'Text', 'Add Row', 'ButtonPushedFcn', @(~, ~) addRow());
    uibutton(rowButtons, 'Text', 'Remove Selected', 'ButtonPushedFcn', @(~, ~) removeSelectedRow());

    settings = uigridlayout(outer, [4 4], 'ColumnWidth', {170, 90, 190, 90}, ...
        'RowHeight', repmat({'fit'}, 1, 4), 'Padding', [0 0 0 0], 'RowSpacing', 4);
    uilabel(settings, 'Text', 'Width at the frequency (Hz):');
    peakField = uieditfield(settings, 'numeric', 'Value', seed.peakFWHM, 'Limits', [0 Inf], 'LowerLimitInclusive', 'off');
    uilabel(settings, 'Text', 'Window start (ms):');
    startField = uieditfield(settings, 'numeric', 'Value', emptyIfNaN(seed.timeStart), 'AllowEmpty', 'on', 'Placeholder', 'whole epoch');
    uilabel(settings, 'Text', 'Neighbours, either side (Hz):');
    distField = uieditfield(settings, 'numeric', 'Value', seed.neighbourDistance, 'Limits', [0 Inf], 'LowerLimitInclusive', 'off');
    uilabel(settings, 'Text', 'Window stop (ms):');
    stopField = uieditfield(settings, 'numeric', 'Value', emptyIfNaN(seed.timeStop), 'AllowEmpty', 'on', 'Placeholder', 'whole epoch');
    uilabel(settings, 'Text', 'Width at the neighbours (Hz):');
    neighField = uieditfield(settings, 'numeric', 'Value', seed.neighbourFWHM, 'Limits', [0 Inf], 'LowerLimitInclusive', 'off');
    uilabel(settings, 'Text', 'Shrinkage of the reference (%):');
    shrinkField = uieditfield(settings, 'numeric', 'Value', 100 * seed.shrinkage, 'Limits', [0 99]);
    mastoidBox = uicheckbox(settings, 'Text', 'Include the mastoids', 'Value', logical(seed.includeMastoids));
    mastoidBox.Layout.Column = [1 2];
    channelNote = uilabel(settings, 'Text', '', 'WordWrap', 'on');
    channelNote.Layout.Column = [3 4];
    mastoidBox.ValueChangedFcn = @(~, ~) showChannels();
    showChannels();

    uilabel(outer, 'WordWrap', 'on', 'FontColor', [0.35 0.35 0.35], 'Text', [ ...
        'Defaults are the authors'' own code: 0.5 Hz at the frequency, neighbours 1 Hz away and 1 Hz wide. ' ...
        'Use the window to leave out the onset response, as the authors did. Shrinkage keeps the filter ' ...
        'defined when an average reference or a removed ICA component has lowered the data''s rank.']);

    buttons = uigridlayout(outer, [1 3], 'ColumnWidth', {'1x', 90, 90}, 'Padding', [8 6 8 6]);
    b1 = uibutton(buttons, 'Text', 'Cancel', 'ButtonPushedFcn', @(~, ~) onCancel()); b1.Layout.Column = 2;
    b2 = uibutton(buttons, 'Text', 'OK', 'BackgroundColor', accentColor, 'FontColor', [1 1 1], ...
        'ButtonPushedFcn', @(~, ~) onOK()); b2.Layout.Column = 3;
    fig.CloseRequestFcn = @(~, ~) onCancel();

    uiwait(fig);

    function showChannels()
        mask = RESSChannels(EEG.chanlocs, mastoidBox.Value);
        channelNote.Text = sprintf('Combines %d channels: %s', nnz(mask), strjoin({EEG.chanlocs(mask).labels}, ' '));
    end

    function onCellSelected(event)
        if ~isempty(event.Indices)
            selectedRow = event.Indices(1, 1);
        end
    end

    function addRow()
        table.Data = [table.Data; {'RESS', NaN, ''}];
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
        candidate = struct( ...
            'rows', {arrayfun(@(k) struct('label', strtrim(char(string(data{k, 1}))), ...
                'freq', double(data{k, 2}), 'bins', strtrim(char(string(data{k, 3})))), ...
                1:size(data, 1), 'UniformOutput', false)}, ...
            'includeMastoids', mastoidBox.Value, ...
            'timeStart', startField.Value, 'timeStop', stopField.Value, ...
            'peakFWHM', peakField.Value, 'neighbourDistance', distField.Value, ...
            'neighbourFWHM', neighField.Value, 'shrinkage', shrinkField.Value / 100);
        try
            RESSPlan(EEG, candidate);
        catch err
            uialert(fig, err.message, 'Check the RESS settings');
            return;
        end
        options = candidate;
        uiresume(fig);
        delete(fig);
    end

    function onCancel()
        uiresume(fig);
        delete(fig);
    end
end

function seed = defaults(EEG)
%DEFAULTS  First-run settings: the authors' filter parameters, the whole
%   epoch, no mastoids, and one row per frequency the bin labels name.
    seed = struct('rows', {{}}, 'includeMastoids', false, 'timeStart', [], 'timeStop', [], ...
        'peakFWHM', 0.5, 'neighbourDistance', 1, 'neighbourFWHM', 1, 'shrinkage', 0.01);
    if ~isfield(EEG, 'bindesc') || isempty(EEG.bindesc)
        return;
    end
    labels = cellstr(string({EEG.bindesc.label}));
    ordinary = true(1, numel(labels));
    if isfield(EEG.bindesc, 'combo')
        ordinary = cellfun(@isempty, {EEG.bindesc.combo});
    end
    hz = TransTools.FrequencyFromLabel(labels);
    hz(~ordinary) = NaN;
    freqs = unique(hz(isfinite(hz)), 'stable');
    for f = freqs
        seed.rows{end + 1} = struct('label', sprintf('RESS%gHz', f), 'freq', f, ...
            'bins', strjoin(labels(hz == f), ', '));
    end
end

function v = emptyIfNaN(v)
    if isnumeric(v) && isscalar(v) && isnan(v)
        v = [];
    end
end
