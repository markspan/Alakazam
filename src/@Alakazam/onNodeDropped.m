function onNodeDropped(this, eventData, sourceTree)
%ONNODEDROPPED  Tree callback: handle a node dropped onto another node.
%   SOURCETREE is whichever of Workspace.Tree/GrandAveragesTree
%   raised the event (see WorkSpace.CreateTreeComponent); recorded
%   as Workspace.ActiveTree so evaluateDroppedBranch's
%   persistResultNode call below adds the new node to the same
%   tree the drop happened in. There is no move/reparent gesture in
%   this tree (WorkSpaceTree/src/webtree always revert the visual
%   move before this fires); every drop re-applies the dragged
%   branch onto the target via evaluateDroppedBranch. Root nodes
%   and drops onto empty space (no target dataset) are ignored.
    this.Workspace.ActiveTree = sourceTree;

    % Guaranteed to run when this callback returns, by any path
    % (a real transformation applied, an ignored root/empty-target
    % drop, or an error unwinding out of evaluateDroppedBranch):
    % the JS side sets a busy/wait cursor the instant it sends
    % nodeDropped (see src/webtree/src/alakazam-tree.js's _onMove)
    % and only clears it once it hears back -- without this, an
    % ignored drop or a failed transformation would leave it stuck.
    notifyDone = onCleanup(@() sourceTree.notifyDropHandled());

    restoreDir = this.enterRepoRoot();

    if eventData.Source.IsRoot
        return; % a root node was dropped; ignore
    end
    if isempty(eventData.Target)
        return; % dropped onto empty space/root; no target dataset
    end

    try
        this.evaluateDroppedBranch(eventData.Source.UserData, eventData.Target);
    catch ME
        % Without this, any failure here (a missing cache file, a
        % transformation whose .m file is gone, or a genuine
        % incompatibility mid-replay) would propagate uncaught
        % straight through the uihtml event bridge as a raw stack
        % trace -- this callback is the top of that chain, same as
        % onTransformation's own try/catch is for a ribbon-run
        % transformation.
        uialert(this.MainFigure, sprintf( ...
            'I wasn''t able to apply the dropped branch to this dataset:\n\n%s', ME.message), ...
            'Could not apply branch', 'Icon', 'warning');
    end
end
