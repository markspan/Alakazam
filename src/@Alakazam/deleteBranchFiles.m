function deleteBranchFiles(this, file)
%DELETEBRANCHFILES  Delete FILE and every descendant cache file beneath it
%   (a node's own child folder, named after its own stem -- see
%   persistResultNode), closing any open tab/tile for each one first so
%   nothing on screen outlives its own cache file. Mirrors onDeleteNode's
%   own inline version of the same cleanup; factored out here since
%   onClearOtherAnalyses needs to run it once per deleted branch, not just
%   once per user action.
%
%   Does not touch the tree itself -- callers still need their own
%   WorkSpaceTree.removeNode(id) afterwards (see onDeleteNode,
%   onClearOtherAnalyses).
    [folder, stem] = fileparts(file);
    childDir = fullfile(folder, stem);

    descendantFiles = {file};
    if exist(childDir, "dir")
        found = dir(fullfile(childDir, '**', '*.mat'));
        for k = 1:numel(found)
            descendantFiles{end + 1} = fullfile(found(k).folder, found(k).name); %#ok<AGROW>
        end
    end
    for k = 1:numel(descendantFiles)
        this.closeTab(descendantFiles{k});
    end

    if exist(file, "file")
        delete(file);
    end
    if exist(childDir, "dir")
        rmdir(childDir, "s");
    end
end
