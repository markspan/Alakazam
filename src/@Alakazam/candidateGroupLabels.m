function groups = candidateGroupLabels(this, candidateFiles)
%CANDIDATEGROUPLABELS  Each candidate's own between-subjects group ('' if
%   none), same order as CANDIDATEFILES. findGrandAverageCandidates scans
%   the cache directory directly, not the tree, so a candidate is matched
%   back to its own tree node by file path (WorkSpaceTree exposes no
%   direct "node for this file" lookup, so this compares UserData against
%   each candidate -- the same approach Alakazam.onClearOtherAnalyses
%   already uses), then walked up to its root via Tree.rootOf -- the SAME
%   mechanism collectEntriesWithField already uses to resolve a subject
%   for the ERP/Spectral export's own .group column, which is already
%   known to work correctly.
%
%   Previously derived the subject by stripping CacheDirectory off the
%   front of the candidate's own path (string erase + first path segment)
%   -- fragile, and the actual bug: CacheDirectory as stored on this
%   WorkSpace and the path dir() returns for a candidate are not
%   guaranteed to be the identical string (trailing separator, drive-
%   letter casing, a resolved vs. unresolved path, ...), so erase() could
%   silently fail to strip anything at all, leaving every subject's own
%   lookup key wrong -- which is exactly what was reported ("fewer than
%   two groups assigned" with two real groups assigned). Matching by
%   UserData against the tree's own node list has no such dependency: both
%   sides are plain file-path strings produced the same way (dir() /
%   EEG.File), not one derived from the other by substring surgery.
    allNodes = this.Workspace.Tree.allNodes();
    groups = cell(1, numel(candidateFiles));
    for i = 1:numel(candidateFiles)
        match = allNodes(strcmp({allNodes.UserData}, candidateFiles{i}));
        if isempty(match)
            groups{i} = '';
            continue;
        end
        root = this.Workspace.Tree.rootOf(match(1).Id);
        if isempty(root)
            groups{i} = '';
            continue;
        end
        groups{i} = this.Workspace.groupFor(root.Name);
    end
end
