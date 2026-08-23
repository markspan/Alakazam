function plan = planDescendantRecalc(this, parentFile, parentEEG)
%PLANDESCENDANTRECALC  Pure (no disk writes): recompute every node
%   below PARENTFILE against the just-recomputed PARENTEEG, using
%   each node's own already-recorded transform id and parameters
%   UNCHANGED (only the node the analyst actually edited gets new
%   parameters -- everything downstream just re-runs headlessly,
%   exactly like evaluateDroppedBranch's own replay). Returns a
%   flat struct array of (file, EEG) pairs in an order safe to
%   save() top-down (parents before children); throws without
%   writing anything if any step fails, so the caller can abandon
%   the whole recalculation cleanly rather than saving a
%   half-updated branch.
    plan = struct('file', {}, 'EEG', {});
    [parentDir, parentName] = fileparts(parentFile);
    childDir = fullfile(parentDir, parentName);
    if exist(childDir, "dir") ~= 7
        return; % leaf: nothing downstream
    end

    childFiles = dir(fullfile(childDir, '*.mat'));
    for i = 1:numel(childFiles)
        childFile = fullfile(childFiles(i).folder, childFiles(i).name);
        childLoaded = load(childFile, "EEG");
        childTransformId = char(string(childLoaded.EEG.Call));

        if exist(childTransformId, "file") ~= 2
            throw(MException('Alakazam:planDescendantRecalc', ...
                ['I''m afraid the stored transformation ''%s'' no longer exists (its .m ' ...
                 'file appears to be missing from the Transformations folder), so I am ' ...
                 'unable to recalculate "%s" and its descendants.'], ...
                childTransformId, char(string(childLoaded.EEG.id))));
        end

        [newChildEEG, ~] = feval(childTransformId, parentEEG, childLoaded.EEG.params);
        newChildEEG.Call   = childLoaded.EEG.Call;
        newChildEEG.params = childLoaded.EEG.params;
        newChildEEG.File   = childFile;
        newChildEEG.id     = childLoaded.EEG.id;

        plan(end + 1) = struct('file', childFile, 'EEG', newChildEEG); %#ok<AGROW>
        plan = [plan, this.planDescendantRecalc(childFile, newChildEEG)]; %#ok<AGROW>
    end
end
