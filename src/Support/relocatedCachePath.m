function path = relocatedCachePath(recorded, cacheDir)
%RELOCATEDCACHEPATH  A cache file recorded where a workspace's cache used to
%   be, found where it is now.
%
%   PATH = RELOCATEDCACHEPATH(RECORDED, CACHEDIR) is RECORDED when that file
%   exists. Otherwise it is the same file under CACHEDIR: the longest
%   trailing part of RECORDED whose first folder (or file) is in CACHEDIR,
%   which, for a cache moved or copied whole, is the part below the old
%   Cache directory. When no part of it is there, RECORDED is returned as
%   it is.
%
%   A grand average records the cache files it was made from by their full
%   paths, so moving a workspace's folders (to another disk, say) left it
%   naming files that were no longer there: it vanished from the tree as
%   another study's, or was shown with its sources deleted, though they had
%   only moved. A source deleted after the move still lands in its
%   recording's folder here, so it is still known to be this workspace's,
%   and still reported missing.
%
%   See also GRANDAVERAGESOURCES, LOADGRANDAVERAGES.
    path = char(recorded);
    if isempty(path) || isempty(cacheDir) || isfile(path)
        return;
    end
    parts = regexp(path, '[\\/]+', 'split');
    parts = parts(~cellfun(@isempty, parts));
    for k = 1:numel(parts)
        here = fullfile(cacheDir, parts{k});
        if isfile(here) || isfolder(here)
            path = fullfile(cacheDir, parts{k:end});
            return;
        end
    end
end
