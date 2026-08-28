function loadGrandAverages(this)
%LOADGRANDAVERAGES  Populate the Grand Averages tree (this.GrandAveragesTree,
%   its own WorkSpaceTree instance -- see WorkSpace.CreateTreeComponent)
%   from CacheDirectory/GrandAverages, the flat folder every grand-average
%   dataset is saved into (see Alakazam.saveGrandAverage). Grand averages
%   are always top-level nodes here (parentId '') -- they never nest under
%   any single subject's branch, since they combine several, and now have
%   their own tree instead of a single always-present "Grand Averages" root
%   node inside the data & analyses tree.
%
%   SCOPED TO THIS WORKSPACE'S OWN DATA. The GrandAverages folder is a flat
%   directory inside the cache, and one cache is routinely shared by many
%   workspaces -- in this repository alone eleven .wksp files point at
%   Data/Cache while their Raw directories hold different studies. A plain
%   scan of that folder therefore showed every grand average ever computed
%   against that cache in every workspace, including ones combining
%   subjects this workspace has never heard of: opening a workspace for one
%   study listed another study's results as if they belonged to it.
%
%   The rule, matching Alakazam.findGrandAverageCandidates: only data
%   rooted on a recording in this workspace's Raw directory belongs to this
%   workspace. A grand average records the cache files it was built from
%   (EEG.etc.GrandAverage.sources), and this.Tree -- already populated by
%   the time open() calls this -- holds exactly the cache files reachable
%   from this workspace's own recordings, so the two are intersected.
%
%   A grand average counts as belonging here when ANY of its sources does,
%   not all of them. Requiring all would make a legitimate result disappear
%   the moment one subject's raw file was moved out of the Raw directory,
%   which is a surprising way to lose sight of saved work; requiring one is
%   enough to keep a wholly unrelated study's grand averages out, which is
%   what this is for.
%
%   A grand average that records NO sources (written before that field
%   existed, or damaged) is shown rather than hidden. Its provenance cannot
%   be checked either way, and silently hiding an analyst's saved result is
%   the worse of the two errors.
    gaDir = fullfile(this.CacheDirectory, 'GrandAverages');
    if ~exist(gaDir, "dir")
        return; % nothing saved yet
    end

    owned = ownedCacheFiles(this);

    found = dir(fullfile(gaDir, '*.mat'));
    for i = 1:numel(found)
        file = fullfile(found(i).folder, found(i).name);
        loaded = load(file, "EEG");
        if ~belongsHere(loaded.EEG, owned)
            continue;
        end
        % 'grandAverage', matching Alakazam.saveGrandAverage's own fresh-
        % creation path -- its own dedicated icon regardless of the
        % underlying data's time/frequency domain, not a borrowed
        % time/freq badge (see alakazam-tree.js's ICONS map comment).
        this.GrandAveragesTree.addNode(loaded.EEG.id, '', 'grandAverage', file, ...
            WorkSpaceTree.optsFor(loaded.EEG));
    end
end

% ======================================================================= %
function owned = ownedCacheFiles(this)
%OWNEDCACHEFILES  Every cache file reachable from this workspace's own
%   recordings, as a normalised set for membership testing.
    owned = containers.Map('KeyType', 'char', 'ValueType', 'logical');
    nodes = this.Tree.allNodes();
    for i = 1:numel(nodes)
        key = normalisePath(nodes(i).UserData);
        if ~isempty(key)
            owned(key) = true;
        end
    end
end

function tf = belongsHere(EEG, owned)
%BELONGSHERE  Does this grand average descend from data in this workspace?
    tf = true;
    if owned.Count == 0
        % No data tree at all (an empty Raw directory): nothing can be
        % matched, so nothing is claimed. Returning false here rather than
        % true is deliberate -- with no recordings loaded, every grand
        % average in a shared cache belongs to some other workspace.
        tf = false;
        return;
    end
    if ~isfield(EEG, 'etc') || ~isstruct(EEG.etc) || ~isfield(EEG.etc, 'GrandAverage')
        return;   % no provenance recorded: shown, see the header note
    end
    ga = EEG.etc.GrandAverage;
    if ~isstruct(ga) || ~isfield(ga, 'sources') || isempty(ga.sources)
        return;   % ditto
    end
    sources = ga.sources;
    if ~iscell(sources)
        sources = {sources};
    end
    for i = 1:numel(sources)
        key = normalisePath(sources{i});
        if ~isempty(key) && isKey(owned, key)
            return;   % tf is already true
        end
    end
    tf = false;
end

function key = normalisePath(p)
%NORMALISEPATH  A path reduced to a comparable key.
%   Separators are unified because a path may have been recorded with
%   either, and case is folded on Windows, where the same file is routinely
%   named with different capitalisation and the comparison would otherwise
%   miss. Case is preserved elsewhere, where it is significant.
    key = '';
    if isempty(p)
        return;
    end
    key = char(p);
    key = strrep(strrep(key, '/', filesep), '\', filesep);
    if ispc
        key = lower(key);
    end
end
