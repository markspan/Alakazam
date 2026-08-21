function options = ReRefDialog(chanlocs, stored)
%REREFDIALOG  Native editor for the ReRef transform: choose the reference the
%   data is re-referenced to, in the app's own dialog style (the same choices
%   pop_reref offers).
%
%   Reference is either the Average of the channels, or Specific channel(s)
%   (their mean). Channels can be excluded from the reference computation, and
%   the reference channel(s) optionally kept in the data. CHANLOCS is the
%   dataset's channels; STORED a previous run's options (or [] on first use).
%
%   Returns the options struct (.mode, .refChannels, .exclude, .keepref), or []
%   on cancel.
    labels = arrayfun(@(c) char(string(c.labels)), chanlocs, 'UniformOutput', false);
    MODES = {'Average', 'Specific channels'};
    [accentColor, bgColor] = dialogChromeColors();
    options = [];

    seed = struct('mode', 'Average', 'refChannels', {{}}, 'exclude', {{}}, 'keepref', false);
    seed = mergeSeedFields(seed, stored);

    fig = uifigure('Name', 'ReRef', 'Position', [100 100 460 410], 'Color', bgColor);
    root = uigridlayout(fig, [2 1], 'RowHeight', {40, '1x'}, 'Padding', [0 0 0 0], 'RowSpacing', 0);
    uilabel(root, 'Text', '  Re-reference', 'FontSize', 14, 'FontWeight', 'bold', ...
        'FontColor', [1 1 1], 'BackgroundColor', accentColor, 'VerticalAlignment', 'center');
    outer = uigridlayout(root, [5 1], 'RowHeight', {'fit', 'fit', '1x', 'fit', 44}, 'Padding', [10 10 10 10]);

    uilabel(outer, 'Text', ['Re-reference the data. Choose the Average of all channels, or the mean ' ...
        'of Specific channel(s). Optionally exclude channels from the reference, and keep the ' ...
        'reference channel(s) in the data.'], 'WordWrap', 'on');

    modeGrid = uigridlayout(outer, [1 2], 'ColumnWidth', {110, 160}, 'Padding', [0 0 0 0]);
    modeGrid.Layout.Row = 2;
    uilabel(modeGrid, 'Text', 'Reference', 'FontWeight', 'bold');
    modeDrop = uidropdown(modeGrid, 'Items', MODES, 'Value', seed.mode);
    modeDrop.ValueChangedFcn = @(~, ~) refreshMode();

    lists = uigridlayout(outer, [2 2], 'RowHeight', {'fit', '1x'}, 'ColumnWidth', {'1x', '1x'}, ...
        'Padding', [0 0 0 0], 'RowSpacing', 2, 'ColumnSpacing', 10);
    lists.Layout.Row = 3;
    uilabel(lists, 'Text', 'Reference channel(s)');
    uilabel(lists, 'Text', 'Exclude from reference');
    refList = uilistbox(lists, 'Items', labels, 'Multiselect', 'on', 'Value', intersectLabels(labels, seed.refChannels));
    exclList = uilistbox(lists, 'Items', labels, 'Multiselect', 'on', 'Value', intersectLabels(labels, seed.exclude));

    keepBox = uicheckbox(outer, 'Text', 'Keep the reference channel(s) in the data', 'Value', seed.keepref);
    keepBox.Layout.Row = 4;

    buttons = uigridlayout(outer, [1 3], 'ColumnWidth', {'1x', 90, 90}, 'Padding', [0 4 0 0]);
    buttons.Layout.Row = 5;
    uilabel(buttons, 'Text', '');
    uibutton(buttons, 'Text', 'Cancel', 'ButtonPushedFcn', @(~, ~) onCancel());
    uibutton(buttons, 'Text', 'OK', 'BackgroundColor', accentColor, ...
        'FontColor', [1 1 1], 'ButtonPushedFcn', @(~, ~) onOK());
    fig.CloseRequestFcn = @(~, ~) onCancel();

    refreshMode();
    uiwait(fig);

    function refreshMode()
        if strcmp(modeDrop.Value, 'Specific channels'); refList.Enable = 'on'; else; refList.Enable = 'off'; end
    end

    function onOK()
        out = struct('mode', modeDrop.Value, 'refChannels', {asCell(refList.Value)}, ...
            'exclude', {asCell(exclList.Value)}, 'keepref', logical(keepBox.Value));
        if strcmp(out.mode, 'Specific channels') && isempty(out.refChannels)
            uialert(fig, 'Select at least one reference channel, or choose Average.', 'Check the reference'); return;
        end
        options = out;
        uiresume(fig); delete(fig);
    end

    function onCancel()
        uiresume(fig); delete(fig);
    end
end

% intersectLabels/asCell (src/Support/) and mergeSeedFields (src/Support/)
% used to be duplicated locally here; see those files.
