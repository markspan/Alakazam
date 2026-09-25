function options = EyeTrackingDialog(EEG, ascFile, stored)
%EYETRACKINGDIALOG  Modal editor for EyeTracking's settings.
%   OPTIONS = EyeTrackingDialog(EEG, ASCFILE, STORED) shows the eye-tracking
%   file found for this recording, the trigger keyword, the anchor triggers,
%   which columns to import, and the limits the synchronisation is held to,
%   seeded from STORED (a previous run's options, or [] on first use). It
%   returns the options EyeTracking takes, or [] on Cancel.
%
%   IT READS THE FILE BEFORE ANYTHING IS JOINED. The preview says how many
%   triggers the eye track has under the keyword given, how many numbered
%   triggers the EEG has, which codes both share, and which two the
%   alignment will be anchored on. A wrong keyword shows up here as an eye
%   track with no triggers, which is the commonest reason a join fails and
%   the one a user can fix in this dialog. It re-reads when the keyword
%   changes, since the keyword decides which messages count as triggers.
%
%   See also EYETRACKING, EYEEEG.SHAREDANCHORS, EYEEEG.PARSE.
    options = [];
    seed = seedFrom(stored);
    [codes, triggerCount] = EyeEeg.triggerCodes(EEG);
    et = [];

    [accentColor, bgColor] = dialogChromeColors();
    fig = uifigure('Name', 'Eye tracking', 'Position', fitOnScreen([140 140 700 600]), 'Color', bgColor);
    root = uigridlayout(fig, [2 1], 'RowHeight', {40, '1x'}, 'Padding', [0 0 0 0], 'RowSpacing', 0);
    uilabel(root, 'Text', '  Eye tracking: join the EyeLink recording onto this EEG', 'FontSize', 14, ...
        'FontWeight', 'bold', 'FontColor', [1 1 1], 'BackgroundColor', accentColor, ...
        'VerticalAlignment', 'center');
    outer = uigridlayout(root, [6 1], 'RowHeight', {'fit', 'fit', 'fit', '1x', 'fit', 44});

    uilabel(outer, 'WordWrap', 'on', 'Text', ['Eye-tracking file: ' ascFile]);

    settings = uigridlayout(outer, [4 4], 'ColumnWidth', {200, 110, 210, 90}, ...
        'RowHeight', repmat({'fit'}, 1, 4), 'Padding', [0 0 0 0], 'RowSpacing', 4);
    uilabel(settings, 'Text', 'Message keyword (blank: INPUT lines):');
    keywordField = uieditfield(settings, 'text', 'Value', seed.keyword, 'Tag', 'keyword', ...
        'ValueChangedFcn', @(~, ~) readEyeTrack());
    uilabel(settings, 'Text', 'Fewest shared triggers:');
    minSharedField = uieditfield(settings, 'numeric', 'Value', seed.minSharedEvents, ...
        'Limits', [1 Inf], 'RoundFractionalValues', 'on');
    uilabel(settings, 'Text', 'Start trigger (blank: automatic):');
    startField = uieditfield(settings, 'text', 'Value', codeText(seed.startEvent), 'Tag', 'startEvent', ...
        'ValueChangedFcn', @(~, ~) showPreview());
    uilabel(settings, 'Text', 'Least % within one sample:');
    minPctField = uieditfield(settings, 'numeric', 'Value', seed.minPctWithinOne, 'Limits', [0 100]);
    uilabel(settings, 'Text', 'End trigger (blank: automatic):');
    endField = uieditfield(settings, 'text', 'Value', codeText(seed.endEvent), 'Tag', 'endEvent', ...
        'ValueChangedFcn', @(~, ~) showPreview());
    uilabel(settings, 'Text', 'Search radius (samples):');
    radiusField = uieditfield(settings, 'numeric', 'Value', seed.searchRadius, ...
        'Limits', [1 Inf], 'RoundFractionalValues', 'on');
    eventsBox = uicheckbox(settings, 'Text', 'Import the tracker''s own saccades, fixations and blinks', ...
        'Value', seed.importEyeEvents);
    eventsBox.Layout.Row = 4;
    eventsBox.Layout.Column = [1 2];
    filterBox = uicheckbox(settings, 'Text', 'Filter at Nyquist when resampling', ...
        'Value', seed.filterEyetrack);
    filterBox.Layout.Row = 4;
    filterBox.Layout.Column = [3 4];

    uilabel(outer, 'WordWrap', 'on', 'FontColor', [0.35 0.35 0.35], 'Text', [ ...
        'The two recordings are lined up through the numbered triggers both received, with a ' ...
        'line fitted through every shared one, as EYE-EEG does. A join that finds too few shared ' ...
        'triggers, or too few of them within one sample of their partner, is refused rather ' ...
        'than made: a bad alignment moves every event and gaze sample, and nothing later can ' ...
        'tell. The defaults for the search radius and filtering are EYE-EEG''s own.']);

    middle = uigridlayout(outer, [1 2], 'ColumnWidth', {'1x', 200}, 'Padding', [0 0 0 0], ...
        'ColumnSpacing', 8);
    preview = uitextarea(middle, 'Editable', 'off', 'Tag', 'preview', ...
        'Value', {'Reading the eye-tracking file...'});
    picker = uigridlayout(middle, [2 1], 'RowHeight', {'fit', '1x'}, 'Padding', [0 0 0 0]);
    uilabel(picker, 'WordWrap', 'on', 'Text', 'Columns to import as channels:');
    columnTree = uitree(picker, 'checkbox');

    buttons = uigridlayout(outer, [1 3], 'ColumnWidth', {'1x', 90, 90}, 'Padding', [8 6 8 6]);
    cancelButton = uibutton(buttons, 'Text', 'Cancel', 'ButtonPushedFcn', @(~, ~) onCancel());
    cancelButton.Layout.Column = 2;
    okButton = uibutton(buttons, 'Text', 'OK', 'BackgroundColor', accentColor, ...
        'FontColor', [1 1 1], 'ButtonPushedFcn', @(~, ~) onOK());
    okButton.Layout.Column = 3;
    fig.CloseRequestFcn = @(~, ~) onCancel();

    drawnow;
    readEyeTrack();
    uiwait(fig);

    function readEyeTrack()
    %READEYETRACK  Parse the file under the current keyword, then refresh.
        preview.Value = {'Reading the eye-tracking file...'};
        drawnow;
        matFile = [tempname() '.mat'];
        try
            et = EyeEeg.parse(ascFile, matFile, keywordField.Value);
        catch err
            et = [];
            preview.Value = [{'The eye-tracking file could not be read:'}, {''}, {err.message}];
        end
        if isfile(matFile)
            delete(matFile);
        end
        if ~isempty(et)
            fillColumns();
            showPreview();
        end
    end

    function fillColumns()
    %FILLCOLUMNS  One tick box per column the join could import, ticked as
    %   stored; EyeEeg.columns decides both, as it does for the join itself.
        [~, names] = EyeEeg.columns(et.colheader, 'all');
        [~, stored] = EyeEeg.columns(et.colheader, seed.columns);
        delete(columnTree.Children);
        for k = 1:numel(names)
            uitreenode(columnTree, 'Text', names{k}, 'NodeData', names{k});
        end
        nodes = columnTree.Children;
        setChecked(columnTree, nodes(ismember(names, stored)));
    end

    function showPreview()
    %SHOWPREVIEW  What the join would use, said before it runs.
        if isempty(et)
            return;
        end
        etCount = 0;
        if isfield(et, 'event')
            etCount = size(et.event, 1);
        end
        [autoStart, autoEnd, shared] = EyeEeg.sharedAnchors(codes, et);
        source = 'the parallel-port INPUT lines';
        if ~isempty(strtrim(keywordField.Value))
            source = sprintf('messages with the keyword "%s"', strtrim(keywordField.Value));
        end
        lines = {sprintf('Eye track: %d trigger(s), read from %s.', etCount, source), ...
                 sprintf('EEG: %d numbered trigger(s).', triggerCount), ''};
        if isempty(shared)
            lines{end + 1} = ['No trigger number occurs in both, so the two cannot be lined ' ...
                'up. If the eye track has none at all, the keyword is probably not the one the ' ...
                'experiment sent.'];
        else
            lines{end + 1} = sprintf('Codes in both: %s.', codeList(shared));
            [startCode, endCode] = anchors(autoStart, autoEnd);
            lines{end + 1} = sprintf('Anchored on the first %s and the last %s.', ...
                codeText(startCode), codeText(endCode));
        end
        preview.Value = lines;
    end

    function [startCode, endCode] = anchors(autoStart, autoEnd)
        startCode = parseCode(startField.Value);
        endCode = parseCode(endField.Value);
        if isempty(startCode); startCode = autoStart; end
        if isempty(endCode); endCode = autoEnd; end
    end

    function onOK()
        startCode = parseCode(startField.Value);
        endCode = parseCode(endField.Value);
        if (~isempty(strtrim(startField.Value)) && isempty(startCode)) || ...
                (~isempty(strtrim(endField.Value)) && isempty(endCode))
            uialert(fig, 'A trigger is a whole number, or left blank to be chosen automatically.', ...
                'Check the triggers');
            return;
        end
        checked = columnTree.CheckedNodes;
        if isempty(checked)
            uialert(fig, 'Would you tick at least one column to import?', 'Check the columns');
            return;
        end
        if numel(checked) == numel(columnTree.Children)
            columns = 'all';      % kept as the word, so a recording with more columns gets them too
        else
            columns = reshape({checked.NodeData}, 1, []);
        end
        options = struct('keyword', strtrim(keywordField.Value), ...
            'startEvent', startCode, 'endEvent', endCode, 'columns', {columns}, ...
            'importEyeEvents', eventsBox.Value, 'filterEyetrack', filterBox.Value, ...
            'searchRadius', radiusField.Value, 'minSharedEvents', minSharedField.Value, ...
            'minPctWithinOne', minPctField.Value);
        uiresume(fig);
        delete(fig);
    end

    function onCancel()
        uiresume(fig);
        delete(fig);
    end
end

% ======================================================================= %
function seed = seedFrom(stored)
%SEEDFROM  The stored options with the defaults filled in. startEvent and
%   endEvent are read directly: empty is an answer there ("automatic").
    seed = struct('keyword', '', 'startEvent', [], 'endEvent', [], 'columns', 'all', ...
        'importEyeEvents', true, 'filterEyetrack', false, 'searchRadius', 4, ...
        'minSharedEvents', 10, 'minPctWithinOne', 90);
    if ~isstruct(stored)
        return;
    end
    for name = fieldnames(seed)'
        if isfield(stored, name{1}) && (~isempty(stored.(name{1})) || ...
                any(strcmp(name{1}, {'startEvent', 'endEvent', 'keyword'})))
            seed.(name{1}) = stored.(name{1});
        end
    end
    seed.keyword = char(string(seed.keyword));
    seed.importEyeEvents = logical(seed.importEyeEvents);
    seed.filterEyetrack = logical(seed.filterEyetrack);
end

function code = parseCode(text)
%PARSECODE  A whole number, or [] for blank or anything else.
    code = [];
    text = strtrim(char(string(text)));
    value = str2double(text);
    if ~isempty(text) && isfinite(value) && value == round(value)
        code = value;
    end
end

function text = codeText(code)
    if isempty(code)
        text = '';
    else
        text = sprintf('%d', code);
    end
end

function text = codeList(codes)
    if numel(codes) <= 16
        text = strjoin(arrayfun(@(c) sprintf('%d', c), codes, 'UniformOutput', false), ', ');
    else
        text = sprintf('%d different codes, from %d to %d', numel(codes), codes(1), codes(end));
    end
end

function setChecked(tree, nodes)
%SETCHECKED  Tick exactly NODES; "none" has to be [] (see DeconvolveDialog).
    if isempty(nodes)
        tree.CheckedNodes = [];
    else
        tree.CheckedNodes = nodes;
    end
end
