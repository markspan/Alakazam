function recalculateTransformNode(this, node, ownEEG)
%RECALCULATETRANSFORMNODE  Reopen NODE's own transformation with an
%   editor pre-filled from its stored parameters (OWNEEG.params);
%   if the analyst leaves them unchanged, or cancels, nothing
%   happens. If they change them, NODE and every one of its
%   descendants are recomputed and overwritten IN PLACE (same node
%   ids, same files -- unlike a branch drag-drop, which always
%   creates new sibling nodes via persistResultNode): the whole
%   point of "recalculate" is revising a branch, not duplicating
%   it. Only ever reachable for a node whose Call is one of
%   WorkSpaceTree.RecalculableTransforms (see optsFor); still
%   re-validated here (defence in depth -- a .wksp saved before
%   this feature existed, or before a Transformations folder
%   cleanup, could otherwise reach here with a stale/foreign Call).
    transformId = char(string(ownEEG.Call));
    if isempty(transformId) ...
            || ~any(strcmp(transformId, WorkSpaceTree.RecalculableTransforms)) ...
            || exist(transformId, "file") ~= 2
        uialert(this.MainFigure, sprintf( ...
            ['"%s" cannot be recalculated with edited parameters -- ' ...
             'either it has no editable options, or its transformation ' ...
             'file is missing.'], transformId), 'Cannot recalculate', 'Icon', 'warning');
        return;
    end

    parentFile = this.Workspace.ActiveTree.parentFile(node.Id);
    if isempty(parentFile) || exist(parentFile, "file") ~= 2
        uialert(this.MainFigure, ...
            'This node''s input dataset could not be found -- cannot recalculate.', ...
            'Cannot recalculate', 'Icon', 'warning');
        return;
    end

    % Seed transformId's own dialog with THIS node's stored
    % parameters -- not the workspace's usual "last used" value,
    % since editing a specific node should show that node's own
    % values -- by temporarily standing in for TransformSettings
    % (every RecalculableTransforms member reads its interactive
    % seed from there; see e.g. Baseline.m's 'Init' branch), then
    % restoring whatever was there before on exit so unrelated
    % future runs of this transform are unaffected by having
    % edited an older node.
    previousStored = TransformSettings.get(transformId);
    TransformSettings.set(transformId, ownEEG.params);
    restoreStored = onCleanup(@() TransformSettings.set(transformId, previousStored));

    restoreDir = this.enterRepoRoot();
    restoreBusy = beginBusy(this.MainFigure, sprintf("Recalculating %s...", transformId));

    parentLoaded = load(parentFile, "EEG");
    try
        [newEEG, newParams] = feval(transformId, parentLoaded.EEG);
    catch ME
        this.restoreFocus();
        this.showTransformationError(transformId, ME);
        return;
    end

    if isempty(newEEG) || ishandle(newEEG)
        % Cancelled (or a pure-plot transform -- shouldn't occur
        % for anything in RecalculableTransforms, but stay
        % consistent with onTransformation's own handling).
        this.restoreFocus();
        return;
    end
    if ~isstruct(newParams)
        newParams = struct('Param', newParams);
    end
    if isequal(newParams, ownEEG.params)
        % Nothing actually changed -- don't touch disk, don't
        % close any open tab, don't recompute descendants for no
        % reason.
        this.restoreFocus();
        return;
    end

    newEEG.Call   = transformId;
    newEEG.params = newParams;
    newEEG.File   = node.UserData; % keep this node's own identity/path
    newEEG.id     = transformId;

    % Compute the whole downstream branch in memory FIRST -- only
    % once every descendant recomputes cleanly are any files
    % actually overwritten, so a failure partway down never
    % leaves the branch half-updated (some nodes reflecting the
    % new parameters, others still stale).
    try
        plan = [struct('file', node.UserData, 'EEG', newEEG), ...
            this.planDescendantRecalc(node.UserData, newEEG)];
    catch ME
        this.restoreFocus();
        this.showTransformationError(transformId, ME);
        return;
    end

    for i = 1:numel(plan)
        EEG = plan(i).EEG; % saved to disk under the variable name "EEG"
        save(plan(i).file, "EEG");
        % A currently open tab/tile for this file would otherwise
        % keep showing its pre-edit content (plotCurrent reuses an
        % already-open tab rather than rebuilding it) -- closing
        % it means reselecting the node shows the fresh result,
        % never a stale one.
        this.closeTab(plan(i).file);
    end

    % A Grand Average built from a node in this branch keeps
    % pointing at whatever that node's file contained when it was
    % built (saveGrandAverage freezes absolute source paths) --
    % without this, it would silently go stale the moment any of
    % its sources got overwritten above, with no indication
    % anything changed. Runs before Workspace.EEG is reset to
    % NEWEEG below: refreshing a Grand Average adopts it as the
    % current dataset in its own right (see saveGrandAverage), so
    % the edited node needs to be re-asserted as current last.
    this.recalculateAffectedGrandAverages({plan.file});

    this.Workspace.EEG = newEEG;
    this.Plotter.plotCurrent();
    this.restoreFocus();
end
