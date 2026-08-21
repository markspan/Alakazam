function overlayAverage(this, targetEEG, sourceEEG)
%OVERLAYAVERAGE  Overlay a dropped average dataset on the target's plot.
%   Ensures the target average is shown (reusing its tab if open),
%   then adds the source average to that tab's AverageView. Plots are
%   uitabs in PlotsTabGroup, found directly by their own Tag (see
%   AlakazamPlotter.plotCurrent).
    existingTab = findobj(this.PlotsTabGroup.Children, 'flat', 'Tag', targetEEG.File);
    if isempty(existingTab)
        this.Workspace.EEG = targetEEG;
        this.Plotter.plotCurrent();
        existingTab = findobj(this.PlotsTabGroup.Children, 'flat', 'Tag', targetEEG.File);
    else
        this.PlotsTabGroup.SelectedTab = existingTab(1);
    end

    view = getappdata(existingTab(1), "AverageView");
    if ~isempty(view) && isvalid(view)
        view.addDataset(sourceEEG);
    end
end
