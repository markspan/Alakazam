function deselectOtherTrees(this, keepTree)
%DESELECTOTHERTREES  Clear the visual selection on every WorkSpaceTree
%   except KEEPTREE, so only one of Data & Analyses / Grand Averages /
%   Reports ever shows a highlighted node at a time.
%
%   Before this, selecting a node in one tree left whatever was previously
%   selected in the OTHER trees still highlighted: the underlying "active"
%   dataset (Workspace.EEG / Workspace.ActiveTree) switched correctly, but
%   picking a Grand Average left a subject's raw dataset still lit up in
%   Data & Analyses above it -- reading as two things selected at once,
%   when a transformation run from the ribbon only ever acts on the one
%   that was actually picked. See loadAndPlotNode and syncActiveDataset,
%   the two places a tree's selection changes from MATLAB's side.
%
%   Setting SelectedNodes = [] here is a pure MATLAB -> JS push:
%   WorkSpaceTree's set.SelectedNodes only ever calls push(), it never
%   invokes SelectionChangedFcn (that only fires from the JS-side
%   'nodeClicked' bridge event, in WorkSpaceTree.onEvent) -- so clearing
%   the sibling trees here cannot recurse back into onSelectionChanged or
%   flip Workspace.ActiveTree a second time.
    for tree = [this.Workspace.Tree, this.Workspace.GrandAveragesTree, this.Workspace.ReportsTree]
        if tree ~= keepTree
            tree.SelectedNodes = [];
        end
    end
end
