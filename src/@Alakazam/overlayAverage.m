function overlayAverage(this, targetEEG, sourceEEG)
%OVERLAYAVERAGE  Overlay a dropped average dataset on the target's plot.
%   Ensures the target average is shown (reusing its tab if open),
%   then adds the source average to that tab's AverageView. Plots are
%   uitabs in PlotsTabGroup, found directly by their own Tag (see
%   AlakazamPlotter.plotCurrent).
%
%   The lines are named by where each dataset sits in the tree
%   (treePathOf), and when the two cannot share the axes (no channel or
%   time in common, see datasetOverlayProblem) the user is told why. The drop
%   is not turned into a replay instead: replaying Average onto an average
%   could only fail.
%
%   See also ALAKAZAM.ONOVERLAY, ALAKAZAM.ISOVERLAYABLEAVERAGE, AVERAGEVIEW.
    existingTab = findobj(this.PlotsTabGroup.Children, 'flat', 'Tag', targetEEG.File);
    if isempty(existingTab)
        this.Workspace.EEG = targetEEG;
        this.Plotter.plotCurrent();
        existingTab = findobj(this.PlotsTabGroup.Children, 'flat', 'Tag', targetEEG.File);
    else
        this.PlotsTabGroup.SelectedTab = existingTab(1);
    end
    if isempty(existingTab)
        return;
    end

    view = getappdata(existingTab(1), "AverageView");
    if ~isempty(view) && isvalid(view)
        view.setDatasetPath(targetEEG.File, this.treePathOf(targetEEG.File));
        problem = view.addDataset(sourceEEG, this.treePathOf(sourceEEG.File));
        if ~isempty(problem)
            uialert(this.MainFigure, sprintf('The dropped average cannot be overlaid on this plot. %s', ...
                problem), 'Overlay on ERP plot', 'Icon', 'warning');
        end
    end
end
