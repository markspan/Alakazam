function onSelectionChanged(this, eventData, sourceTree)
%ONSELECTIONCHANGED  Tree callback: load and plot the newly selected
%   dataset. SOURCETREE (see onNodeDropped) becomes Workspace.
%   ActiveTree, so later actions (rename/delete/run a
%   transformation) act on whichever of the three trees this
%   selection came from -- and the other two trees' own selection is
%   cleared, so only SOURCETREE shows a highlighted node. See
%   loadAndPlotNode (shared with onNodeDoubleClicked) and, for the
%   deselection, Alakazam.deselectOtherTrees.
    this.loadAndPlotNode(eventData, sourceTree, 'select this dataset');
end
