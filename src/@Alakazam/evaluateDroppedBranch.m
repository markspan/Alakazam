function evaluateDroppedBranch(this, sourceFile, targetNode)
%EVALUATEDROPPEDBRANCH  Re-apply a dragged branch onto a target dataset.
%   EVALUATEDROPPEDBRANCH(THIS, SOURCEFILE, TARGETNODE) walks the branch
%   rooted at SOURCEFILE and re-applies each stored transformation onto
%   the dataset at TARGETNODE, chaining down the tree while the source
%   branch has children.
%
%   Special case: dropping one AVERAGED dataset onto a matching AVERAGED
%   dataset overlays their plots instead of transforming -- isOverlayableAverage's
%   own job to recognise (see its header comment for why that is a source-side
%   .Call check, not a step-position one: it needs to reject Measure et al
%   reached either as the user's own direct drop or by descending into a
%   branch's children).
    atLeaf     = false;
    targetFile = targetNode.UserData;

    while ~atLeaf
        % Both files are stored tree-node paths, not something
        % just derived from code on disk -- a node can outlive its
        % file (cache cleared by hand, a workspace copied from
        % another machine, a branch deleted outside the app), so
        % this is checked explicitly rather than letting load()
        % throw a raw "Unable to find file" straight through
        % onNodeDropped's own try/catch.
        if exist(targetFile, "file") ~= 2
            throw(MException('Alakazam:evaluateDroppedBranch', ...
                'The target dataset''s cache file is missing:\n\n    %s', targetFile));
        end
        if exist(sourceFile, "file") ~= 2
            throw(MException('Alakazam:evaluateDroppedBranch', ...
                'The dragged branch''s cache file is missing:\n\n    %s', sourceFile));
        end
        targetStruct = load(targetFile, "EEG");
        sourceStruct = load(sourceFile, "EEG");
        % TARGETFILE/SOURCEFILE (just verified to exist, above)
        % always win over whatever EEG.File already is -- see
        % Alakazam.loadNodeEEG's own note on why the stored field
        % can be stale (a different machine/username).
        targetStruct.EEG.File = targetFile;
        sourceStruct.EEG.File = sourceFile;

        % Call is just the transformation id (see onTransformation); no
        % parsing needed.
        transformId = char(sourceStruct.EEG.Call);

        if this.isOverlayableAverage(targetStruct.EEG, sourceStruct.EEG)
            % Overlay the dropped average on top of the target average.
            this.overlayAverage(targetStruct.EEG, sourceStruct.EEG);
            atLeaf = true;
        else
            % General case: re-apply the stored transformation to the
            % target, carrying over the source's call and parameters.
            % The id is stored data (loaded from a .mat file that may
            % predate a Transformations-folder cleanup), not something
            % just derived from code on disk, so it's validated before
            % feval rather than failing with a cryptic "undefined
            % function" error.
            if exist(transformId, "file") ~= 2
                throw(MException('Alakazam:evaluateDroppedBranch', ...
                    ['Stored transformation ''%s'' no longer exists ' ...
                     '(its .m file is missing from the Transformations ' ...
                     'folder). Cannot replay this branch.'], transformId));
            end
            [result.EEG, ~] = feval(transformId, targetStruct.EEG, sourceStruct.EEG.params);
            result.EEG.Call   = sourceStruct.EEG.Call;
            result.EEG.params = sourceStruct.EEG.params;

            [result.EEG, newNode] = this.persistResultNode(result.EEG, ...
                targetStruct.EEG.File, sourceStruct.EEG.id, transformId, targetNode);

            % Descend: if the source has a child dataset, continue the
            % chain with it against the newly created node.
            [srcDir, srcName] = fileparts(sourceFile);
            childDir = fullfile(srcDir, srcName);
            if exist(childDir, "dir")
                targetNode = newNode;
                targetFile = result.EEG.File;
                childMat   = dir(fullfile(childDir, '*.mat'));
                sourceFile = fullfile(childDir, childMat.name);
            else
                atLeaf = true;
            end
        end
    end
end
