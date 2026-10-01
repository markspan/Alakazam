function installed = ensureLatestGEDAI(options)
%ENSURELATESTGEDAI  Put the newest GEDAI release on the path, installing it
%   on first use and updating it when a newer one is out.
%
%   INSTALLED = ensureLatestGEDAI() returns a struct with
%     Version  the GEDAI version now first on the path, such as '1.8'
%              ('' when the install does not say)
%     Folder   the folder holding its GEDAI.m
%
%   ALWAYS THE NEWEST RELEASE. Alakazam runs the newest GEDAI release there
%   is (neurotuning/GEDAI-master's highest version tag), not a pinned one.
%   Once per MATLAB session GitHub is asked for it; a release newer than
%   the newest installed is downloaded into a folder of its own under
%   Documents/MATLAB/GEDAI and used from then on. Older releases stay on
%   disk, off the path. Because the result of a step can then change with
%   a release, AutoGEDAI records the version it ran in EEG.etc.GEDAI.
%
%   THE VERSION IS THE TAG'S. An install's version is read from its folder
%   name, which comes from the tag it was downloaded from (GEDAI-master-1.8,
%   in v1.8), and from GEDAI's EEGLAB plugin file only when the folder does
%   not say. The plugin file is not kept up to date: v1.7.1's still says
%   v1.7, and taking it at its word would download v1.7.1 again every
%   session.
%
%   CONSENT ONCE. GEDAI is licensed PolyForm Noncommercial, so the first
%   install asks before downloading anything. An update of an install the
%   user already agreed to is not asked again; it is said in the command
%   window. A GEDAI already on the path (EEGLAB's plugin manager puts it
%   in eeglab/plugins) counts as agreed to as well.
%
%   OFFLINE. When GitHub cannot be reached, or an update fails to
%   download, the newest installed release is used, with a warning in the
%   second case, and the update is not tried again until MATLAB restarts.
%   Only having no release at all and no way to get one is an error
%   (Alakazam:AutoGEDAI:notInstalled).
%
%   Name-value arguments, for tests; every real caller omits them:
%     Root         folder the releases are installed in
%                  (default <home>/Documents/MATLAB/GEDAI)
%     FetchLatest  @() returning struct('Version', '1.8', 'Url', zipUrl),
%                  erroring when the newest release cannot be found
%                  (default: GitHub's tag list, asked once per session)
%     Download     @(url, folder) putting the archive at URL in FOLDER
%     Consent      @(version) true when the first install may proceed
%
%   See also AUTOGEDAI, EEGLABENVIRONMENT.FINDINSTALLED.

    arguments
        options.Root (1, :) char = defaultRoot()
        options.FetchLatest = []
        options.Download (1, 1) function_handle = @downloadRelease
        options.Consent (1, 1) function_handle = @askToInstall
    end

    releases = installedReleases(options.Root);
    latest = newestRelease(options.FetchLatest);

    if ~isempty(latest) && (isempty(releases) || isNewer(latest.Version, releases(1).Version))
        [releases, downloaded] = obtain(latest, releases, options);
        if ~downloaded && isempty(options.FetchLatest)
            newestRelease([], true);   % not again this session: Apply to All would retry per recording
        end
    end
    if isempty(releases)
        throw(MException('Alakazam:AutoGEDAI:notInstalled', ...
            ['I''m afraid GEDAI is not installed and I could not reach GitHub to download ' ...
             'it. Please connect to the internet and run AutoGEDAI again, or install it ' ...
             'yourself from https://github.com/neurotuning/GEDAI-master.']));
    end

    installed = releases(1);
    attach(installed.Folder);
end

% ======================================================================= %
function [releases, downloaded] = obtain(latest, releases, options)
%OBTAIN  Download LATEST, asking first when nothing is installed yet, and
%   return the releases with it first. A failed update keeps RELEASES.
    downloaded = false;
    if isempty(releases)
        if ~options.Consent(latest.Version)
            throw(MException('Alakazam:AutoGEDAI:notInstalled', ...
                ['I''m afraid GEDAI is required but could not be found on the MATLAB path, ' ...
                 'and its installation was declined. Please install it yourself from ' ...
                 'https://github.com/neurotuning/GEDAI-master, or run AutoGEDAI again and ' ...
                 'accept the download.']));
        end
    else
        fprintf('AutoGEDAI: updating GEDAI from %s to v%s, the newest release.\n', ...
            describeVersion(releases(1).Version), latest.Version);
    end

    target = fullfile(options.Root, ['v' latest.Version]);
    try
        options.Download(latest.Url, target);
        fresh = dir(fullfile(target, '**', 'GEDAI.m'));
        if isempty(fresh)
            error('Alakazam:installMissing', 'GEDAI.m was not found under %s after downloading %s', ...
                target, latest.Url);
        end
    catch downloadError
        if isempty(releases)
            rethrow(downloadError);
        end
        warning('Alakazam:AutoGEDAI:update', ...
            'AutoGEDAI could not install GEDAI v%s (%s), so %s is used.', ...
            latest.Version, downloadError.message, describeVersion(releases(1).Version));
        return;
    end

    % Only the folder just downloaded, and its version as the tag gave it:
    % listing everything installed again would put an older release found
    % on the path first if this one's folder did not say its version.
    [~, shallowest] = min(cellfun(@numel, {fresh.folder}));
    releases = [struct('Version', latest.Version, 'Folder', fresh(shallowest).folder), releases];
    downloaded = true;
end

% ======================================================================= %
function releases = installedReleases(root)
%INSTALLEDRELEASES  Every GEDAI install under ROOT or on the path, newest
%   first, as a struct array with fields Version and Folder.
%   Both of the layouts Alakazam has used are found: the release's own
%   folder directly under ROOT (GEDAI-master-1.7, as the pinned install
%   unzipped it) and one per version (v1.8/GEDAI-master-1.8).
    underRoot = {};
    if isfolder(root)
        found = dir(fullfile(root, '**', 'GEDAI.m'));
        underRoot = {found.folder};
    end
    onPath = cellfun(@fileparts, cellstr(which('GEDAI', '-all')), 'UniformOutput', false);
    % dir gives a row and which a column; one folder can be both, and on
    % Windows in two spellings of its case.
    folders = [reshape(underRoot, 1, []), reshape(onPath, 1, [])];
    folders = folders(~cellfun(@isempty, folders));
    [~, first] = unique(pathKey(folders), 'stable');
    folders = folders(sort(first));

    versions = cellfun(@releaseVersion, folders, 'UniformOutput', false);
    releases = struct('Version', versions, 'Folder', folders);
    if numel(releases) > 1
        [~, order] = sort(cellfun(@versionKey, versions), 'descend');   % stable: ties keep ROOT's first
        releases = releases(order);
    end
end

function version = releaseVersion(folder)
%RELEASEVERSION  The version of the GEDAI install in FOLDER, or '' when
%   nothing says: from the folder's name (GEDAI-master-1.8, GitHub's name
%   for tag v1.8's archive, or GEDAI1.8, EEGLAB's plugin manager's), else
%   from its parent's (v1.8, the folder Alakazam installs a release in),
%   else from the EEGLAB plugin file (vers = 'GEDAI v1.8 - September 2026').
    version = folderVersion(folder, '^GEDAI(?:-master)?[-_]?v?(\d+(?:\.\d+)*)$');
    if isempty(version)
        version = folderVersion(fileparts(folder), '^v(\d+(?:\.\d+)*)$');
    end
    pluginFile = fullfile(folder, 'eegplugin_GEDAI.m');
    if isempty(version) && isfile(pluginFile)
        found = regexp(fileread(pluginFile), 'vers\s*=\s*[''"][^''"]*?v(\d+(?:\.\d+)*)', ...
            'tokens', 'once');
        if ~isempty(found)
            version = found{1};
        end
    end
end

function version = folderVersion(folder, pattern)
%FOLDERVERSION  The version in FOLDER's own name, matched by PATTERN, or ''.
%   Its whole name: fileparts would take 1.7.1's ".7.1" for an extension.
    [~, name, extension] = fileparts(folder);
    found = regexpi([name extension], pattern, 'tokens', 'once');
    version = '';
    if ~isempty(found)
        version = found{1};
    end
end

% ======================================================================= %
function latest = newestRelease(fetchLatest, forget)
%NEWESTRELEASE  The newest GEDAI release, or [] when it cannot be found.
%   GitHub is asked once per MATLAB session, the answer kept for the rest
%   of it: Apply to All runs AutoGEDAI once per recording, and twenty
%   recordings should not mean twenty requests, nor twenty timeouts
%   offline. newestRelease([], true) replaces the kept answer with [], so
%   that an update that failed is not tried again for every recording.
    persistent sessionAnswer
    if nargin > 1 && forget
        sessionAnswer = {[]};
        latest = [];
    elseif isempty(fetchLatest)
        if isempty(sessionAnswer)
            sessionAnswer = {askGitHub(@latestTaggedRelease)};
        end
        latest = sessionAnswer{1};
    else
        latest = askGitHub(fetchLatest);
    end
end

function latest = askGitHub(fetchLatest)
    try
        latest = fetchLatest();
    catch fetchError
        fprintf('AutoGEDAI: could not check for a newer GEDAI release (%s).\n', fetchError.message);
        latest = [];
    end
end

function latest = latestTaggedRelease()
%LATESTTAGGEDRELEASE  The highest version tag of neurotuning/GEDAI-master.
%   Tags, not GitHub releases: the archive Alakazam installs is a tag's,
%   and a tag is there whether or not a release page was written for it.
%   Only plain version tags count (v1.8, 1.8.1); anything else, such as a
%   beta, is not a release.
    tags = webread('https://api.github.com/repos/neurotuning/GEDAI-master/tags?per_page=100', ...
        weboptions('Timeout', 15, 'ContentType', 'json'));
    if iscell(tags)
        names = cellfun(@(t) t.name, tags, 'UniformOutput', false);
    else
        names = {tags.name};
    end
    versions = regexp(names, '^v?(\d+(?:\.\d+)*)$', 'tokens', 'once');
    isRelease = ~cellfun(@isempty, versions);
    if ~any(isRelease)
        error('Alakazam:AutoGEDAI:noRelease', 'GEDAI-master has no version tag.');
    end
    names = names(isRelease);
    versions = cellfun(@(v) v{1}, versions(isRelease), 'UniformOutput', false);
    [~, newest] = max(cellfun(@versionKey, versions));
    latest = struct('Version', versions{newest}, 'Url', ...
        ['https://github.com/neurotuning/GEDAI-master/archive/refs/tags/' names{newest} '.zip']);
end

% ======================================================================= %
function attach(folder)
%ATTACH  Make FOLDER's GEDAI the one MATLAB runs: every other GEDAI folder
%   comes off the path, and with it every folder under it (GEDAI puts its
%   auxiliaries on the path itself, EEGLAB a plugin's subfolders). An older
%   release's helpers left on the path would otherwise answer for the
%   newer one's wherever they share a name.
    others = cellfun(@fileparts, cellstr(which('GEDAI', '-all')), 'UniformOutput', false);
    others = others(~cellfun(@isempty, others) & ~strcmp(pathKey(others), pathKey({folder})));
    if isempty(others) && ~isempty(which('GEDAI'))
        return;   % FOLDER's is the only GEDAI there is: leave the path alone
    end
    entries = strsplit(path(), pathsep);
    for other = reshape(others, 1, [])
        inside = strcmp(pathKey(entries), pathKey(other)) ...
            | startsWith(pathKey(entries), pathKey({[other{1} filesep]}));
        for entry = entries(inside)
            rmpath(entry{1});
        end
    end
    addpath(folder);
end

function keys = pathKey(folders)
%PATHKEY  FOLDERS as they compare: Windows paths are not case-sensitive.
    keys = cellstr(folders);
    if ispc
        keys = lower(keys);
    end
end

function downloadRelease(url, folder)
%DOWNLOADRELEASE  Unzip the archive at URL into FOLDER.
%   It is unzipped elsewhere first and moved into place whole, so that a
%   download or unzip broken off halfway leaves no half a release behind,
%   which would then be taken for an install of this version.
    zipPath = [tempname() '.zip'];
    staging = tempname();
    removeZip = onCleanup(@() deleteIfPresent(zipPath));
    removeStaging = onCleanup(@() removeFolderIfPresent(staging));
    try
        fprintf('Downloading %s ...\n', url);
        websave(zipPath, url, weboptions('Timeout', 600));
        fprintf('Unzipping into %s ...\n', folder);
        unzip(zipPath, staging);
        if ~isfolder(folder)
            mkdir(folder);
        end
        unzipped = dir(staging);
        for entry = setdiff({unzipped.name}, {'.', '..'})
            moved = movefile(fullfile(staging, entry{1}), folder);
            if ~moved
                error('Alakazam:download', 'could not move %s into %s', entry{1}, folder);
            end
        end
    catch downloadError
        error('Alakazam:download', ...
            'I wasn''t able to download or unzip %s, I''m afraid: %s', url, downloadError.message);
    end
end

function deleteIfPresent(file)
    if isfile(file)
        delete(file);
    end
end

function removeFolderIfPresent(folder)
    if isfolder(folder)
        rmdir(folder, 's');
    end
end

% ======================================================================= %
function ok = askToInstall(version)
%ASKTOINSTALL  The licence notice and the question, before a first install.
    % LEGACY-JAVA-GUI: questdlg is a classic Java/AWT dialog, not a
    % uifigure; see migration.md's "old-style Java-based graphics" checklist.
    answer = questdlg([ ...
        'AutoGEDAI needs the GEDAI EEGLAB plugin (neurotuning/GEDAI-master), ', ...
        'which was not found on the MATLAB path.', newline, newline, ...
        'GEDAI is licensed under the PolyForm Noncommercial License 1.0.0: ', ...
        'free for personal, noncommercial research use; a separate licence ', ...
        'is required for commercial use. Full terms: ', ...
        'https://github.com/neurotuning/GEDAI-master/blob/master/LICENSE', newline, newline, ...
        'Download and install GEDAI v' version ', the newest release, into your ', ...
        'Documents/MATLAB folder? Newer releases will then be installed as they come out.'], ...
        'GEDAI not found', ...
        'Download and install', 'Cancel', 'Download and install');
    ok = strcmp(answer, 'Download and install');
end

function root = defaultRoot()
    home = getenv('USERPROFILE');
    if isempty(home)
        home = char(java.lang.System.getProperty('user.home'));
    end
    root = fullfile(home, 'Documents', 'MATLAB', 'GEDAI');
end

% ======================================================================= %
function tf = isNewer(candidate, installed)
    tf = versionKey(candidate) > versionKey(installed);
end

function key = versionKey(version)
%VERSIONKEY  A number that orders versions as versions: 1.10 after 1.9.
%   Up to three parts, a thousand values each; '' (an install that does
%   not say) orders before every version.
    parts = str2double(regexp(version, '\d+', 'match'));
    parts(end + 1:3) = 0;
    key = parts(1:3) * [1e6; 1e3; 1];
end

function text = describeVersion(version)
    if isempty(version)
        text = 'an unnumbered install';
    else
        text = ['v' version];
    end
end
