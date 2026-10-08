function [nodes, files] = collectBranchTree(~, sourceFile)
%COLLECTBRANCHTREE  Walk the whole branch rooted at SOURCEFILE (a node's own
%   cache file), collecting every node -- SOURCEFILE's own step and ALL of its
%   descendants, following every fork, not just the first child. Returns a flat
%   struct array of (transformId, params, parent) in depth-first order, where
%   PARENT is the 1-based index (into this same array) of a node's parent, or
%   -1 for the root (SOURCEFILE itself). Because a parent is always appended
%   before its children, parent < child for every node, so the list can be
%   replayed top-down and reconstructs the exact tree (see onApplyTemplate).
%
%   This flat parent-index form (rather than a nested struct) is deliberate:
%   it preserves the branching structure a template must reproduce, yet
%   survives jsonencode/jsondecode without the nested-object ambiguities that
%   a recursive struct would hit. Pure (no disk writes, no tree/UI
%   dependence): used by onSaveTemplate to turn a live branch into a portable
%   template file. Same child-folder convention as persistResultNode /
%   planDescendantRecalc (a node's descendants live in a folder named after
%   its own file stem, sibling to it).
%
%   [NODES, FILES] = collectBranchTree(...) also returns each node's own
%   cache file, a cellstr beside NODES, for an export that reads results
%   as well as settings (onExportFieldTripScript). They are kept out of
%   NODES itself, which a template and the script export compare and
%   store, and where a path would only get in the way.
    nodes = struct('transformId', {}, 'params', {}, 'parent', {});
    files = {};
    [nodes, files] = appendBranch(nodes, files, sourceFile, -1);
end

function [nodes, files] = appendBranch(nodes, files, file, parentIdx)
%APPENDBRANCH  Append FILE's node (with parent PARENTIDX) to NODES, then
%   recurse into every child, depth-first.
    if exist(file, "file") ~= 2
        throw(MException('Alakazam:collectBranchTree', ...
            'I''m afraid one of this branch''s steps has a cache file that could not be found:\n\n    %s', file));
    end
    % Only the step's transformation and settings are needed, and each node
    % holds a full copy of its data, so read the small record instead.
    meta = readEegCacheMeta(file);
    nodes(end + 1) = struct('transformId', char(string(meta.Call)), ...
        'params', meta.params, 'parent', parentIdx);
    files{end + 1} = file;
    myIdx = numel(nodes);

    [dirPart, namePart] = fileparts(file);
    childDir = fullfile(dirPart, namePart);
    if exist(childDir, "dir") == 7
        childMat = dir(fullfile(childDir, '*.mat'));
        for i = 1:numel(childMat)
            [nodes, files] = appendBranch(nodes, files, fullfile(childDir, childMat(i).name), myIdx);
        end
    end
end
