function spec = GrandAverageDialog(candidateFiles, candidateLabels, candidateKinds, prefillSpec)
%GRANDAVERAGEDIALOG  Modal dialog: name, type, weighting, and which subjects
%   to combine into a grand average.
%
%   SPEC = GRANDAVERAGEDIALOG(CANDIDATEFILES, CANDIDATELABELS, CANDIDATEKINDS,
%   PREFILLSPEC) shows a small dialog listing the candidate subject datasets.
%   A grand average combines datasets of ONE kind -- ERP waveforms,
%   time-frequency maps, or coherence maps -- so a "Type" selector puts each
%   kind in its own selection list (CANDIDATEKINDS is each candidate's kind,
%   'ERP' / 'TF' / 'coherence'), and only that type's subjects are shown at a
%   time. Weighting applies to ERPs only; it is disabled for the map types
%   (their grand average is an equal-weight mean).
%
%   PREFILLSPEC is [] for a brand new grand average (name editable, type
%   selectable, nothing pre-selected), or a struct with fields .name,
%   .sources and .weighted when revisiting an existing one (name and type are
%   then fixed; its current sources/weighting are pre-selected).
%
%   Returns a struct with .name, .sources (the selected files) and .weighted,
%   or [] if the analyst cancelled.

    spec = [];
    isNew = isempty(prefillSpec);
    candidateKinds = cellfun(@char, candidateKinds, 'UniformOutput', false);

    % Kinds actually present, in a stable preferred order.
    order = {'ERP', 'TF', 'coherence'};
    presentKinds = order(ismember(order, candidateKinds));
    if isempty(presentKinds); presentKinds = unique(candidateKinds); end

    % Nothing to offer: return rather than build a dropdown around it.
    % 'Value', presentKinds{1} below indexes this, so an empty candidate
    % list threw MATLAB:badsubscript ("Index exceeds array bounds") out of
    % the dialog instead of saying anything. onDefineGrandAverage and
    % onClusterStats both guard with their own "fewer than two" check and
    % never arrive here empty, but onRecalculateNode calls straight through
    % with no guard -- so recalculating an existing grand average in a
    % workspace that no longer offers its sources was a hard error, which
    % is precisely the moment the analyst most needs an explanation.
    if isempty(presentKinds)
        return;
    end

    weightChoices = {'Unweighted (every subject counts equally)', ...
                     'Weighted by each subject''s trial count'};

    % Header bar + accent styling, matching every other dialog's own look
    % (ReRefDialog, SelectDataDialog, ...) -- this was previously the one
    % dialog that skipped it, with no apparent reason to look unstyled
    % next to its siblings.
    [accentColor, bgColor] = dialogChromeColors();
    fig = uifigure('Name', 'Grand Average', 'Position', [100 100 480 460], 'Color', bgColor);
    root = uigridlayout(fig, [2 1], 'RowHeight', {40, '1x'}, 'Padding', [0 0 0 0], 'RowSpacing', 0);
    uilabel(root, 'Text', '  Grand Average', 'FontSize', 14, 'FontWeight', 'bold', ...
        'FontColor', [1 1 1], 'BackgroundColor', accentColor, 'VerticalAlignment', 'center');
    outer = uigridlayout(root, [5 1], 'RowHeight', {'fit', 'fit', 'fit', '1x', 44}, 'Padding', [10 10 10 10]);

    % Row 1: name.
    nameRow = uigridlayout(outer, [1 2], 'ColumnWidth', {90, '1x'}, 'Padding', [8 8 8 0]);
    nameRow.Layout.Row = 1;
    uilabel(nameRow, 'Text', 'Name:');
    if isNew; defaultName = ''; else; defaultName = prefillSpec.name; end
    nameField = uieditfield(nameRow, 'text', 'Value', defaultName, 'Editable', isNew);

    % Row 2: type (which kind of dataset to combine).
    typeRow = uigridlayout(outer, [1 2], 'ColumnWidth', {90, '1x'}, 'Padding', [8 8 8 0]);
    typeRow.Layout.Row = 2;
    uilabel(typeRow, 'Text', 'Type:');
    % The callback reads the new value off its own source (src.Value), not a
    % captured typeDrop -- typeDrop is still being assigned when this anonymous
    % function is created, so it would not be in scope when the callback fires.
    typeDrop = uidropdown(typeRow, 'Tag', 'gaType', ...
        'Items', cellfun(@kindDisplay, presentKinds, 'UniformOutput', false), ...
        'ItemsData', presentKinds, 'Value', presentKinds{1}, ...
        'ValueChangedFcn', @(src, ~) refreshForKind(src.Value));

    % Row 3: weighting (ERP only).
    weightRow = uigridlayout(outer, [1 2], 'ColumnWidth', {90, '1x'}, 'Padding', [8 8 8 0]);
    weightRow.Layout.Row = 3;
    uilabel(weightRow, 'Text', 'Weighting:');
    weightField = uidropdown(weightRow, 'Tag', 'gaWeight', 'Items', weightChoices, 'Value', weightChoices{1}, ...
        'Tooltip', 'Weighting applies to ERP grand averages only; map types are averaged equally.');

    % Row 4: subject picker (the selected type's datasets only).
    listRow = uigridlayout(outer, [2 1], 'RowHeight', {'fit', '1x'}, 'Padding', [8 8 8 0]);
    listRow.Layout.Row = 4;
    uilabel(listRow, 'Text', 'Include these subjects:');
    subjectList = uilistbox(listRow, 'Tag', 'gaSubjects', 'Items', {}, 'Multiselect', 'on');

    % Row 5: OK / Cancel.
    buttons = uigridlayout(outer, [1 3], 'ColumnWidth', {'1x', 90, 90}, 'Padding', [8 6 8 6]);
    buttons.Layout.Row = 5;
    cancelBtn = uibutton(buttons, 'Text', 'Cancel', 'ButtonPushedFcn', @(~,~) onCancel());
    cancelBtn.Layout.Column = 2;
    okBtn = uibutton(buttons, 'Tag', 'gaOK', 'Text', 'Compute', 'BackgroundColor', accentColor, ...
        'FontColor', [1 1 1], 'ButtonPushedFcn', @(~,~) onOK());
    okBtn.Layout.Column = 3;
    fig.CloseRequestFcn = @(~,~) onCancel();

    % Initial population. For a recalculation the kind is fixed (the type of
    % the sources already stored); for a new one it starts on the first kind.
    if isNew
        refreshForKind(presentKinds{1});
    else
        prefillKind = kindOfSources(prefillSpec.sources, candidateFiles, candidateKinds, presentKinds{1});
        typeDrop.Value = prefillKind;
        typeDrop.Enable = 'off';           % a grand average's kind never changes
        refreshForKind(prefillKind);
        subjectList.Value = intersect(prefillSpec.sources, subjectList.ItemsData);
        if strcmp(prefillKind, 'ERP') && prefillSpec.weighted
            weightField.Value = weightChoices{2};
        end
    end

    uiwait(fig);

    function refreshForKind(kind)
        mask = strcmp(candidateKinds, kind);
        % Clear the selection and detach ItemsData before swapping Items:
        % setting Items to a different length while the old ItemsData is still
        % attached is a transient length mismatch that uilistbox rejects.
        subjectList.Value     = {};
        subjectList.ItemsData = {};
        subjectList.Items     = candidateLabels(mask);
        subjectList.ItemsData = candidateFiles(mask);
        if strcmp(kind, 'ERP')
            weightField.Enable = 'on';
        else
            weightField.Enable = 'off';
            weightField.Value  = weightChoices{1};
        end
    end

    function onOK()
        name = strtrim(nameField.Value);
        if isempty(name)
            uialert(fig, 'Would you give this grand average a name before continuing?', 'Name needed');
            return;
        end
        if numel(subjectList.Value) < 2
            uialert(fig, 'I''m afraid at least two subjects of the selected type need to be picked.', 'Not enough subjects');
            return;
        end
        weighted = strcmp(typeDrop.Value, 'ERP') && strcmp(weightField.Value, weightChoices{2});
        spec = struct('name', name, 'sources', {subjectList.Value}, 'weighted', weighted);
        uiresume(fig);
        delete(fig);
    end

    function onCancel()
        uiresume(fig);
        delete(fig);
    end
end

% ----------------------------------------------------------------------- %
function name = kindDisplay(kind)
    switch kind
        case 'ERP';       name = 'ERP waveforms';
        case 'TF';        name = 'Time-frequency maps';
        case 'coherence'; name = 'Coherence maps';
        otherwise;        name = char(kind);
    end
end

function kind = kindOfSources(sources, candidateFiles, candidateKinds, fallback)
%KINDOFSOURCES  The kind of a prefilled grand average, read off its first
%   source that is still a candidate; FALLBACK if none match.
    kind = fallback;
    for i = 1:numel(sources)
        idx = find(strcmp(candidateFiles, sources{i}), 1);
        if ~isempty(idx)
            kind = candidateKinds{idx};
            return;
        end
    end
end
