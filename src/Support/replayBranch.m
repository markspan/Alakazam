function [nodes, errorMessage] = replayBranch(sourceFile, targetFile, transRoot, targetEEG)
%REPLAYBRANCH  Replay a cached branch of transformations onto another
%   dataset, writing each result's cache file, without the user interface.
%
%   [NODES, ERRORMESSAGE] = replayBranch(SOURCEFILE, TARGETFILE, TRANSROOT)
%   runs the transformation SOURCEFILE was made by, with its stored
%   parameters, on the dataset cached in TARGETFILE, saves the result where
%   Alakazam caches a child of TARGETFILE (resultCacheFile), and does the same
%   for everything below SOURCEFILE in its own cache tree, depth first: the
%   computation evaluateDroppedBranch does for a dragged branch. TRANSROOT is
%   the Transformations folder, for the node icons. TARGETEEG, when given, is
%   TARGETFILE's dataset already in memory.
%
%   NODES describes what was written, each parent before its children, for
%   the caller to add to the tree:
%     .File        the result's cache file
%     .ParentFile  its parent's cache file (TARGETFILE for the first)
%     .Label       the transformation id, which the tree shows
%     .Icon        WorkSpaceTree.iconForResult
%     .Opts        WorkSpaceTree.optsFor; canApplyToAll is left to the
%                  caller, which knows which tree the nodes go into
%
%   A failure stops the replay and comes back as ERRORMESSAGE ('' on
%   success), with NODES holding what was written before it, so the tree
%   can show the same partial branch the one-at-a-time replay leaves.
%
%   WHY IT EXISTS. It touches nothing but files, so it can run on a parallel
%   worker: Apply to All Raw Files hands one recording to each worker
%   (replayBranchOnTargets) and adds the nodes in the app as each finishes.
%   It leaves out the one thing evaluateDroppedBranch does that needs the
%   app, overlaying an averaged dataset onto another averaged one; callers
%   send those targets through evaluateDroppedBranch instead.
%
%   See also REPLAYBRANCHONTARGETS, EVALUATEDROPPEDBRANCH, RESULTCACHEFILE.
    if nargin < 4
        targetEEG = [];
    end
    nodes = struct('File', {}, 'ParentFile', {}, 'Label', {}, 'Icon', {}, 'Opts', {});
    errorMessage = '';
    try
        replayOne(sourceFile, targetFile, targetEEG);
    catch err
        errorMessage = err.message;
    end

    function replayOne(srcFile, parentFile, parentEEG)
        if isempty(parentEEG)
            if exist(parentFile, 'file') ~= 2
                throw(MException('Alakazam:replayBranch', ...
                    'I''m afraid the target dataset''s cache file could not be found:\n\n    %s', parentFile));
            end
            loaded = load(parentFile, 'EEG');
            parentEEG = loaded.EEG;
            clear loaded;
        end
        if exist(srcFile, 'file') ~= 2
            throw(MException('Alakazam:replayBranch', ...
                'I''m afraid the branch''s cache file could not be found:\n\n    %s', srcFile));
        end
        parentEEG.File = parentFile;

        meta = readEegCacheMeta(srcFile);
        transformId = char(meta.Call);
        if exist(transformId, 'file') ~= 2
            throw(MException('Alakazam:replayBranch', ...
                ['I''m sorry, but the stored transformation ''%s'' no longer appears to exist ' ...
                 '(its .m file seems to be missing from the Transformations folder), so I am ' ...
                 'unable to replay this branch.'], transformId));
        end
        [result, ~] = TransTools.invoke(transformId, parentEEG, meta.params);
        clear parentEEG;   % the children start from the result, not from here
        result.Call   = meta.Call;
        result.params = meta.params;
        result.File   = resultCacheFile(parentFile, transformId);
        result.id     = transformId;
        saveEegCache(result.File, result);
        nodes(end + 1) = struct('File', result.File, 'ParentFile', parentFile, ...
            'Label', transformId, 'Icon', WorkSpaceTree.iconForResult(result, transRoot), ...
            'Opts', WorkSpaceTree.optsFor(result));

        [srcDir, srcName] = fileparts(srcFile);
        childDir = fullfile(srcDir, srcName);
        if exist(childDir, 'dir')
            children = dir(fullfile(childDir, '*.mat'));
            for i = 1:numel(children)
                replayOne(fullfile(childDir, children(i).name), result.File, result);
            end
        end
    end
end
