function [removed, ok] = RemoveComponentsDialog(icl, icawinv, chanlocs)
%REMOVECOMPONENTSDIALOG  Alakazam-styled manual ICA component selector.
%
%   Shows every independent component in a table with its ICLabel class
%   probabilities and a "Remove" tick-box, alongside a live scalp-topography
%   preview of the currently selected component, so the analyst can inspect
%   and remove components by hand (the manual counterpart of AutoEyeICA's
%   automatic eye pruning). This is the EEGLAB pop_selectcomps / pop_subcomp
%   workflow, restyled to the app.
%
%   ICL is EEG.etc.ic_classification.ICLabel (fields .classes 1xC cellstr and
%   .classifications ncomp x C). ICAWINV is the component scalp-projection
%   matrix (nchan x ncomp) and CHANLOCS the channels it is indexed over
%   (EEG.chanlocs(EEG.icachansind)). Returns REMOVED, a row vector of the
%   component indices to subtract (possibly empty), and OK = true when the
%   analyst confirmed, or REMOVED = [] and OK = false on cancel.
    accentColor = [0.290 0.498 0.788];
    bgColor     = [0.9608 0.9608 0.9608];
    removed = [];
    ok = false;

    classes = icl.classes(:)';
    probs   = icl.classifications;
    ncomp   = size(probs, 1);

    fig = uifigure('Name', 'Remove ICA components', 'Position', [100 100 860 540], 'Color', bgColor);
    root = uigridlayout(fig, [2 1], 'RowHeight', {40, '1x'}, 'Padding', [0 0 0 0], 'RowSpacing', 0);
    uilabel(root, 'Text', '  Remove ICA components', 'FontSize', 14, 'FontWeight', 'bold', ...
        'FontColor', [1 1 1], 'BackgroundColor', accentColor, 'VerticalAlignment', 'center');
    outer = uigridlayout(root, [3 1], 'RowHeight', {'fit', '1x', 44}, 'Padding', [10 10 10 10]);

    uilabel(outer, 'Text', ['Tick the components to subtract from the data. Select a row to preview ' ...
        'its scalp topography. ICLabel probabilities (%) are shown to help identify artefact ' ...
        'components (eye, muscle, heart, line/channel noise).'], 'WordWrap', 'on');

    middle = uigridlayout(outer, [1 2], 'ColumnWidth', {'1x', 300}, 'Padding', [0 0 0 0], 'ColumnSpacing', 10);
    middle.Layout.Row = 2;

    colNames = [{'IC'}, classes, {'Remove'}];
    colFmt   = [{'numeric'}, repmat({'numeric'}, 1, numel(classes)), {'logical'}];
    colEdit  = [false, false(1, numel(classes)), true];
    data = cell(ncomp, numel(colNames));
    for c = 1:ncomp
        data{c, 1} = c;
        for k = 1:numel(classes)
            data{c, 1 + k} = round(probs(c, k) * 100);
        end
        data{c, end} = false;
    end
    tbl = uitable(middle, 'ColumnName', colNames, 'ColumnFormat', colFmt, ...
        'ColumnEditable', colEdit, 'Data', data, 'RowName', {}, ...
        'CellSelectionCallback', @(~, ev) onSelect(ev));

    ax = uiaxes(middle);
    ax.Color = bgColor; title(ax, 'Component topography');
    axis(ax, 'off');

    buttons = uigridlayout(outer, [1 3], 'ColumnWidth', {'1x', 90, 90}, 'Padding', [0 4 0 0], 'ColumnSpacing', 6);
    buttons.Layout.Row = 3;
    uilabel(buttons, 'Text', '');
    uibutton(buttons, 'Text', 'Cancel', 'ButtonPushedFcn', @(~, ~) onCancel());
    uibutton(buttons, 'Text', 'OK', 'BackgroundColor', accentColor, 'FontColor', [1 1 1], ...
        'ButtonPushedFcn', @(~, ~) onOK());
    fig.CloseRequestFcn = @(~, ~) onCancel();

    if ncomp >= 1
        drawComponent(1);
    end

    uiwait(fig);

    function onSelect(ev)
        if isempty(ev.Indices); return; end
        drawComponent(ev.Indices(1, 1));
    end

    function drawComponent(ic)
        if ic < 1 || ic > ncomp; return; end
        try
            vals = icawinv(:, ic);
            lim  = max(abs(vals));
            if lim == 0 || isnan(lim); lim = 1; end
            TransTools.DrawScalpMap(ax, vals, chanlocs, lim);
            [~, top] = max(probs(ic, :));
            title(ax, sprintf('IC %d -- %s (%.0f%%)', ic, classes{top}, probs(ic, top) * 100));
        catch err
            cla(ax); axis(ax, 'off');
            title(ax, sprintf('IC %d (no topography: %s)', ic, err.message));
        end
    end

    function onOK()
        d = tbl.Data;
        flags = false(ncomp, 1);
        for r = 1:ncomp
            v = d{r, end};
            flags(r) = ~isempty(v) && islogical(v) && v;
        end
        removed = find(flags(:))';
        ok = true;
        uiresume(fig); delete(fig);
    end

    function onCancel()
        removed = [];
        ok = false;
        uiresume(fig); delete(fig);
    end
end
