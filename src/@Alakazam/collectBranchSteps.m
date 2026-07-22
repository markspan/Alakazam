function steps = collectBranchSteps(~, sourceFile)
%COLLECTBRANCHSTEPS  Walk the branch rooted at SOURCEFILE (a node's
%   own cache file) down through its single-chain descendants,
%   collecting each step's (transformId, params) in order --
%   SOURCEFILE's own step first. Pure (no disk writes, no dependence
%   on the tree/UI): used by onSaveTemplate to turn a live branch
%   into a portable template file.
%
%   Same child-folder convention as persistResultNode/
%   evaluateDroppedBranch (a node's descendants live in a folder
%   named after its own file stem, sibling to it). A branch that
%   forks (more than one child under some node) only follows the
%   first child found -- matching evaluateDroppedBranch's own
%   existing single-chain assumption; dragging a forked branch is
%   not really supported today either.
    steps = struct('transformId', {}, 'params', {});
    file = sourceFile;
    atLeaf = false;
    while ~atLeaf
        if exist(file, "file") ~= 2
            throw(MException('Alakazam:collectBranchSteps', ...
                'A step''s cache file is missing:\n\n    %s', file));
        end
        loaded = load(file, "EEG");
        steps(end + 1) = struct('transformId', char(string(loaded.EEG.Call)), ...
            'params', loaded.EEG.params); %#ok<AGROW>

        [dirPart, namePart] = fileparts(file);
        childDir = fullfile(dirPart, namePart);
        if exist(childDir, "dir")
            childMat = dir(fullfile(childDir, '*.mat'));
            file = fullfile(childDir, childMat(1).name);
        else
            atLeaf = true;
        end
    end
end