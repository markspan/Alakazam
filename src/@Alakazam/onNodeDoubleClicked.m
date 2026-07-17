function onNodeDoubleClicked(this, eventData, sourceTree)
%ONNODEDOUBLECLICKED  Tree callback: (re)load and plot the double-clicked
%   dataset. Loads it itself rather than relying on a preceding single
%   click's SelectionChangedFcn having already done so, since
%   WorkSpaceTree does not guarantee that ordering. SOURCETREE: see
%   onNodeDropped.
    this.Workspace.ActiveTree = sourceTree;
    EEG = this.loadNodeEEG(eventData.UserData, 'open this dataset');
    if isempty(EEG)
        return;
    end
    this.Workspace.EEG = EEG;
    this.Plotter.plotCurrent();
end
