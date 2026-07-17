function onSelectionChanged(this, eventData, sourceTree)
%ONSELECTIONCHANGED  Tree callback: load and plot the newly selected
%   dataset. SOURCETREE (see onNodeDropped) becomes Workspace.
%   ActiveTree, so later actions (rename/delete/run a
%   transformation) act on whichever of the two trees this
%   selection came from.
    this.Workspace.ActiveTree = sourceTree;
    EEG = this.loadNodeEEG(eventData.UserData, 'select this dataset');
    if isempty(EEG)
        return;
    end
    this.Workspace.EEG = EEG;
    this.Plotter.plotCurrent();
end
