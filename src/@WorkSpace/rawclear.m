function rawclear(this,~,~)
%RAWCLEAR  "Clear WorkSpace": delete this workspace's cached analyses.
%
%   SCOPED TO THIS WORKSPACE. This used to be rmdir(CacheDirectory, 's') --
%   the whole cache folder, unconditionally. One cache is routinely shared
%   by several workspaces analysing different studies (eleven .wksp files
%   in this repository alone point at Data/Cache), so "Clear WorkSpace" in
%   one of them silently destroyed every other one's work as well, with a
%   confirmation dialog that gave no hint it would.
%
%   The rule is the same one findGrandAverageCandidates and
%   loadGrandAverages already follow: only data rooted on a recording in
%   this workspace's Raw directory belongs to this workspace. Each root
%   node owns <CacheDirectory>/<id>.mat plus the <CacheDirectory>/<id>/
%   folder its descendants live in (see resolveCachePaths/treeTraverse),
%   and those are what get removed. Anything else in the cache belongs to
%   somebody else and is left alone.
%
%   Grand averages are deleted only when EVERY subject they combine is
%   rooted here. loadGrandAverages shows one when ANY of its sources is --
%   which is right for displaying it, and much too loose for deleting it,
%   since a grand average combining this study with another is partly
%   somebody else's result. The asymmetry is deliberate: show generously,
%   delete conservatively.

    targets = ownedCacheTargets(this);

    % LEGACY-JAVA-GUI: questdlg is a classic Java/AWT dialog, not a
    % uifigure -- see migration.md's "old-style Java-based graphics"
    % checklist.
    answer = questdlg(confirmationText(targets), ...
    	'Clear Workspace?', ...
        'Yes, delete!','Sorry, what? No!','Sorry, what? No!');
    if ~strcmp(answer, 'Yes, delete!')
        return;
    end

    % gcf ignores this app's uifigure (it only tracks classic figures),
    % so it used to silently CREATE a new blank one here -- exactly the
    % stray figure window users saw, which then sat on top of/stole
    % focus from MainFigure and made the app look hung. Use the app's
    % own window instead, restored via onCleanup so the busy indicator
    % can't get stuck if a delete or open throws partway through.
    fig = this.Parent.MainFigure;
    restoreBusy = beginBusy(fig, 'Clearing cache...'); %#ok<NASGU>

    for i = 1:numel(targets)
        removeTarget(targets{i}, this.CacheDirectory);
    end

    if exist(this.CacheDirectory, 'dir') ~= 7
        mkdir(this.CacheDirectory);   % only if it went missing entirely
    end
    open(this);
end

% ======================================================================= %
function targets = ownedCacheTargets(this)
%OWNEDCACHETARGETS  Every path this workspace may delete: one root cache
%   file and its descendants folder per recording, plus the grand averages
%   built entirely from them.
    targets = {};

    nodes = this.Tree.allNodes();
    ownedFiles = containers.Map('KeyType', 'char', 'ValueType', 'logical');
    for i = 1:numel(nodes)
        key = normalisePath(nodes(i).UserData);
        if ~isempty(key)
            ownedFiles(key) = true;
        end
        if ~nodes(i).IsRoot || isempty(nodes(i).UserData)
            continue;
        end
        rootFile = nodes(i).UserData;
        targets{end + 1} = rootFile; %#ok<AGROW>
        % Every cache node is written alongside a "<file>.mat.json"
        % sidecar (see saveEegCache/readEegCacheInfo); deleting the .mat
        % without it would leave the cache littered with descriptions of
        % datasets that no longer exist.
        targets{end + 1} = [rootFile '.json']; %#ok<AGROW>
        % The descendants of <id>.mat live in the sibling folder <id>/,
        % whose own sidecars go with it when the folder is removed.
        [folder, stem] = fileparts(rootFile);
        targets{end + 1} = fullfile(folder, stem); %#ok<AGROW>
    end

    gaDir = fullfile(this.CacheDirectory, 'GrandAverages');
    if exist(gaDir, 'dir') ~= 7
        return;
    end
    found = dir(fullfile(gaDir, '*.mat'));
    for i = 1:numel(found)
        file = fullfile(found(i).folder, found(i).name);
        if whollyOwned(file, ownedFiles)
            targets{end + 1} = file; %#ok<AGROW>
            sidecar = [file '.json'];
            if exist(sidecar, 'file') == 2
                targets{end + 1} = sidecar; %#ok<AGROW>
            end
        end
    end
end

function tf = whollyOwned(gaFile, ownedFiles)
%WHOLLYOWNED  Is every subject in this grand average rooted in this
%   workspace? A grand average with no recorded provenance is NOT claimed:
%   when in doubt, do not delete.
    tf = false;
    try
        loaded = load(gaFile, 'EEG');
    catch
        return;   % unreadable: leave it alone
    end
    EEG = loaded.EEG;
    if ~isfield(EEG, 'etc') || ~isstruct(EEG.etc) || ~isfield(EEG.etc, 'GrandAverage')
        return;
    end
    ga = EEG.etc.GrandAverage;
    if ~isstruct(ga) || ~isfield(ga, 'sources') || isempty(ga.sources)
        return;
    end
    sources = ga.sources;
    if ~iscell(sources)
        sources = {sources};
    end
    for i = 1:numel(sources)
        key = normalisePath(sources{i});
        if isempty(key) || ~isKey(ownedFiles, key)
            return;
        end
    end
    tf = true;
end

function removeTarget(target, cacheDir)
%REMOVETARGET  Delete one file or folder, but only from inside the cache.
%   The containment check is the point: these paths come from tree node
%   data, and a delete is not something to perform on a path that has not
%   been proven to be where it claims to be. A target outside the cache is
%   skipped with a warning rather than removed.
    if ~isUnder(target, cacheDir)
        warning('Alakazam:WorkSpace:rawclear', ...
            'Refusing to delete "%s": it is outside the cache directory.', target);
        return;
    end
    if exist(target, 'dir') == 7
        rmdir(target, 's');
    elseif exist(target, 'file') == 2
        delete(target);
    end
end

function tf = isUnder(target, root)
%ISUNDER  Is TARGET inside ROOT (and not ROOT itself)?
    t = normalisePath(target);
    r = normalisePath(root);
    if isempty(t) || isempty(r)
        tf = false; return;
    end
    if r(end) ~= filesep
        r = [r filesep];
    end
    tf = strncmp(t, r, numel(r)) && numel(t) > numel(r);
end

function text = confirmationText(targets)
%CONFIRMATIONTEXT  Say what will actually go, and what will not.
%   The old wording -- "delete all your work" -- was both alarming and,
%   on a shared cache, an understatement of the blast radius. Now that the
%   scope is real, the dialog states it.
    nRoots = 0;
    for i = 1:numel(targets)
        if endsWith(lower(targets{i}), '.mat') && ~contains(targets{i}, [filesep 'GrandAverages' filesep])
            nRoots = nRoots + 1;
        end
    end
    if nRoots == 0
        text = sprintf(['There are no cached analyses for this workspace to clear.' ...
            '\n\nClear anyway?']);
        return;
    end
    text = sprintf([ ...
        'Delete the cached analyses for the %d recording(s) in this workspace?\n\n' ...
        'The raw recordings themselves are not touched, and neither is anything in ' ...
        'the cache folder belonging to other workspaces.'], nRoots);
end

function key = normalisePath(p)
%NORMALISEPATH  A path reduced to a comparable key: separators unified, and
%   case folded on Windows, where the same file is routinely named with
%   different capitalisation. Case is preserved elsewhere, where it matters.
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
