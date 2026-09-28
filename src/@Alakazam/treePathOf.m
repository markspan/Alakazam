function path = treePathOf(this, file)
%TREEPATHOF  Where the dataset in FILE sits in the workspace, as the labels
%   from its recording (or grand average) down to its own node; {} when no
%   tree holds it. Names an overlaid dataset (see AverageView, SignalView
%   and overlayNames). The Data & Analyses tree is searched first, then the
%   Grand Averages tree, since either can hold an average worth comparing.
%
%   See also ALAKAZAM.ONOVERLAY, ALAKAZAM.OVERLAYAVERAGE, WORKSPACETREE.PATHOF.
    path = {};
    for tree = {this.Workspace.Tree, this.Workspace.GrandAveragesTree}
        if isempty(tree{1}) || ~isvalid(tree{1})
            continue;
        end
        id = tree{1}.findByFile(file);
        if ~isempty(id)
            path = tree{1}.pathOf(id);
            return;
        end
    end
end
