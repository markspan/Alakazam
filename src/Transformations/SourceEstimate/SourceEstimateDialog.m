function opts = SourceEstimateDialog(EEG, previous)
%SOURCEESTIMATEDIALOG  Settings for the SourceEstimate transformation.
%
%   OPTS = SourceEstimateDialog(EEG, PREVIOUS) returns the chosen settings,
%   or [] if cancelled. PREVIOUS is the remembered settings struct.
%
%   THE SAME SETTINGS AS THE SOURCE CLUSTER TEST, and deliberately worded
%   the same way, because a stored estimate is reused by that test only when
%   every one of them matches. An analyst who sets a 200 ms window here and
%   a 300 ms window there gets no reuse and no error, so the dialog says
%   what the choices are for rather than leaving them to be discovered.
%
%   The size estimate is shown because this transformation writes a node
%   that can be tens of megabytes, unlike most, and the cost is decided
%   entirely by the two settings above it.
%
%   See also SOURCEESTIMATE, TRANSTOOLS.SOURCEESTIMATEKEY.
    opts = [];
    if nargin < 2 || isempty(previous)
        previous = struct();
    end

    epoch = epochRange(EEG);
    nBins = binCount(EEG);

    [accentColor, bgColor] = dialogChromeColors();
    fig = uifigure('Name', 'Source Estimate', 'Position', [100 100 560 460], 'Color', bgColor);
    root = uigridlayout(fig, [2 1], 'RowHeight', {40, '1x'}, 'Padding', [0 0 0 0], 'RowSpacing', 0);
    uilabel(root, 'Text', '  Source Estimate', 'FontSize', 14, 'FontWeight', 'bold', ...
        'FontColor', [1 1 1], 'BackgroundColor', accentColor, 'VerticalAlignment', 'center');
    outer = uigridlayout(root, [4 1], 'RowHeight', {'fit', 'fit', '1x', 44}, ...
        'Padding', [10 10 10 10]);

    uilabel(outer, 'Text', ['Inverts every bin of this dataset onto a template cortical ' ...
        'sheet and stores the result, so that a source cluster test reads it instead of ' ...
        'computing it again. The test reuses what is stored here only if all of these ' ...
        'settings match what it needs, so keep them the same across subjects.'], ...
        'WordWrap', 'on');

    grid = uigridlayout(outer, [6 2], 'ColumnWidth', {170, '1x'}, ...
        'Padding', [8 8 8 0], 'RowSpacing', 4);

    uilabel(grid, 'Text', 'Inverse method', ...
        'Tooltip', 'dSPM and sLORETA are both depth-corrected. eLORETA is not, and is not offered.');
    methodDrop = uidropdown(grid, 'Items', {'dSPM (recommended)', 'sLORETA'}, ...
        'ItemsData', {'mne', 'sloreta'}, 'Value', TransTools.FieldOr(previous, 'Method', 'mne'));

    uilabel(grid, 'Text', 'Orientation', ...
        'Tooltip', 'Signed keeps the polarity of the effect; magnitude is unsigned.');
    orientationDrop = uidropdown(grid, 'Items', {'Signed (cortical normal)', 'Magnitude'}, ...
        'ItemsData', {'normal', 'magnitude'}, 'Value', TransTools.FieldOr(previous, 'Orientation', 'normal'));

    uilabel(grid, 'Text', 'Source space', ...
        'Tooltip', ['A finer sheet does not buy resolution with a few dozen electrodes, ' ...
            'but it does cost, in both runtime and the size of the stored node.']);
    spaceDrop = uidropdown(grid, ...
        'Items', {'20484 vertices (full)', '8196 vertices', '5124 vertices (fastest)'}, ...
        'ItemsData', {20484, 8196, 5124}, 'Value', TransTools.FieldOr(previous, 'SourceSpace', 20484));

    uilabel(grid, 'Text', 'Time window (ms)', ...
        'Tooltip', ['Applied before the inverse, so an estimate over a wider window is ' ...
            'a different fit rather than one that can be cropped later.']);
    windowRow = uigridlayout(grid, [1 3], 'ColumnWidth', {'1x', 16, '1x'}, ...
        'Padding', [0 0 0 0], 'ColumnSpacing', 4);
    startField = uieditfield(windowRow, 'numeric', ...
        'Value', TransTools.FieldOr(previous, 'WindowStart', epoch(1)));
    uilabel(windowRow, 'Text', 'to', 'HorizontalAlignment', 'center');
    stopField = uieditfield(windowRow, 'numeric', ...
        'Value', TransTools.FieldOr(previous, 'WindowStop', epoch(2)));

    uilabel(grid, 'Text', 'Store at (Hz)', ...
        'Tooltip', 'The rate the estimate is stored at. This is also part of the match.');
    rateField = uieditfield(grid, 'numeric', 'Limits', [10 1000], ...
        'Value', TransTools.FieldOr(previous, 'ResampleHz', 200));

    uilabel(grid, 'Text', 'Regularisation', ...
        'Tooltip', 'Chooses which of the many solutions fitting the data is returned.');
    regField = uieditfield(grid, 'numeric', 'Limits', [1e-6 10], ...
        'Value', TransTools.FieldOr(previous, 'RegParam', 0.05));

    sizeLabel = uilabel(outer, 'Text', '', 'WordWrap', 'on', ...
        'FontColor', [0.4 0.4 0.4], 'FontSize', 11);

    buttons = uigridlayout(outer, [1 3], 'ColumnWidth', {'1x', 90, 100}, ...
        'Padding', [8 6 8 6]);
    cancelBtn = uibutton(buttons, 'Text', 'Cancel', 'ButtonPushedFcn', @(~,~) onCancel());
    cancelBtn.Layout.Column = 2;
    okBtn = uibutton(buttons, 'Text', 'Compute', 'BackgroundColor', accentColor, ...
        'FontColor', [1 1 1], 'ButtonPushedFcn', @(~,~) onOK());
    okBtn.Layout.Column = 3;
    fig.CloseRequestFcn = @(~,~) onCancel();

    sizeDrivers = {spaceDrop, startField, stopField, rateField};
    for i = 1:numel(sizeDrivers)
        sizeDrivers{i}.ValueChangedFcn = @(~,~) refreshSize();
    end
    refreshSize();
    uiwait(fig);

    function refreshSize()
        span = max(0, stopField.Value - startField.Value);
        samples = max(1, round(span / 1000 * rateField.Value) + 1);
        bytes = spaceDrop.Value * samples * nBins * 8;
        sizeLabel.Text = sprintf( ...
            ['This will store about %.0f MB on the new node (%d vertices x %d samples ' ...
             'x %d bins). Nodes are usually a few MB, so a coarser sheet or a narrower ' ...
             'window is worth considering if disk is tight.'], ...
            bytes / 1e6, spaceDrop.Value, samples, nBins);
    end

    function onOK()
        if stopField.Value <= startField.Value
            uialert(fig, 'The time window would need to end after it starts.', 'Time window');
            return;
        end
        opts = struct( ...
            'Method',      methodDrop.Value, ...
            'Orientation', orientationDrop.Value, ...
            'SourceSpace', spaceDrop.Value, ...
            'TimeWindow',  [startField.Value, stopField.Value], ...
            'ResampleHz',  rateField.Value, ...
            'RegParam',    regField.Value, ...
            'WindowStart', startField.Value, ...
            'WindowStop',  stopField.Value);
        uiresume(fig);
        delete(fig);
    end

    function onCancel()
        opts = [];
        uiresume(fig);
        delete(fig);
    end
end


function range = epochRange(EEG)
%EPOCHRANGE  This dataset's own latencies, so the window defaults to all of
%   them rather than to a number someone once typed.
    range = [0 500];
    if isfield(EEG, 'times') && ~isempty(EEG.times)
        t = double(EEG.times);
        range = [min(t), max(t)];
    end
end

function n = binCount(EEG)
    n = 1;
    if isfield(EEG, 'bindesc') && ~isempty(EEG.bindesc)
        n = numel(EEG.bindesc);
    end
end
