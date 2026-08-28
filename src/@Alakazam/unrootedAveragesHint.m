function hint = unrootedAveragesHint(this)
%UNROOTEDAVERAGESHINT  The extra sentence a "not enough subjects" message
%   needs when the averages exist but do not belong to this workspace.
%
%   HINT is '' when there is nothing useful to add, so callers can append
%   it unconditionally.
%
%   WHY THIS EXISTS. Candidates are scoped to data rooted on a recording in
%   this workspace's Raw directory (see findGrandAverageCandidates), which
%   is the correct definition: one cache is routinely shared by several
%   workspaces analysing different studies, and offering another study's
%   averages produces a grand average that fails on a channel-count
%   mismatch, or worse, silently succeeds.
%
%   But the consequence is confusing at exactly the wrong moment. An
%   analyst whose Raw directory has been repointed -- or who opened the
%   default workspace by habit -- sees "fewer than two were found in this
%   workspace. Run Average on more subjects first", while ten perfectly
%   good averages sit in the cache directory. Following that advice means
%   re-averaging subjects that were already averaged, and it does not work,
%   because the new results are not rooted here either.
%
%   So when the cache holds averaged datasets that the tree does not, say
%   so and name the directory to repoint. The scoping is not the bug; the
%   silence about it was.
    hint = '';

    cacheDir = this.Workspace.CacheDirectory;
    if isempty(cacheDir) || exist(cacheDir, 'dir') ~= 7
        return;
    end

    % Cheap structural count, deliberately not readEegCacheInfo on every
    % file: this runs only on the failure path, but the cache can hold
    % thousands of intermediates and the point is a hint, not an inventory.
    found = dir(fullfile(cacheDir, '**', 'Average*.mat'));
    if isempty(found)
        return;
    end

    inTree = 0;
    nodes = this.Workspace.Tree.allNodes();
    for i = 1:numel(nodes)
        if contains(lower(nodes(i).UserData), lower('Average'))
            inTree = inTree + 1;
        end
    end

    orphaned = numel(found) - inTree;
    if orphaned < 1
        return;
    end

    hint = sprintf([ ...
        '\n\nThere %s %d averaged dataset%s in the cache folder that %s not reachable ' ...
        'from this workspace: a dataset only counts as belonging here when the recording ' ...
        'it came from is in the workspace''s Raw folder (currently "%s"). If those are ' ...
        'the subjects you meant, point Raw at the recordings they came from with ' ...
        'Edit WorkSpace, or open the workspace that owns them.'], ...
        pluralIs(orphaned), orphaned, pluralS(orphaned), pluralAre(orphaned), ...
        this.Workspace.RawDirectory);
end

% ======================================================================= %
function s = pluralIs(n),  if n == 1, s = 'is'; else, s = 'are'; end, end
function s = pluralS(n),   if n == 1, s = '';   else, s = 's';   end, end
function s = pluralAre(n), if n == 1, s = 'is'; else, s = 'are'; end, end
