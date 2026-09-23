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
%
%   SEVERAL RECORDINGS AT ONCE. Each recording is replayed by replayBranch,
%   which only reads and writes cache files, so replayBranchOnTargets can
%   hand the recordings to parallel workers (Settings > Processing; how many
%   at once is applyToAllWorkers' call, set by free memory as much as by
%   cores). The nodes are added to the tree here, as each recording
%   finishes. With parallel processing off, or no Parallel Computing
%   Toolbox, the same replay runs here one recording at a time. The branch's
%   own node stays selected throughout, rather than each new node in turn.
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

    if ~confirmAction(this.MainFigure, sprintf( ...
            ['Apply "%s" (and everything below it) to all %d other raw ' ...
             'file(s) in this workspace?'], node.Name, numel(targets)), ...
            'Apply to All Raw Files', 'Apply', 'Cancel')
        return;
    end

    restoreDir = this.enterRepoRoot();

    % A determinate progress dialog here, not the generic indeterminate
    % beginBusy every other call site uses: unlike those (one atomic,
    % all-or-nothing operation each), this one already loops over a known
    % list of targets, so it can show real "N of M" progress -- genuinely
    % informative for a batch that can take a while, rather than a spinner
    % with no sense of how much is left.
    total = numel(targets);
    dlg = uiprogressdlg(this.MainFigure, "Title", "Alakazam", ...
        "Message", sprintf("Applying to %d raw file(s)...", total), ...
        "ShowPercentage", "on", "Value", 0);
    restoreBusy = onCleanup(@() close(dlg));

    % One target's failure (a genuine incompatibility, e.g. a
    % subject whose recording lacks a channel/event type this
    % branch's chain depends on) should not abort the whole batch --
    % every other target still gets the branch applied, and the
    % user sees exactly which ones did not at the end.
    failed = strings(1, 0); % row, not column -- cellstr(failed) below must
                             % concatenate horizontally with the other message lines
    done = 0;
    started = tic;

    % An averaged branch dropped on an averaged recording may be overlaid
    % rather than replayed, which needs the app, so those targets keep the
    % one-at-a-time evaluateDroppedBranch. Every other target is replayed by
    % replayBranch, which touches only files and so can run on a parallel
    % worker; the nodes are added here as each recording finishes.
    viaApp = false(1, total);
    sourceMeta = readEegCacheMeta(sourceFile);
    if strcmpi(sourceMeta.DataFormat, 'AVERAGED')
        for k = 1:total
            targetMeta = readEegCacheMeta(targets(k).UserData);
            viaApp(k) = strcmpi(targetMeta.DataFormat, 'AVERAGED');
        end
    end
    replayed = targets(~viaApp);
    nWorkers = applyToAllWorkers({replayed.UserData});
    canApplyToAll = isequal(this.Workspace.ActiveTree, this.Workspace.Tree);
    transRoot = fullfile(this.RootDir, 'Transformations');

    % The tree is redrawn once, when the batch ends, not once per node added:
    % each addNode used to send the whole tree to the page again, so a dozen
    % recordings of ten nodes each was over a hundred full redraws.
    releaseTree = this.Workspace.ActiveTree.beginBatch();   % released by delete below
    for k = find(viaApp)
        dlg.Message = sprintf("Applying to %s (%d of %d)...", targets(k).Name, done + 1, total);
        try
            this.evaluateDroppedBranch(sourceFile, targets(k));
        catch ME
            failed(end + 1) = sprintf("%s: %s", targets(k).Name, ME.message); %#ok<AGROW>
        end
        done = done + 1;
        dlg.Value = done / total;
    end
    if ~isempty(replayed)
        if nWorkers >= 2
            dlg.Message = sprintf("Applying to %d raw file(s), %d at a time (starting the workers the first time takes a little while)...", ...
                numel(replayed), nWorkers);
        end
        [~, usedWorkers] = replayBranchOnTargets(sourceFile, {replayed.UserData}, transRoot, ...
            nWorkers, @onReplayed, @onStarted);
    else
        usedWorkers = 1;
    end
    delete(releaseTree);   % not clear: this function has nested functions

    this.restoreFocus();
    succeeded = total - numel(failed);
    elapsed = toc(started);
    if usedWorkers >= 2
        how = sprintf(', up to %d at a time', usedWorkers);
    else
        how = '';
    end
    if isempty(failed)
        % LEGACY-JAVA-GUI: msgbox, see the note near onListEvents.
        msgbox(sprintf('Applied "%s" to %d raw file(s) in %s%s.', node.Name, succeeded, ...
            durationText(elapsed), how), 'Apply to All Raw Files complete');
    else
        message = [{sprintf('I''m sorry to report that "%s" was applied to only %d of %d raw file(s). It failed on:', ...
            node.Name, succeeded, numel(targets))}, {''}, cellstr(failed)];
        uialert(this.MainFigure, message, 'Some raw files could not be updated', ...
            'Icon', 'warning');
    end

    function onStarted(k)
    %ONSTARTED  Name the recording being processed, when there is one at a time.
        if nWorkers < 2
            dlg.Message = sprintf("Applying to %s (%d of %d)...", replayed(k).Name, done + 1, total);
        end
    end

    function onReplayed(k, result)
    %ONREPLAYED  Add one finished recording's nodes, even a partial branch, and
    %   record its failure if it stopped early.
        addReplayedNodes(this.Workspace.ActiveTree, result.nodes, replayed(k), canApplyToAll);
        if ~isempty(result.error)
            failed(end + 1) = sprintf("%s: %s", replayed(k).Name, result.error);
        end
        done = done + 1;
        dlg.Value = done / total;
        if nWorkers >= 2
            dlg.Message = sprintf("Applying to %d raw file(s), %d at a time: %d of %d done...", ...
                numel(replayed), nWorkers, done - nnz(viaApp), numel(replayed));
        end
    end
end

function txt = durationText(seconds)
%DURATIONTEXT  "42 s" or "3 min 5 s".
    if seconds < 60
        txt = sprintf('%.0f s', seconds);
    else
        txt = sprintf('%d min %.0f s', floor(seconds / 60), mod(seconds, 60));
    end
end
