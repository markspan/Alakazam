function loadAndPlotNode(this, eventData, sourceTree, action)
%LOADANDPLOTNODE  Load and plot the dataset behind a tree node, setting
%   SOURCETREE as the active tree first (see onNodeDropped for what
%   SOURCETREE is). ACTION is loadNodeEEG's own action-description string
%   (used in its error message if the load fails, e.g. "select this
%   dataset" / "open this dataset").
%
%   Shared by onSelectionChanged and onNodeDoubleClicked, whose bodies
%   were previously byte-identical apart from that one ACTION string.
    this.Workspace.ActiveTree = sourceTree;
    EEG = this.loadNodeEEG(eventData.UserData, action);
    if isempty(EEG)
        return;
    end
    this.Workspace.EEG = EEG;
    this.Plotter.plotCurrent();
end
