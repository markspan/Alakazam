function onApplyToAllRawFiles(this)
%ONAPPLYTOALLRAWFILES  Context-menu callback: re-apply the selected
%   branch (a chain of transformations already run on one raw
%   recording) onto every OTHER raw recording (root node) currently
%   in the Data & Analyses tree, in one action -- exactly what
%   dragging that branch onto each one individually would do (see
%   evaluateDroppedBranch), without doing it by hand once per
%   subject. Only ever reachable for a non-root node in
%   Workspace.Tree (the context menu item's own eligibility is
%   baked into the node at creation time, see persistResultNode,
%   exactly like List events/Recalculate); re-validated here too,
%   defence in depth for a .wksp saved before this feature existed.
%
%   The branch's own root (the raw file it was originally built on)
%   is excluded from the targets -- re-applying a branch to the very
%   recording it already came from would just clone it as a
%   redundant sibling of itself.
    node = this.Workspace.ActiveTree.SelectedNodes;
    if isempty(node) || node.IsRoot || ~isequal(this.Workspace.ActiveTree, this.Workspace.Tree)
        return;
    end

    sourceFile = node.UserData;
    sourceRoot = this.Workspace.Tree.rootOf(node.Id);

    targets = this.Workspace.Tree.allNodes();
    targets = targets([targets.IsRoot]);
    if ~isempty(sourceRoot)
        targets = targets(~strcmp({targets.Id}, sourceRoot.Id));
    end

    if isempty(targets)
        % LEGACY-JAVA-GUI: msgbox, see the note near onListEvents.
        msgbox(['There are no other raw files in this workspace to apply ' ...
            'this branch to.'], 'Nothing to apply to');
        return;
    end

    % LEGACY-JAVA-GUI: questdlg, see the note near onDeleteNode.
    answer = questdlg(sprintf( ...
        ['Apply "%s" (and everything below it) to all %d other raw ' ...
         'file(s) in this workspace?'], node.Name, numel(targets)), ...
        'Apply to All Raw Files', 'Apply', 'Cancel', 'Cancel');
    if ~strcmp(answer, 'Apply')
        return;
    end

    % Run from the repository root (historic behaviour): individual
    % plugins may resolve resources relative to it -- same as
    % onTransformation/onNodeDropped.
    originalDir = cd(this.RepoRoot);
    restoreDir  = onCleanup(@() cd(originalDir)); % restores cwd at method exit
    this.MainFigure.Pointer = "watch";
    restorePointer = onCleanup(@() set(this.MainFigure, "Pointer", "arrow"));

    % One target's failure (a genuine incompatibility, e.g. a
    % subject whose recording lacks a channel/event type this
    % branch's chain depends on) should not abort the whole batch --
    % every other target still gets the branch applied, and the
    % analyst sees exactly which ones did not at the end.
    failed = strings(1, 0); % row, not column -- cellstr(failed) below must
                             % concatenate horizontally with the other message lines
    for k = 1:numel(targets)
        try
            this.evaluateDroppedBranch(sourceFile, targets(k));
        catch ME
            failed(end + 1) = sprintf("%s: %s", targets(k).Name, ME.message); %#ok<AGROW>
        end
    end

    this.restoreFocus();
    succeeded = numel(targets) - numel(failed);
    if isempty(failed)
        % LEGACY-JAVA-GUI: msgbox, see the note near onListEvents.
        msgbox(sprintf('Applied "%s" to %d raw file(s).', node.Name, succeeded), ...
            'Apply to All Raw Files complete');
    else
        message = [{sprintf('Applied "%s" to %d of %d raw file(s). Failed on:', ...
            node.Name, succeeded, numel(targets))}, {''}, cellstr(failed)];
        uialert(this.MainFigure, message, 'Some raw files could not be updated', ...
            'Icon', 'warning');
    end
end
