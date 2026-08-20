function editGroups(this, ~, ~)
%EDITGROUPS  "Edit Groups" dialog: one row per subject (every root node in
%   Tree -- Data & Analyses' own per-subject branches, the same identity
%   collectEntriesWithField resolves as .subject via Tree.rootOf), each
%   with a free-text group label field. Blank means "no group assigned" --
%   groupFor returns '' for it, and generateQuartoReport's between-
%   subjects/mixed branch only activates once at least two DISTINCT
%   non-blank labels exist, so leaving everything blank is exactly
%   today's within-subject-only behaviour, unchanged.
%
%   uifigure-based, same header/button style as WorkSpace.edit -- but a
%   scrollable middle panel, not a fixed grid, since the subject count is
%   open-ended (a handful in a pilot dataset, dozens in a full study).
%
%   OK copies every row into this.Groups (this WorkSpace instance only --
%   like TransformSettings and the three directories, it does not touch
%   disk until the analyst explicitly does "Save WorkSpace"). Cancel (or
%   closing the window) discards changes.
    accentColor = [0.290 0.498 0.788]; % matches AlakazamRibbon.html's .alz-tab-home (#4a7fc9)
    bgColor     = [0.9608 0.9608 0.9608]; % uifigure's own default Color

    subjects = {};
    nodes = this.Tree.allNodes();
    for i = 1:numel(nodes)
        if nodes(i).IsRoot
            subjects{end + 1} = nodes(i).Name; %#ok<AGROW>
        end
    end
    subjects = sort(subjects);

    parentFig = [];
    if isprop(this.Parent, 'MainFigure') && isvalid(this.Parent.MainFigure)
        parentFig = this.Parent.MainFigure;
    end
    position = [400 300 480 440];
    if ~isempty(parentFig)
        parentPos = parentFig.Position;
        position(1) = parentPos(1) + (parentPos(3) - position(3)) / 2;
        position(2) = parentPos(2) + (parentPos(4) - position(4)) / 2;
    end

    fig = uifigure('Name', 'Edit Groups', 'Position', position, ...
        'Color', bgColor, 'Resize', 'off');

    outer = uigridlayout(fig, [4, 1], 'RowHeight', {40, 24, '1x', 46}, ...
        'Padding', [0 0 0 0], 'RowSpacing', 0);

    header = uilabel(outer, 'Text', '  Edit Groups', 'FontSize', 14, ...
        'FontWeight', 'bold', 'FontColor', [1 1 1], 'BackgroundColor', accentColor, ...
        'VerticalAlignment', 'center');
    header.Layout.Row = 1;

    subtitle = uilabel(outer, ...
        'Text', '  Assign a between-subjects group per subject (blank = none). Use Save WorkSpace to keep this.', ...
        'FontColor', [0.4 0.4 0.4], 'VerticalAlignment', 'center');
    subtitle.Layout.Row = 2;

    if isempty(subjects)
        rowsGrid = uigridlayout(outer, [1, 1], 'Padding', [16 8 16 8]);
        rowsGrid.Layout.Row = 3;
        uilabel(rowsGrid, 'Text', 'No subjects in this workspace yet.', 'FontColor', [0.5 0.5 0.5]);
        fields = {};
    else
        scrollPanel = uipanel(outer, 'Scrollable', 'on', 'BorderType', 'none', ...
            'BackgroundColor', bgColor);
        scrollPanel.Layout.Row = 3;
        rowsGrid = uigridlayout(scrollPanel, [numel(subjects), 2], ...
            'ColumnWidth', {'1.4x', '1x'}, 'RowHeight', repmat({30}, 1, numel(subjects)), ...
            'Padding', [16 10 16 10], 'RowSpacing', 8, 'Scrollable', 'on');
        fields = gobjects(1, numel(subjects));
        for i = 1:numel(subjects)
            label = uilabel(rowsGrid, 'Text', subjects{i}, 'VerticalAlignment', 'center');
            label.Layout.Row = i;
            label.Layout.Column = 1;
            fields(i) = uieditfield(rowsGrid, 'text', 'Value', this.groupFor(subjects{i}), ...
                'Placeholder', 'Group (blank = none)');
            fields(i).Layout.Row = i;
            fields(i).Layout.Column = 2;
        end
    end

    buttonRow = uigridlayout(outer, [1, 3], 'ColumnWidth', {'1x', 90, 90}, ...
        'Padding', [16 6 16 10], 'ColumnSpacing', 8);
    buttonRow.Layout.Row = 4;
    cancelBtn = uibutton(buttonRow, 'Text', 'Cancel', 'ButtonPushedFcn', @(~, ~) onCancel());
    cancelBtn.Layout.Column = 2;
    okBtn = uibutton(buttonRow, 'Text', 'OK', 'BackgroundColor', accentColor, ...
        'FontColor', [1 1 1], 'ButtonPushedFcn', @(~, ~) onOK());
    okBtn.Layout.Column = 3;

    fig.CloseRequestFcn = @(~, ~) onCancel();

    uiwait(fig);

    function onOK()
        newGroups = struct('subject', {}, 'group', {});
        for k = 1:numel(subjects)
            grp = strtrim(fields(k).Value);
            if ~isempty(grp)
                newGroups(end + 1) = struct('subject', subjects{k}, 'group', grp); %#ok<AGROW>
            end
        end
        this.Groups = newGroups;
        delete(fig);
    end

    function onCancel()
        delete(fig);
    end
end
