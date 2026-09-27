function onOverlayErp(this)
%ONOVERLAYERP  Context-menu action: draw the right-clicked average on the
%   ERP plot in view.
%
%   The plot in view is the one keyboard shortcuts go to (activeTileTag): the
%   selected tab, or the tile last clicked. Right-clicking a node selects it
%   without plotting it (WorkSpaceTree's contextMenuAction), so that plot is
%   still the one the user was looking at.
%
%   ONLY ERPS. The menu item is offered for every averaged node, since the
%   tree decides from a small record that cannot tell an ERP from a scalp
%   map (see WorkSpaceTree.optsFor); whether the node really is drawn as
%   waveforms is AlakazamPlotter.viewClassFor's answer, asked here once the
%   node is loaded. Whether the two can share the axes is decided by channel
%   name and time (erpOverlayProblem), and every refusal says why.
%
%   See also ALAKAZAM.OVERLAYAVERAGE, AVERAGEVIEW, ERPOVERLAYPROBLEM.
    dialogTitle = 'Overlay on ERP plot';
    node = this.Workspace.ActiveTree.SelectedNodes;
    if isempty(node)
        return;
    end

    tab = findobj(this.PlotsTabGroup.Children, 'flat', 'Tag', this.activeTileTag());
    view = [];
    if ~isempty(tab)
        view = getappdata(tab(1), 'AverageView');
    end
    if isempty(view) || ~isvalid(view)
        uialert(this.MainFigure, ['Show an ERP first: select an averaged dataset so its ' ...
            'waveforms are in view, then right-click another average and choose ' ...
            'Overlay on ERP plot.'], dialogTitle, 'Icon', 'info');
        return;
    end
    if strcmp(node.UserData, tab(1).Tag)
        uialert(this.MainFigure, sprintf('"%s" is the plot''s own dataset.', node.Name), ...
            dialogTitle, 'Icon', 'info');
        return;
    end

    EEG = this.loadNodeEEG(node.UserData, 'overlay this dataset');
    if isempty(EEG)
        return;
    end
    EEG.File = node.UserData;
    if ~strcmp(AlakazamPlotter.viewClassFor(EEG), 'AverageView')
        uialert(this.MainFigure, sprintf(['"%s" is not drawn as ERP waveforms, so it cannot ' ...
            'be overlaid on them. Averages drawn as waveforms can.'], node.Name), ...
            dialogTitle, 'Icon', 'info');
        return;
    end

    view.setDatasetPath(tab(1).Tag, this.erpTreePath(tab(1).Tag));
    problem = view.addDataset(EEG, this.erpTreePath(node.UserData));
    if ~isempty(problem)
        uialert(this.MainFigure, sprintf('"%s" cannot be overlaid on this plot. %s', ...
            node.Name, problem), dialogTitle, 'Icon', 'warning');
    end
end
