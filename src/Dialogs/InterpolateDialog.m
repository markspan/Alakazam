function options = InterpolateDialog(chanlocs, stored)
%INTERPOLATEDIALOG  Native editor for the Interpolate transform: pick the bad
%   channels to reconstruct from their neighbours, and the method, in the app's
%   own dialog style (the same choice pop_interp offers).
%
%   CHANLOCS is the dataset's channels; STORED a previous run's options (or []).
%   Returns the options struct (.channels {labels}, .method), or [] on cancel.
    labels = arrayfun(@(c) char(string(c.labels)), chanlocs, 'UniformOutput', false);
    METHODS = {'Spherical spline', 'Inverse distance', 'Spacetime'};
    METHODCODES = {'spherical', 'invdist', 'spacetime'};
    [accentColor, bgColor] = dialogChromeColors();
    options = [];

    seed = struct('channels', {{}}, 'method', 'spherical');
    seed = mergeSeedFields(seed, stored);
    seedMethodDisplay = METHODS{max(1, find(strcmp(METHODCODES, seed.method), 1))};

    fig = uifigure('Name', 'Interpolate', 'Position', [100 100 460 430], 'Color', bgColor);
    root = uigridlayout(fig, [2 1], 'RowHeight', {40, '1x'}, 'Padding', [0 0 0 0], 'RowSpacing', 0);
    uilabel(root, 'Text', '  Interpolate bad channels', 'FontSize', 14, 'FontWeight', 'bold', ...
        'FontColor', [1 1 1], 'BackgroundColor', accentColor, 'VerticalAlignment', 'center');
    outer = uigridlayout(root, [3 1], 'RowHeight', {'fit', '1x', 44}, 'Padding', [10 10 10 10]);

    topGrid = uigridlayout(outer, [2 2], 'RowHeight', {'fit', 'fit'}, ...
        'ColumnWidth', {90, 180}, 'Padding', [0 0 0 0], 'RowSpacing', 4);
    topGrid.Layout.Row = 1;
    intro = uilabel(topGrid, 'Text', ['Rebuild bad channels from the surrounding good ones ' ...
        '(they need scalp positions). Pick the channels to interpolate.'], 'WordWrap', 'on');
    intro.Layout.Row = 1; intro.Layout.Column = [1 2];
    uilabel(topGrid, 'Text', 'Method', 'FontWeight', 'bold');
    methodDrop = uidropdown(topGrid, 'Items', METHODS, 'Value', seedMethodDisplay);

    chanGrid = uigridlayout(outer, [2 1], 'RowHeight', {'fit', '1x'}, 'Padding', [0 0 0 0], 'RowSpacing', 2);
    chanGrid.Layout.Row = 2;
    uilabel(chanGrid, 'Text', 'Channels to interpolate:');
    chanList = uilistbox(chanGrid, 'Items', labels, 'Multiselect', 'on', ...
        'Value', intersectLabels(labels, seed.channels));

    buttons = uigridlayout(outer, [1 3], 'ColumnWidth', {'1x', 90, 90}, 'Padding', [0 4 0 0]);
    buttons.Layout.Row = 3;
    uilabel(buttons, 'Text', '');
    uibutton(buttons, 'Text', 'Cancel', 'ButtonPushedFcn', @(~, ~) onCancel());
    uibutton(buttons, 'Text', 'OK', 'BackgroundColor', accentColor, 'FontColor', [1 1 1], ...
        'ButtonPushedFcn', @(~, ~) onOK());
    fig.CloseRequestFcn = @(~, ~) onCancel();

    uiwait(fig);

    function onOK()
        chans = asCell(chanList.Value);
        if isempty(chans)
            uialert(fig, 'Select at least one channel to interpolate.', 'Nothing selected'); return;
        end
        code = METHODCODES{strcmp(METHODS, methodDrop.Value)};
        options = struct('channels', {chans}, 'method', code);
        uiresume(fig); delete(fig);
    end

    function onCancel()
        uiresume(fig); delete(fig);
    end
end

% intersectLabels/asCell (src/Support/) and mergeSeedFields (src/Support/)
% used to be duplicated locally here; see those files.
