function onOverlay(this)
%ONOVERLAY  Context-menu action: draw the right-clicked dataset on the plot
%   in view, to compare the two.
%
%   The plot in view is the one keyboard shortcuts go to (activeTileTag): the
%   selected tab, or the tile last clicked. Right-clicking a node selects it
%   without plotting it (the tree only clicks on the left button), so that
%   plot is still the one the user was looking at.
%
%   THREE KINDS OF PLOT. On an ERP plot (AverageView) the node must be drawn
%   as ERP waveforms too; on a spectrum (FourierView) it must be a spectrum;
%   on a continuous recording (SignalView) it must be a continuous
%   time-domain recording. The menu item is offered for every averaged or
%   continuous node, since the tree decides from a small record (see
%   WorkSpaceTree.optsFor); which kind the node really is is asked here,
%   once it is loaded (AlakazamPlotter.viewClassFor). Whether the two can
%   share the axes is decided by the view (addDataset): by channel name and
%   time or frequency (datasetOverlayProblem), and for spectra by unit and
%   by not being single trials. Every refusal says why.
%
%   See also ALAKAZAM.OVERLAYAVERAGE, AVERAGEVIEW, FOURIERVIEW, SIGNALVIEW,
%   DATASETOVERLAYPROBLEM.
    dialogTitle = 'Overlay on plot';
    node = this.Workspace.ActiveTree.SelectedNodes;
    if isempty(node)
        return;
    end

    tab = findobj(this.PlotsTabGroup.Children, 'flat', 'Tag', this.activeTileTag());
    view = [];
    kind = '';
    if ~isempty(tab)
        for candidate = {'AverageView', 'FourierView', 'SignalView'}
            found = getappdata(tab(1), candidate{1});
            if ~isempty(found) && isvalid(found)
                view = found;
                kind = candidate{1};
                break;
            end
        end
    end
    if isempty(view)
        uialert(this.MainFigure, ['Show an ERP, a spectrum or a continuous recording first: ' ...
            'select it so its plot is in view, then right-click another dataset of the same ' ...
            'kind and choose Overlay on plot.'], dialogTitle, 'Icon', 'info');
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
    if strcmp(kind, 'AverageView')
        fits = strcmp(AlakazamPlotter.viewClassFor(EEG), 'AverageView');
        what = 'ERP waveforms';
    elseif strcmp(kind, 'FourierView')
        fits = strcmp(AlakazamPlotter.viewClassFor(EEG), 'FourierView');
        what = 'a spectrum';
    else
        fits = strcmpi(TransTools.FieldOr(EEG, 'DataFormat', ''), 'CONTINUOUS') ...
            && strcmpi(TransTools.FieldOr(EEG, 'DataType', ''), 'TIMEDOMAIN');
        what = 'a continuous recording';
    end
    if ~fits
        uialert(this.MainFigure, sprintf(['"%s" is not %s, so it cannot be overlaid on this ' ...
            'plot, which is.'], node.Name, what), dialogTitle, 'Icon', 'info');
        return;
    end

    view.setDatasetPath(tab(1).Tag, this.treePathOf(tab(1).Tag));
    problem = view.addDataset(EEG, this.treePathOf(node.UserData));
    if ~isempty(problem)
        uialert(this.MainFigure, sprintf('"%s" cannot be overlaid on this plot. %s', ...
            node.Name, problem), dialogTitle, 'Icon', 'warning');
    end
end
