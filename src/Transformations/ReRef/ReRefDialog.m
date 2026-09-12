function options = ReRefDialog(chanlocs, stored, elcFile)
%REREFDIALOG  Native editor for the ReRef transform: choose the reference the
%   data is re-referenced to, in the app's own dialog style (the same choices
%   pop_reref offers).
%
%   Reference is either the Average of the channels, or Specific channel(s)
%   (their mean). Channels can be excluded from the reference computation, and
%   the reference channel(s) optionally kept in the data. CHANLOCS is the
%   dataset's channels; STORED a previous run's options (or [] on first use);
%   ELCFILE the standard 10-5 template path (see TransTools.Template1005File),
%   offered as suggestions for the implicit-reference name below.
%
%   THE IMPLICIT REFERENCE. Some recordings are made against a reference
%   channel that was never itself saved (a single active electrode, e.g. Cz
%   or a mastoid, whose own voltage relative to itself is by definition
%   always zero, so nothing was ever recorded for it). Re-referencing to
%   something else is exactly the computation that recovers its true signal
%   -- see ReRef.m's addImplicitReferenceChannel -- so this dialog lets the
%   analyst name it: typed freely, or picked from the 10-5 template, since
%   that is commonly what an implicit reference actually is (Cz and the
%   mastoids are the usual candidates).
%
%   Returns the options struct (.mode, .refChannels, .exclude, .keepref,
%   .implicitRef -- '' when not reconstructing one), or [] on cancel.
    labels = arrayfun(@(c) char(string(c.labels)), chanlocs, 'UniformOutput', false);
    MODES = {'Average', 'Specific channels'};
    [accentColor, bgColor] = dialogChromeColors();
    options = [];

    seed = struct('mode', 'Average', 'refChannels', {{}}, 'exclude', {{}}, 'keepref', false, ...
        'implicitRef', '');
    seed = mergeSeedFields(seed, stored);

    fig = uifigure('Name', 'ReRef', 'Position', fitOnScreen([100 100 460 450]), 'Color', bgColor);
    root = uigridlayout(fig, [2 1], 'RowHeight', {40, '1x'}, 'Padding', [0 0 0 0], 'RowSpacing', 0);
    uilabel(root, 'Text', '  Re-reference', 'FontSize', 14, 'FontWeight', 'bold', ...
        'FontColor', [1 1 1], 'BackgroundColor', accentColor, 'VerticalAlignment', 'center');
    outer = uigridlayout(root, [6 1], 'RowHeight', {'fit', 'fit', '1x', 'fit', 'fit', 44}, ...
        'Padding', [10 10 10 10]);

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

    % IMPLICIT-REFERENCE ROW. Items are the 10-5 template's own labels, minus
    % whatever is already a channel in this dataset (picking an existing
    % channel's name would collide, not reconstruct anything); Editable
    % lets the analyst type a name the template does not carry at all (a lab
    % that calls its reference "REF" rather than by an electrode name).
    implicitGrid = uigridlayout(outer, [1 2], 'ColumnWidth', {'fit', '1x'}, 'Padding', [0 0 0 0], ...
        'ColumnSpacing', 8);
    implicitGrid.Layout.Row = 5;
    implicitBox = uicheckbox(implicitGrid, 'Text', 'Reconstruct implicit reference channel:', ...
        'Value', ~isempty(seed.implicitRef));
    implicitBox.ValueChangedFcn = @(~, ~) refreshImplicit();
    implicitDrop = uidropdown(implicitGrid, 'Items', implicitChoices(elcFile, labels), ...
        'Editable', 'on', 'Value', seed.implicitRef, ...
        'Tooltip', ['The name of the reference channel this recording was made against but ' ...
            'never saved (often Cz or a mastoid). Pick from the list or type any name.']);

    buttons = uigridlayout(outer, [1 3], 'ColumnWidth', {'1x', 90, 90}, 'Padding', [0 4 0 0]);
    buttons.Layout.Row = 6;
    uilabel(buttons, 'Text', '');
    uibutton(buttons, 'Text', 'Cancel', 'ButtonPushedFcn', @(~, ~) onCancel());
    uibutton(buttons, 'Text', 'OK', 'BackgroundColor', accentColor, ...
        'FontColor', [1 1 1], 'ButtonPushedFcn', @(~, ~) onOK());
    fig.CloseRequestFcn = @(~, ~) onCancel();

    refreshMode();
    refreshImplicit();
    uiwait(fig);

    function refreshMode()
        if strcmp(modeDrop.Value, 'Specific channels'); refList.Enable = 'on'; else; refList.Enable = 'off'; end
    end

    function refreshImplicit()
        if implicitBox.Value; implicitDrop.Enable = 'on'; else; implicitDrop.Enable = 'off'; end
    end

    function onOK()
        implicitRef = '';
        if implicitBox.Value
            implicitRef = strtrim(implicitDrop.Value);
            if isempty(implicitRef)
                uialert(fig, 'Would you name the implicit reference channel, or untick the box?', ...
                    'Check the implicit reference'); return;
            end
            if any(strcmpi(labels, implicitRef))
                uialert(fig, sprintf('"%s" is already a channel in this dataset.', implicitRef), ...
                    'Check the implicit reference'); return;
            end
        end

        out = struct('mode', modeDrop.Value, 'refChannels', {asCell(refList.Value)}, ...
            'exclude', {asCell(exclList.Value)}, 'keepref', logical(keepBox.Value), ...
            'implicitRef', implicitRef);
        if strcmp(out.mode, 'Specific channels') && isempty(out.refChannels)
            uialert(fig, 'Would you select at least one reference channel, or choose Average instead?', 'Check the reference'); return;
        end
        options = out;
        uiresume(fig); delete(fig);
    end

    function onCancel()
        uiresume(fig); delete(fig);
    end
end

% ======================================================================= %
function items = implicitChoices(elcFile, datasetLabels)
%IMPLICITCHOICES  The 10-5 template's own labels, minus whatever this
%   dataset already has. Best-effort: an unreadable template just leaves the
%   list empty rather than blocking the dialog -- typing a name always works.
    items = {};
    try
        template = readlocs(elcFile);
        items = unique({template.labels}, 'stable');
        items = items(~ismember(lower(items), lower(datasetLabels)));
    catch
    end
end

% intersectLabels/asCell (src/Support/) and mergeSeedFields (src/Support/)
% used to be duplicated locally here; see those files.
