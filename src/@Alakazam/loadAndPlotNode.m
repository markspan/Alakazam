function loadAndPlotNode(this, eventData, sourceTree, action)
%LOADANDPLOTNODE  Load and plot the dataset behind a tree node, setting
%   SOURCETREE as the active tree first (see onNodeDropped for what
%   SOURCETREE is). ACTION is loadNodeEEG's own action-description string
%   (used in its error message if the load fails, e.g. "select this
%   dataset" / "open this dataset").
%
%   Shared by onSelectionChanged and onNodeDoubleClicked, whose bodies
%   were previously byte-identical apart from that one ACTION string.
%
%   Also clears any selection the OTHER two trees are still showing (see
%   deselectOtherTrees), so picking a node in one tree -- most visibly, a
%   Grand Average -- does not leave an unrelated dataset looking selected
%   in a different tree above or below it.
    this.Workspace.ActiveTree = sourceTree;
    this.deselectOtherTrees(sourceTree);
    EEG = this.loadNodeEEG(eventData.UserData, action);
    if isempty(EEG)
        return;
    end
    this.Workspace.EEG = EEG;
    this.Plotter.plotCurrent();
end
