function spec = GrandAverageDialog(candidateFiles, candidateLabels, prefillSpec)
%GRANDAVERAGEDIALOG  Modal dialog: name, weighting, and which subjects to
%   combine into a grand average.
%
%   SPEC = GRANDAVERAGEDIALOG(CANDIDATEFILES, CANDIDATELABELS, PREFILLSPEC)
%   shows a small dialog listing CANDIDATEFILES (a cell array of paths to
%   Averaged subject datasets) with CANDIDATELABELS as their on-screen
%   names, lets the analyst pick which ones to include, name the result,
%   and choose weighted/unweighted combining.
%
%   PREFILLSPEC is [] when defining a brand new grand average (the name
%   field is editable, nothing pre-selected), or a struct with fields
%   .name, .sources (a cell array of files, a subset of CANDIDATEFILES),
%   and .weighted, when revisiting an existing one (its name is fixed --
%   editing it here does not rename its saved file -- and its current
%   sources/weighting are pre-selected).
%
%   Returns a struct with .name, .sources (the selected files, a cell
%   array), and .weighted, or [] if the analyst cancelled.

    spec = [];
    isNew = isempty(prefillSpec);

    fig = uifigure('Name', 'Grand Average', 'Position', [100 100 480 420]);
    outer = uigridlayout(fig, [4 1], 'RowHeight', {'fit', 'fit', '1x', 44});

    % Row 1: name.
    nameRow = uigridlayout(outer, [1 2], 'ColumnWidth', {90, '1x'}, 'Padding', [8 8 8 0]);
    nameRow.Layout.Row = 1;
    uilabel(nameRow, 'Text', 'Name:');
    if isNew
        defaultName = '';
    else
        defaultName = prefillSpec.name;
    end
    nameField = uieditfield(nameRow, 'text', 'Value', defaultName, 'Editable', isNew);

    % Row 2: weighting.
    weightRow = uigridlayout(outer, [1 2], 'ColumnWidth', {90, '1x'}, 'Padding', [8 8 8 0]);
    weightRow.Layout.Row = 2;
    uilabel(weightRow, 'Text', 'Weighting:');
    weightChoices = {'Unweighted (every subject counts equally)', ...
                     'Weighted by each subject''s trial count'};
    if ~isNew && prefillSpec.weighted
        defaultWeightChoice = weightChoices{2};
    else
        defaultWeightChoice = weightChoices{1};
    end
    weightField = uidropdown(weightRow, 'Items', weightChoices, 'Value', defaultWeightChoice);

    % Row 3: subject picker (a plain multi-select list box -- no need for
    % per-item tickboxes/callbacks here, just "which of these are in").
    listRow = uigridlayout(outer, [2 1], 'RowHeight', {'fit', '1x'}, 'Padding', [8 8 8 0]);
    listRow.Layout.Row = 3;
    uilabel(listRow, 'Text', 'Include these subjects:');
    if isNew
        preselected = {};
    else
        preselected = prefillSpec.sources;
    end
    subjectList = uilistbox(listRow, 'Items', candidateLabels, 'ItemsData', candidateFiles, ...
        'Multiselect', 'on', 'Value', preselected);

    % Row 4: OK / Cancel, right-aligned.
    buttons = uigridlayout(outer, [1 3], 'ColumnWidth', {'1x', 90, 90}, 'Padding', [8 6 8 6]);
    buttons.Layout.Row = 4;
    cancelBtn = uibutton(buttons, 'Text', 'Cancel', 'ButtonPushedFcn', @(~,~) onCancel());
    cancelBtn.Layout.Column = 2;
    okBtn = uibutton(buttons, 'Text', 'Compute', 'ButtonPushedFcn', @(~,~) onOK());
    okBtn.Layout.Column = 3;
    fig.CloseRequestFcn = @(~,~) onCancel();

    uiwait(fig);

    function onOK()
        name = strtrim(nameField.Value);
        if isempty(name)
            uialert(fig, 'Give this grand average a name.', 'Name needed');
            return;
        end
        if numel(subjectList.Value) < 2
            uialert(fig, 'Pick at least two subjects to combine.', 'Not enough subjects');
            return;
        end
        spec = struct('name', name, 'sources', {subjectList.Value}, ...
            'weighted', strcmp(weightField.Value, weightChoices{2}));
        uiresume(fig);
        delete(fig);
    end

    function onCancel()
        uiresume(fig);
        delete(fig);
    end
end
