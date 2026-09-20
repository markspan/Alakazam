function [newNode, resultEEG] = applyStepToTarget(this, transformId, params, targetNode, targetEEG)
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
%
%   TARGETEEG (optional) is the dataset TARGETNODE holds, when the caller
%   already has it in memory: a template's steps then pass each result to the
%   next instead of every step reading back the file the one before it had
%   just written. RESULTEEG, the second output, is what to pass on.
    targetFile = targetNode.UserData;
    inMemory = nargin >= 5 && ~isempty(targetEEG);
    if ~inMemory && exist(targetFile, "file") ~= 2
        throw(MException('Alakazam:applyStepToTarget', ...
            'I''m afraid the target dataset''s cache file could not be found:\n\n    %s', targetFile));
    end
    if exist(transformId, "file") ~= 2
        throw(MException('Alakazam:applyStepToTarget', ...
            ['I''m sorry, but the stored transformation ''%s'' no longer appears to exist (its ' ...
             '.m file seems to be missing from the Transformations folder), so I am unable to ' ...
             'apply this step.'], transformId));
    end

    if ~inMemory
        targetLoaded = load(targetFile, "EEG");
        targetEEG = targetLoaded.EEG;
        clear targetLoaded;
    end
    targetEEG.File = targetFile; % see loadNodeEEG's own note on why this wins over the stored field

    [result.EEG, ~] = TransTools.invoke(transformId, targetEEG, params);
    result.EEG.Call   = transformId;
    result.EEG.params = params;

    [resultEEG, newNode] = this.persistResultNode(result.EEG, targetFile, '', transformId, targetNode);
end
