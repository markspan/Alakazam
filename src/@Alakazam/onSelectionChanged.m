function onSelectionChanged(this, eventData, sourceTree)
%ONSELECTIONCHANGED  Tree callback: load and plot the newly selected
%   dataset. SOURCETREE (see onNodeDropped) becomes Workspace.
%   ActiveTree, so later actions (rename/delete/run a
%   transformation) act on whichever of the two trees this
%   selection came from. See loadAndPlotNode, shared with
%   onNodeDoubleClicked.
    this.loadAndPlotNode(eventData, sourceTree, 'select this dataset');
end
