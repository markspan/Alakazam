function addReplayedNodes(tree, nodes, targetNode, canApplyToAll)
%ADDREPLAYEDNODES  Put what replayBranch wrote into TREE under TARGETNODE:
%   each node under the one made from its parent file (the first under the
%   target itself), in the order written, parents first. CANAPPLYTOALL is
%   the flag persistResultNode would set: true in the Data & Analyses tree.
%
%   The app side of Apply to All Raw Files: the replay can run on a parallel
%   worker, but the tree lives in the app.
%
%   See also REPLAYBRANCH, ONAPPLYTOALLRAWFILES.
    idOf = containers.Map({char(targetNode.UserData)}, {targetNode.Id});
    for i = 1:numel(nodes)
        opts = nodes(i).Opts;
        opts.canApplyToAll = canApplyToAll;
        added = tree.addNode(nodes(i).Label, idOf(char(nodes(i).ParentFile)), ...
            nodes(i).Icon, nodes(i).File, opts);
        idOf(char(nodes(i).File)) = added.Id;
    end
end
