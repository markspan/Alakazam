function editSubjects(this, ~, ~)
%EDITSUBJECTS  "Edit Subjects" dialog (formerly "Edit Groups"): one row
%   per raw file (every root node in Tree -- Data & Analyses' own
%   per-subject branches, the same identity collectEntriesWithField
%   resolves as .subject via Tree.rootOf), with three editable fields:
%
%     - Person ID: which real person this raw file belongs to. Pre-filled
%       with the raw file's own name (today's implicit behaviour: every
%       raw file is its own person), so it needs editing ONLY for a
%       multi-session design -- give two raw files ("...day1", "...day2")
%       the SAME Person ID to tell Alakazam they are the same person
%       measured twice, rather than two unrelated subjects.
%     - Session: an optional label for which session/day/visit this raw
%       file is ("Day 1", "Pre", "Post", ...), blank if not applicable.
%     - Group: the between-subjects group (unchanged from the original
%       "Edit Groups" dialog), blank meaning "no group assigned" --
%       groupFor returns '' for it, and generateQuartoReport's between-
%       subjects/mixed branch only activates once at least two DISTINCT
%       non-blank labels exist, so leaving every row's Group blank is
%       exactly today's within-subject-only behaviour, unchanged. Group
%       is conceptually a property of the PERSON, not of one recording,
%       so it should normally read the same across every raw file that
%       shares a Person ID -- not enforced here, since keeping this
%       dialog a plain per-row table is simpler than reconciling
%       conflicting entries, but worth keeping consistent by hand.
%
%   uifigure-based, same header/button style as WorkSpace.edit -- but a
%   scrollable middle panel, not a fixed grid, since the subject count is
%   open-ended (a handful in a pilot dataset, dozens in a full study).
%
%   OK copies every row into this.Groups (this WorkSpace instance only --
%   like TransformSettings and the three directories, it does not touch
%   disk until the analyst explicitly does "Save WorkSpace"). Cancel (or
%   closing the window) discards changes.
%
%   Person ID/Session are metadata only so far: they reach the exported
%   CSV (person_id/session columns, see collectEntriesWithField/
%   exportMeasurementsCSV/exportSpectralCSV) for a researcher's own
%   analysis, but generateQuartoReport does not yet treat session as a
%   statistical factor the way it does bin/group.
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
    position = [380 260 700 460];
    if ~isempty(parentFig)
        parentPos = parentFig.Position;
        position(1) = parentPos(1) + (parentPos(3) - position(3)) / 2;
        position(2) = parentPos(2) + (parentPos(4) - position(4)) / 2;
    end

    fig = uifigure('Name', 'Edit Subjects', 'Position', position, ...
        'Color', bgColor, 'Resize', 'on');

    outer = uigridlayout(fig, [5, 1], 'RowHeight', {40, 24, 22, '1x', 46}, ...
        'Padding', [0 0 0 0], 'RowSpacing', 0);

    header = uilabel(outer, 'Text', '  Edit Subjects', 'FontSize', 14, ...
        'FontWeight', 'bold', 'FontColor', [1 1 1], 'BackgroundColor', accentColor, ...
        'VerticalAlignment', 'center');
    header.Layout.Row = 1;

    subtitle = uilabel(outer, ...
        'Text', ['  Person ID links multiple sessions (day 1/2, ...) of the same subject; ' ...
                 'Group is between-subjects. Save WorkSpace to keep this.'], ...
        'FontColor', [0.4 0.4 0.4], 'VerticalAlignment', 'center');
    subtitle.Layout.Row = 2;

    % Column headers, ROW 3 of OUTER -- a fixed row of its own, not a
    % child of scrollPanel below: two uigridlayouts sharing the same
    % plain (non-grid) parent each try to fill that parent's WHOLE
    % client area, so putting the header grid and the rows grid inside
    % the same scrollPanel made the rows grid (created after, so drawn
    % on top) completely cover the header -- present in the object tree,
    % invisible on screen, exactly what left the columns unlabelled.
    % Same ColumnWidth as rowsGrid below so the header text lines up
    % with the fields underneath it.
    columnsGrid = uigridlayout(outer, [1, 5], ...
        'ColumnWidth', {'1.2x', '0.95x', '0.75x', '0.75x', 60}, 'RowHeight', {22}, ...
        'Padding', [16 0 30 0], 'ColumnSpacing', 8);
    columnsGrid.Layout.Row = 3;
    boldLabel(columnsGrid, 'Raw file', 1);
    boldLabel(columnsGrid, 'Person ID', 2);
    boldLabel(columnsGrid, 'Session', 3);
    boldLabel(columnsGrid, 'Group', 4);
    boldLabel(columnsGrid, 'In study', 5);

    if isempty(subjects)
        rowsGrid = uigridlayout(outer, [1, 1], 'Padding', [16 8 16 8]);
        rowsGrid.Layout.Row = 4;
        uilabel(rowsGrid, 'Text', 'No subjects in this workspace yet.', 'FontColor', [0.5 0.5 0.5]);
        personFields = {};
        sessionFields = {};
        groupFields = {};
        includeBoxes = {};
    else
        scrollPanel = uipanel(outer, 'Scrollable', 'on', 'BorderType', 'none', ...
            'BackgroundColor', bgColor);
        scrollPanel.Layout.Row = 4;

        rowsGrid = uigridlayout(scrollPanel, [numel(subjects), 5], ...
            'ColumnWidth', {'1.2x', '0.95x', '0.75x', '0.75x', 60}, 'RowHeight', repmat({30}, 1, numel(subjects)), ...
            'Padding', [16 4 16 10], 'RowSpacing', 8, 'Scrollable', 'on');
        % Suggested Person IDs, only for rows nothing has been explicitly
        % typed into yet (see suggestedPersonIds's own header comment) --
        % a raw file's own name is otherwise the pre-fill (personFor's
        % established fallback), unchanged for a workspace this dialog
        % has never touched.
        suggested = suggestedPersonIds(subjects);
        personFields = gobjects(1, numel(subjects));
        sessionFields = gobjects(1, numel(subjects));
        groupFields = gobjects(1, numel(subjects));
        includeBoxes = gobjects(1, numel(subjects));
        for i = 1:numel(subjects)
            label = uilabel(rowsGrid, 'Text', subjects{i}, 'VerticalAlignment', 'center');
            label.Layout.Row = i;
            label.Layout.Column = 1;

            storedPerson = this.personFor(subjects{i});
            if strcmp(storedPerson, subjects{i})
                defaultPerson = suggested{i};
            else
                defaultPerson = storedPerson;
            end
            personFields(i) = uieditfield(rowsGrid, 'text', 'Value', defaultPerson);
            personFields(i).Layout.Row = i;
            personFields(i).Layout.Column = 2;

            sessionFields(i) = uieditfield(rowsGrid, 'text', 'Value', this.sessionFor(subjects{i}), ...
                'Placeholder', 'e.g. Day 1');
            sessionFields(i).Layout.Row = i;
            sessionFields(i).Layout.Column = 3;

            groupFields(i) = uieditfield(rowsGrid, 'text', 'Value', this.groupFor(subjects{i}), ...
                'Placeholder', 'blank = none');
            groupFields(i).Layout.Row = i;
            groupFields(i).Layout.Column = 4;

            % Ticked by default: a recording is in the study unless somebody
            % says otherwise. Unticking is how a recording is left out now,
            % in place of the old convention of clearing its Group and
            % letting the report's own filter drop it.
            includeBoxes(i) = uicheckbox(rowsGrid, 'Text', '', ...
                'Value', this.includedFor(subjects{i}));
            includeBoxes(i).Layout.Row = i;
            includeBoxes(i).Layout.Column = 5;
        end
    end

    buttonRow = uigridlayout(outer, [1, 3], 'ColumnWidth', {'1x', 90, 90}, ...
        'Padding', [16 6 16 10], 'ColumnSpacing', 8);
    buttonRow.Layout.Row = 5;
    cancelBtn = uibutton(buttonRow, 'Text', 'Cancel', 'ButtonPushedFcn', @(~, ~) onCancel());
    cancelBtn.Layout.Column = 2;
    okBtn = uibutton(buttonRow, 'Text', 'OK', 'BackgroundColor', accentColor, ...
        'FontColor', [1 1 1], 'ButtonPushedFcn', @(~, ~) onOK());
    okBtn.Layout.Column = 3;

    fig.CloseRequestFcn = @(~, ~) onCancel();

    uiwait(fig);

    function onOK()
        newGroups = struct('subject', {}, 'group', {}, 'person', {}, ...
            'session', {}, 'included', {});
        for k = 1:numel(subjects)
            grp = strtrim(groupFields(k).Value);
            person = strtrim(personFields(k).Value);
            session = strtrim(sessionFields(k).Value);
            included = logical(includeBoxes(k).Value);
            % A row with nothing set at all is dropped, not kept as an
            % empty entry -- same "blank means unassigned" convention
            % personFor/sessionFor/groupFor already treat a missing row
            % as, so this.Groups never accumulates dead rows for
            % subjects an analyst looked at but left untouched.
            %
            % An EXCLUDED row is never "nothing set", however blank its
            % other fields: dropping it would read back as included (see
            % includedFor's own default) and silently undo the exclusion on
            % the next open.
            untouched = isempty(grp) && isempty(session) ...
                && (isempty(person) || strcmp(person, subjects{k}));
            if untouched && included
                continue;
            end
            newGroups(end + 1) = struct('subject', subjects{k}, 'group', grp, ...
                'person', person, 'session', session, 'included', included); %#ok<AGROW>
        end
        this.Groups = newGroups;
        delete(fig);
    end

    function onCancel()
        delete(fig);
    end
end

function lbl = boldLabel(parent, text, column)
    lbl = uilabel(parent, 'Text', text, 'FontWeight', 'bold', 'FontColor', [0.35 0.35 0.35]);
    lbl.Layout.Row = 1;
    lbl.Layout.Column = column;
end

function suggestions = suggestedPersonIds(subjects)
%SUGGESTEDPERSONIDS  A cleaner Person ID guess per SUBJECT: every
%   substring longer than 3 characters that appears in ALL of SUBJECTS is
%   stripped out first (longest match first, repeated until none remain
%   -- see longestCommonSubstring), on the reasoning that a fragment
%   shared by every single recording (an experiment name like "N400",
%   say) cannot possibly help tell one subject apart from another, so
%   pre-filling it into every row's Person ID just adds noise the analyst
%   would otherwise have to notice and remove by hand, in every row,
%   themselves. What is LEFT after stripping (a subject number, a day
%   label, ...) is the part that actually varies.
%
%   A no-op (returns SUBJECTS unchanged) when fewer than two subjects
%   exist, or when no >3-character substring is common to all of them --
%   the raw file's own name is then exactly what personFor's own
%   fallback already returns, so editSubjects' own onOK correctly treats
%   an unedited row as "nothing to save" either way.
    suggestions = subjects;
    if numel(subjects) < 2
        return;
    end
    cleaned = subjects;
    while true
        tok = longestCommonSubstring(cleaned);
        if isempty(tok) || length(tok) <= 3
            break;
        end
        cleaned = cellfun(@(s) strrep(s, tok, ''), cleaned, 'UniformOutput', false);
    end
    suggestions = cellfun(@tidySeparators, cleaned, 'UniformOutput', false);
end

function tok = longestCommonSubstring(strs)
%LONGESTCOMMONSUBSTRING  The longest substring common to every string in
%   STRS (cellstr), '' if none (beyond the trivial empty one). Checked
%   against the shortest string first (fewest candidate substrings to
%   try), longest candidate substring first, so the first hit found is
%   already the longest.
    [~, shortestIdx] = min(cellfun(@length, strs));
    ref = strs{shortestIdx};
    tok = '';
    for len = length(ref):-1:1
        for startPos = 1:(length(ref) - len + 1)
            candidate = ref(startPos:startPos + len - 1);
            if all(cellfun(@(s) contains(s, candidate), strs))
                tok = candidate;
                return;
            end
        end
    end
end

function s = tidySeparators(s)
%TIDYSEPARATORS  Collapse the run of underscores/hyphens/spaces a
%   stripped-out token typically leaves behind (e.g. "12_N400_day1" minus
%   "N400" is "12__day1") into one, and trim a leading/trailing one --
%   cosmetic only, so the suggestion reads as a name, not a redaction.
    s = regexprep(s, '[_\-\s]{2,}', '_');
    s = regexprep(s, '^[_\-\s]+|[_\-\s]+$', '');
end
