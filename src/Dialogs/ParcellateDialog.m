function options = ParcellateDialog(~)
%PARCELLATEDIALOG  Choose an inverse method, an atlas and which regions to keep.
%   OPTIONS = ParcellateDialog(EEG) returns the settings Parcellate should
%   record, or [] if the analyst cancelled.
%
%   THE REGION LIST IS THE POINT OF THIS DIALOG. AAL yields 85-odd usable
%   cortical regions, and carrying all of them into ERP Measure and a report
%   would produce a document nobody reads and a multiple-comparison problem
%   nobody planned. Choosing regions here is the same discipline as choosing
%   channels: it asks for a hypothesis before it produces numbers.
%
%   Selecting nothing keeps every region, which is offered but is not the
%   default posture -- the list starts empty precisely so that "all of them"
%   is a decision rather than an oversight.
%
%   Building the list needs only the cortical sheet and the atlas, NOT a
%   leadfield (see TransTools.TemplateSourceModel): a dialog that had to
%   compute a full forward model before it could show region names would
%   take minutes to open.
%
%   See also PARCELLATE, TRANSTOOLS.PARCELLATESOURCE, TRANSTOOLS.ATLASVERTEXLABELS.
    options = [];
    stored = TransformSettings.get('Parcellate');

    fig = uifigure('Name', 'Parcellate into regions', 'Position', centredOn([], 720, 620));
    try
        sourcemodel = localBusy(fig, 'Reading the cortical atlas...', ...
            @() TransTools.TemplateSourceModel());
        atlasNames = {'aal', 'brainnetome'};
        [regionNames, regionCounts] = localBusy(fig, 'Reading the cortical atlas...', ...
            @() regionsFor(sourcemodel, 'aal'));
    catch err
        delete(fig);
        rethrow(err);
    end

    outer = uigridlayout(fig, [5 1], 'RowHeight', {'fit', 'fit', '1x', 'fit', 44}, ...
        'Padding', [12 12 12 12], 'RowSpacing', 8);

    % ---- method / atlas ----------------------------------------------------
    top = uigridlayout(outer, [2 4], 'ColumnWidth', {74, '1x', 96, '1x'}, ...
        'RowHeight', {'fit', 'fit'}, 'Padding', [0 0 0 0], 'ColumnSpacing', 8);
    top.Layout.Row = 1;

    uilabel(top, 'Text', 'Method');
    methodDrop = uidropdown(top, ...
        'Items', {'dSPM (noise-normalized)', 'eLORETA', 'sLORETA'}, ...
        'ItemsData', {'mne', 'eloreta', 'sloreta'}, ...
        'Value', TransTools.FieldOr(stored, 'Method', 'mne'));

    uilabel(top, 'Text', 'Aggregation');
    modeDrop = uidropdown(top, ...
        'Items', {'Mean with sign flip (recommended)', 'Plain mean'}, ...
        'ItemsData', {'mean_flip', 'mean'}, ...
        'Value', TransTools.FieldOr(stored, 'Mode', 'mean_flip'), ...
        'Tooltip', ['Cortex is folded, so opposite walls of a sulcus record the same ' ...
            'source with opposite sign. A plain mean cancels most of a real effect for ' ...
            'that purely geometric reason, and it fails silently -- it returns a small ' ...
            'number, not an error. Sign flipping aligns each region''s vertices to their ' ...
            'own dominant normal first; measured on the real cortical sheet it recovers ' ...
            'about three times the amplitude a plain mean does.']);

    uilabel(top, 'Text', 'Atlas');
    atlasDrop = uidropdown(top, 'Items', atlasNames, 'Value', 'aal');

    uilabel(top, 'Text', 'Min vertices');
    minField = uieditfield(top, 'numeric', 'Value', TransTools.FieldOr(stored, 'MinVertices', 20), ...
        'Limits', [1 Inf], 'RoundFractionalValues', 'on', ...
        'Tooltip', 'Regions with fewer usable vertices than this are dropped rather than reported from a handful.');

    % ---- the caveat, where it cannot be missed -------------------------------
    warn = uilabel(outer, 'WordWrap', 'on', 'FontColor', [0.55 0.33 0.10], ...
        'Text', ['A region name reads like an anatomical finding in a way "channel P7" ' ...
            'never does. This is a template head model, template electrode positions ' ...
            'AND a template atlas: an approximation, not a per-subject localization. ' ...
            'Neighbouring regions are also strongly correlated, so these are nowhere ' ...
            'near independent tests.']);
    warn.Layout.Row = 2;

    % ---- region list ---------------------------------------------------------
    listBox = uilistbox(outer, 'Multiselect', 'on', ...
        'Items', displayItems(regionNames, regionCounts), 'ItemsData', regionNames, ...
        'Value', {});
    listBox.Layout.Row = 3;
    preselect(listBox, regionNames, TransTools.FieldOr(stored, 'Regions', {}));

    countLabel = uilabel(outer, 'Text', '', 'WordWrap', 'on');
    countLabel.Layout.Row = 4;
    listBox.ValueChangedFcn = @(~, ~) refreshCount();
    atlasDrop.ValueChangedFcn = @(~, ~) onAtlasChanged();
    refreshCount();

    % ---- buttons --------------------------------------------------------------
    buttons = uigridlayout(outer, [1 4], 'ColumnWidth', {110, '1x', 90, 90}, ...
        'Padding', [0 4 0 0]);
    buttons.Layout.Row = 5;
    uibutton(buttons, 'Text', 'Select all', 'ButtonPushedFcn', @(~, ~) selectAll());
    cancelBtn = uibutton(buttons, 'Text', 'Cancel', 'ButtonPushedFcn', @(~, ~) onCancel());
    cancelBtn.Layout.Column = 3;
    okBtn = uibutton(buttons, 'Text', 'OK', 'ButtonPushedFcn', @(~, ~) onOK());
    okBtn.Layout.Column = 4;
    fig.CloseRequestFcn = @(~, ~) onCancel();

    uiwait(fig);

    % ===================================================================== %
    function onAtlasChanged()
        try
            [regionNames, regionCounts] = localBusy(fig, 'Reading the cortical atlas...', ...
                @() regionsFor(sourcemodel, atlasDrop.Value));
        catch err
            uialert(fig, err.message, 'Could not read that atlas');
            return;
        end
        listBox.Items = displayItems(regionNames, regionCounts);
        listBox.ItemsData = regionNames;
        listBox.Value = {};   % a selection from another atlas means nothing here
        refreshCount();
    end

    function refreshCount()
        n = numel(listBox.Value);
        if n == 0
            countLabel.Text = sprintf(['Nothing selected: ALL %d regions will be kept. ' ...
                'That is a long report and a lot of comparisons.'], numel(regionNames));
            countLabel.FontColor = [0.55 0.33 0.10];
        else
            countLabel.Text = sprintf('%d of %d regions selected.', n, numel(regionNames));
            countLabel.FontColor = [0.25 0.25 0.25];
        end
    end

    function selectAll()
        listBox.Value = listBox.ItemsData;
        refreshCount();
    end

    function onOK()
        options = struct( ...
            'Method',      methodDrop.Value, ...
            'Atlas',       atlasDrop.Value, ...
            'Mode',        modeDrop.Value, ...
            'MinVertices', minField.Value, ...
            'Regions',     {cellstr(string(listBox.Value(:)'))});
        uiresume(fig);
        delete(fig);
    end

    function onCancel()
        options = [];
        uiresume(fig);
        delete(fig);
    end
end

% ======================================================================= %
function varargout = localBusy(fig, message, fn)
%LOCALBUSY  A spinner on THIS dialog only, deliberately NOT beginBusy.
%
%   beginBusy drives busyGate, which is a single global indicator owned by
%   one figure at a time: 'open' replaces its whole state, including which
%   figure owns it. Calling it from inside a transformation's own options
%   dialog therefore hijacks the app's "Running <id>..." indicator and
%   points it at a window that is about to be destroyed -- after which
%   TransformSettings.set's own BusyGate('resume') finds an invalid figure
%   and silently restores nothing. The result is a 20-second source
%   computation with no indicator at all, which is exactly the moment one
%   is most wanted. Found the hard way.
%
%   So this uses uiprogressdlg directly on the dialog's own figure, leaving
%   the app's gate suspended and intact for InitGuard/TransformSettings to
%   hand back when the real work starts.
    dlg = uiprogressdlg(fig, 'Message', message, 'Indeterminate', 'on', ...
        'Cancelable', 'off');
    cleanup = onCleanup(@() delete(dlg));
    [varargout{1:nargout}] = fn();
end

function [names, counts] = regionsFor(sourcemodel, atlasName)
%REGIONSFOR  The regions this cortical sheet actually reaches, with how many
%   vertices each gets. Regions the sheet never touches (the cerebellum and
%   deep grey structures, which a cortical surface HAS no vertices in) are
%   left out rather than offered and then silently dropped later.
    [vertexLabel, allLabels] = TransTools.AtlasVertexLabels(sourcemodel, atlasName);
    counts = accumarray(vertexLabel(vertexLabel > 0), 1, [numel(allLabels), 1]);
    keep = counts > 0;
    names = allLabels(keep);
    counts = counts(keep);
    names = names(:)';
end

function items = displayItems(names, counts)
    items = arrayfun(@(k) sprintf('%s  (%d vertices)', names{k}, counts(k)), ...
        1:numel(names), 'UniformOutput', false);
end

function preselect(listBox, names, wanted)
    if isempty(wanted); return; end
    keep = ismember(lower(names), lower(cellstr(string(wanted))));
    listBox.Value = names(keep);
end

