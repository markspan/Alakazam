function [resultEEG, newNode] = persistResultNode(this, resultEEG, sourceFile, ~, transformId, parentTreeNode)
%PERSISTRESULTNODE  Save a transformation result and add it to the tree.
%   [RESULTEEG, NEWNODE] = PERSISTRESULTNODE(THIS, RESULTEEG, SOURCEFILE,
%   DISPLAYBASE, TRANSFORMID, PARENTTREENODE) performs the persistence
%   step shared by onTransformation and evaluateDroppedBranch. DISPLAYBASE
%   (the calling node's own label) is accepted but currently unused, since
%   the tree shows each node's own transform id rather than an
%   accumulated lineage string; kept as a parameter in case that changes:
%     * derive a timestamped cache file in a folder named after the
%       source dataset's own stem (sibling to SOURCEFILE), creating
%       that folder if needed;
%     * set RESULTEEG.File and RESULTEEG.id (just TRANSFORMID: the
%       tree shows each node's own transform, not its lineage);
%     * add a tree node under PARENTTREENODE with the matching icon,
%       expand its parent and select it;
%     * save RESULTEEG to disk and make it the workspace's current EEG.
%   Returns the updated dataset and the new tree node.
%
%   The child folder MUST be named after the source's own stem, not
%   the new node's key: treeTraverse (tree rebuild from disk) and
%   evaluateDroppedBranch (drag-drop recursion) both locate a node's
%   children this way, by re-deriving the same folder name from the
%   node's own file path rather than storing it anywhere.

    % Timestamped key, e.g. "Fourier051423". The DDhhMMss format is
    % kept for backwards compatibility with existing cache trees. The
    % key stays a char array because it is used to build a file name.
    nodeKey = [transformId datestr(datetime('now'), 'DDhhMMss')]; %#ok<DATST>

    % The result is cached in a folder named after the source dataset,
    % which is how the tree is later rebuilt from disk.
    [parentDir, parentName] = fileparts(sourceFile);
    childDir = fullfile(parentDir, parentName);
    if ~exist(childDir, "dir")
        mkdir(childDir);
    end

    resultEEG.File = fullfile(childDir, [nodeKey '.mat']);
    resultEEG.id   = transformId;

    % Add the node to the data browser and select it, in whichever
    % of the two trees (Tree / GrandAveragesTree) PARENTTREENODE
    % actually belongs to -- this.Workspace.ActiveTree, kept
    % current by CreateTreeComponent's callback wiring, so running
    % a transformation on a currently-selected grand average adds
    % its result under that node in GrandAveragesTree, not the
    % unrelated data & analyses tree. WorkSpaceTree nodes are
    % always shown expanded, so there is no separate "expand the
    % parent" step to do here. The icon is the transformation's own
    % (Transformations/<transformId>/*.json's Icon), scaled down
    % for the tree row -- see WorkSpaceTree.iconForResult.
    transRoot = fullfile(this.RootDir, 'Transformations');
    % 'Apply to All Raw Files' only makes sense for a branch living
    % in the Data & Analyses tree (a chain rooted in one raw
    % recording, replayable onto others) -- never for a node added
    % under a Grand Average (see this method's own header comment:
    % running a transformation on a selected grand average adds its
    % result into GrandAveragesTree instead). WorkSpaceTree.optsFor
    % cannot compute this itself, since it only sees the EEG, not
    % which tree it is headed for.
    opts = WorkSpaceTree.optsFor(resultEEG);
    opts.canApplyToAll = isequal(this.Workspace.ActiveTree, this.Workspace.Tree);
    newNode = this.Workspace.ActiveTree.addNode(resultEEG.id, parentTreeNode.Id, ...
        WorkSpaceTree.iconForResult(resultEEG, transRoot), resultEEG.File, opts);
    this.Workspace.ActiveTree.SelectedNodes = newNode;

    % Persist to disk (under the variable name "EEG", plus a JSON sidecar
    % -- see saveEegCache) and adopt it as the workspace's current dataset.
    saveEegCache(resultEEG.File, resultEEG);
    this.Workspace.EEG = resultEEG;
end
