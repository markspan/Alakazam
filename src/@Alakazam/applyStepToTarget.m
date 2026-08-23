function newNode = applyStepToTarget(this, transformId, params, targetNode)
%APPLYSTEPTOTARGET  Replay one recorded transformation step
%   (TRANSFORMID, PARAMS) onto TARGETNODE, persisting the result as
%   a new child node and returning it (so a caller can chain
%   further steps onto it in turn -- see onApplyTemplate). Used
%   only by onApplyTemplate: evaluateDroppedBranch has its own,
%   data-dependent overlay special case (see isOverlayableAverage)
%   that a template -- a recipe of (transformId, params) pairs with
%   no live source EEG to compare shapes against -- cannot
%   participate in, so this is a deliberately separate, simpler
%   apply-one-step primitive rather than a shared one.
    targetFile = targetNode.UserData;
    if exist(targetFile, "file") ~= 2
        throw(MException('Alakazam:applyStepToTarget', ...
            'I''m afraid the target dataset''s cache file could not be found:\n\n    %s', targetFile));
    end
    if exist(transformId, "file") ~= 2
        throw(MException('Alakazam:applyStepToTarget', ...
            ['I''m sorry, but the stored transformation ''%s'' no longer appears to exist (its ' ...
             '.m file seems to be missing from the Transformations folder), so I am unable to ' ...
             'apply this step.'], transformId));
    end

    targetLoaded = load(targetFile, "EEG");
    targetEEG = targetLoaded.EEG;
    targetEEG.File = targetFile; % see loadNodeEEG's own note on why this wins over the stored field

    [result.EEG, ~] = feval(transformId, targetEEG, params);
    result.EEG.Call   = transformId;
    result.EEG.params = params;

    [~, newNode] = this.persistResultNode(result.EEG, targetFile, '', transformId, targetNode);
end
