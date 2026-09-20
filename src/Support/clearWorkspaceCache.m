function targets = clearWorkspaceCache(nodes, cacheDirectory, mode, dryRun)
%CLEARWORKSPACECACHE  The cached files a workspace clear removes, and (unless
%   DRYRUN) removes them.
%
%   TARGETS = clearWorkspaceCache(NODES, CACHEDIRECTORY, MODE) deletes this
%   workspace's cached analyses and returns the paths it removed.
%   clearWorkspaceCache(..., MODE, true) only reports what it WOULD remove.
%
%   NODES is the workspace tree's node list (WorkSpaceTree.allNodes): a
%   struct array with at least UserData (a cache file path) and IsRoot.
%
%   MODE is 'normal' or 'deep'.
%
%     NORMAL removes the analyses: for every recording in the workspace, the
%     folder <id>/ that holds each transformation result and its sidecar,
%     and the grand averages built entirely from these recordings. It KEEPS
%     each recording's own cache file <id>.mat and its <id>.mat.json sidecar,
%     which is the recording as loaded from its raw file. That is the
%     expensive part to recreate (a 400 MB .set file has to be read and
%     converted again), and it holds no analysis, so a normal clear is what
%     you want before re-running a revised pipeline.
%
%     DEEP removes those as well, so every recording is read from its raw
%     file again the next time it is opened.
%
%   SCOPED TO THE WORKSPACE, in both modes. One cache is routinely shared by
%   several workspaces analysing different studies, so only data rooted on a
%   recording that is in NODES belongs to this workspace. Anything else in
%   the cache is left alone.
%
%   Grand averages are deleted only when EVERY subject they combine is
%   rooted here. A grand average is shown when ANY of its sources is (which
%   is right for displaying it), but one that combines this study with
%   another is partly somebody else's result, so it is kept. A grand
%   average with no recorded provenance is never claimed: when in doubt, do
%   not delete.
%
%   A path that is not inside CACHEDIRECTORY is never deleted; it is skipped
%   with a warning. These paths come from tree node data, and a delete is not
%   something to perform on a path that has not been shown to be where it
%   claims to be.
%
%   See also WORKSPACE/RAWCLEAR, WORKSPACETREE.
    if nargin < 4 || isempty(dryRun)
        dryRun = false;
    end
    mode = lower(char(string(mode)));
    if ~any(strcmp(mode, {'normal', 'deep'}))
        throw(MException('Alakazam:clearWorkspaceCache', ...
            'I''m afraid the clear mode must be "normal" or "deep", not "%s".', mode));
    end

    candidates = candidateTargets(nodes, cacheDirectory, strcmp(mode, 'deep'));

    targets = {};
    for i = 1:numel(candidates)
        target = candidates{i};
        if ~isUnder(target, cacheDirectory)
            if ~dryRun
                warning('Alakazam:clearWorkspaceCache', ...
                    'Refusing to delete "%s": it is outside the cache directory.', target);
            end
            continue;
        end
        isFolder = exist(target, 'dir') == 7;
        if ~isFolder && exist(target, 'file') ~= 2
            continue;   % nothing there: not yet computed, or already gone
        end
        targets{end + 1} = target; %#ok<AGROW>
        if dryRun
            continue;
        end
        if isFolder
            rmdir(target, 's');
        else
            delete(target);
        end
    end
end

% ======================================================================= %
function targets = candidateTargets(nodes, cacheDirectory, deep)
%CANDIDATETARGETS  Every path this workspace may delete in this mode.
    targets = {};

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
        [folder, stem] = fileparts(rootFile);

        % The descendants of <id>.mat live in the sibling folder <id>/, and
        % every cache node in it is written with "<file>.mat.json" and
        % "<file>.mat.meta" records that go with the folder.
        targets{end + 1} = fullfile(folder, stem); %#ok<AGROW>

        % The recording as loaded from its raw file: a deep clean only.
        % Its sidecar goes with it, because deleting the .mat alone would
        % leave the cache littered with descriptions of datasets that no
        % longer exist.
        if deep
            targets{end + 1} = rootFile; %#ok<AGROW>
            targets{end + 1} = [rootFile '.json']; %#ok<AGROW>
            targets{end + 1} = [rootFile '.meta']; %#ok<AGROW>
        end
    end

    gaDir = fullfile(cacheDirectory, 'GrandAverages');
    if exist(gaDir, 'dir') ~= 7
        return;
    end
    found = dir(fullfile(gaDir, '*.mat'));
    for i = 1:numel(found)
        file = fullfile(found(i).folder, found(i).name);
        if whollyOwned(file, ownedFiles)
            targets{end + 1} = file; %#ok<AGROW>
            targets{end + 1} = [file '.json']; %#ok<AGROW>
            targets{end + 1} = [file '.meta']; %#ok<AGROW>
        end
    end
end

function tf = whollyOwned(gaFile, ownedFiles)
%WHOLLYOWNED  Is every subject in this grand average rooted in this
%   workspace? A grand average with no recorded provenance is NOT claimed.
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

function tf = isUnder(target, root)
%ISUNDER  Is TARGET inside ROOT (and not ROOT itself)?
    t = normalisePath(target);
    r = normalisePath(root);
    if isempty(t) || isempty(r)
        tf = false;
        return;
    end
    if r(end) ~= filesep
        r = [r filesep];
    end
    tf = strncmp(t, r, numel(r)) && numel(t) > numel(r);
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
