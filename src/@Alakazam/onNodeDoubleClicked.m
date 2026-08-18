function onNodeDoubleClicked(this, eventData, sourceTree)
%ONNODEDOUBLECLICKED  Tree callback: (re)load and plot the double-clicked
%   dataset. Loads it itself rather than relying on a preceding single
%   click's SelectionChangedFcn having already done so, since
%   WorkSpaceTree does not guarantee that ordering. SOURCETREE: see
%   onNodeDropped. See loadAndPlotNode, shared with onSelectionChanged.
    this.loadAndPlotNode(eventData, sourceTree, 'open this dataset');
end
