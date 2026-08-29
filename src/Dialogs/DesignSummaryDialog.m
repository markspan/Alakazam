function DesignSummaryDialog(design, parentFig)
%DESIGNSUMMARYDIALOG  Show the design Alakazam has read from the workspace.
%
%   Read-only, deliberately. This phase states what the records amount to;
%   it does not let the design be edited, because the design is derived
%   from Edit Subjects and each Average's own bins (see deriveDesign), and
%   an editable copy could disagree with them. To change the design, change
%   what it is read from.
%
%   Three parts, in the order a reader needs them: what is wrong (if
%   anything), the factors and their levels, and the cell counts. Warnings
%   come first rather than last -- an empty cell or a subject in two groups
%   is the reason to have opened this at all, and burying it under a table
%   would defeat the point.
%
%   uifigure-based and styled to match Edit Subjects, its sibling in the
%   Home tab's Design group.
%
%   See also DERIVEDESIGN, ALAKAZAM.ONSHOWDESIGN, WORKSPACE.EDITSUBJECTS.
    accentColor = [0.290 0.498 0.788];   % AlakazamRibbon.html's .alz-tab-home (#4a7fc9)
    warnColor   = [0.753 0.255 0.247];   % the Icons' own red accent (#c0413f)
    bgColor     = [0.9608 0.9608 0.9608];

    position = [420 300 720 620];
    if nargin >= 2 && ~isempty(parentFig) && isvalid(parentFig)
        parentPos = parentFig.Position;
        position(1) = parentPos(1) + (parentPos(3) - position(3)) / 2;
        position(2) = parentPos(2) + (parentPos(4) - position(4)) / 2;
    end

    fig = uifigure('Name', 'Study design', 'Position', position, 'Color', bgColor);
    outer = uigridlayout(fig, [3, 1], 'RowHeight', {40, '1x', 46}, ...
        'Padding', [0 0 0 0], 'RowSpacing', 0);

    header = uilabel(outer, 'Text', '  Study design', 'FontSize', 14, ...
        'FontWeight', 'bold', 'FontColor', [1 1 1], 'BackgroundColor', accentColor, ...
        'VerticalAlignment', 'center');
    header.Layout.Row = 1;

    body = uigridlayout(outer, [4, 1], 'RowHeight', {'fit', 'fit', 'fit', '1x'}, ...
        'Padding', [16 12 16 8], 'RowSpacing', 12, 'Scrollable', 'on');
    body.Layout.Row = 2;

    addSummary(body, design);
    addWarnings(body, design, warnColor);
    addFactors(body, design);
    addCells(body, design);

    buttonRow = uigridlayout(outer, [1, 2], 'ColumnWidth', {'1x', 90}, ...
        'Padding', [16 6 16 10]);
    buttonRow.Layout.Row = 3;
    closeBtn = uibutton(buttonRow, 'Text', 'Close', 'BackgroundColor', accentColor, ...
        'FontColor', [1 1 1], 'ButtonPushedFcn', @(~, ~) delete(fig));
    closeBtn.Layout.Column = 2;
end

% ----------------------------------------------------------------------- %
function addSummary(parent, design)
    text = sprintf('%d recording(s) from %d subject(s) in the study.', ...
        design.nRecordings, design.nPersons);
    if design.nRecordings ~= design.nPersons
        text = [text ' Some subjects were recorded more than once.'];
    end
    if isfield(design, 'nExcluded') && design.nExcluded > 0
        text = sprintf('%s %d further recording(s) are excluded under Grouping.', ...
            text, design.nExcluded);
    end
    label = uilabel(parent, 'Text', text, 'WordWrap', 'on');
    label.Layout.Row = 1;
end

function addWarnings(parent, design, warnColor)
%ADDWARNINGS  First, and only when there is something to say. A panel that
%   always shows an empty "Warnings" heading trains the reader to skip it.
    if isempty(design.warnings)
        panel = uipanel(parent, 'Title', '', 'BorderType', 'none');
        panel.Layout.Row = 2;
        uilabel(uigridlayout(panel, [1 1], 'Padding', [0 0 0 0]), ...
            'Text', 'Nothing to flag: every cell is filled and every subject is consistent.', ...
            'FontColor', [0.35 0.35 0.35], 'WordWrap', 'on');
        return;
    end

    panel = uipanel(parent, 'Title', 'Worth checking', 'FontWeight', 'bold', ...
        'ForegroundColor', warnColor);
    panel.Layout.Row = 2;
    grid = uigridlayout(panel, [numel(design.warnings), 1], ...
        'RowHeight', repmat({'fit'}, 1, numel(design.warnings)), ...
        'Padding', [10 8 10 8], 'RowSpacing', 4);
    for i = 1:numel(design.warnings)
        uilabel(grid, 'Text', design.warnings{i}, 'WordWrap', 'on');
    end
end

function addFactors(parent, design)
    panel = uipanel(parent, 'Title', 'Factors', 'FontWeight', 'bold');
    panel.Layout.Row = 3;
    grid = uigridlayout(panel, [1 1], 'Padding', [8 8 8 8]);

    rows = cell(numel(design.factors), 4);
    for i = 1:numel(design.factors)
        f = design.factors(i);
        rows{i, 1} = f.name;
        rows{i, 2} = f.type;
        rows{i, 3} = levelsText(f.levels);
        rows{i, 4} = f.note;
    end
    t = uitable(grid, 'Data', rows, ...
        'ColumnName', {'Factor', 'Type', 'Levels', 'Note'}, ...
        'ColumnWidth', {80, 75, 220, 'auto'}, ...
        'RowName', {}, 'ColumnEditable', false(1, 4));
    t.Layout.Row = 1;
end

function addCells(parent, design)
%ADDCELLS  The counts, in subjects and in recordings. Both, because they
%   differ whenever anyone was recorded twice, and a between-subjects n is
%   the first number rather than the second.
    panel = uipanel(parent, 'Title', 'Cells', 'FontWeight', 'bold');
    panel.Layout.Row = 4;
    grid = uigridlayout(panel, [1 1], 'Padding', [8 8 8 8]);

    rows = cell(numel(design.cells), 4);
    for i = 1:numel(design.cells)
        c = design.cells(i);
        rows{i, 1} = c.group;
        rows{i, 2} = c.session;
        rows{i, 3} = c.nPersons;
        rows{i, 4} = c.nRecordings;
    end
    t = uitable(grid, 'Data', rows, ...
        'ColumnName', {'Group', 'Session', 'Subjects', 'Recordings'}, ...
        'ColumnWidth', {160, 160, 90, 100}, ...
        'RowName', {}, 'ColumnEditable', false(1, 4));
    t.Layout.Row = 1;

    % An empty cell is the thing most worth seeing in this table, so it is
    % marked in the table itself as well as in the warnings above.
    empty = find([design.cells.nPersons] == 0);
    if ~isempty(empty)
        try
            s = uistyle('BackgroundColor', [0.98 0.92 0.92]);
            addStyle(t, s, 'row', empty);
        catch
            % uistyle is unavailable in some configurations; the warning
            % above already carries the same information, so this is a
            % presentation nicety rather than the message itself.
        end
    end
end

function text = levelsText(levels)
    if isempty(levels)
        text = '(none)';
    else
        text = strjoin(cellfun(@(l) char(string(l)), levels, 'UniformOutput', false), ', ');
    end
end
