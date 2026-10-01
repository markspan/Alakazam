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
%   CONSENT ONCE. GEDAI is licensed PolyForm Noncommercial, so the first
%   install asks before downloading anything. An update of an install the
%   user already agreed to is not asked again; it is said in the command
%   window. A GEDAI already on the path (EEGLAB's plugin manager puts it
%   in eeglab/plugins) counts as agreed to as well.
%
%   OFFLINE. When GitHub cannot be reached, or an update fails to
%   download, the newest installed release is used, with a warning in the
%   second case. Only having no release at all and no way to get one is an
%   error.
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
%   See also AUTOGEDAI, EEGLABENVIRONMENT.INSTALLFROMZIP.

    arguments
        options.Root (1, :) char = defaultRoot()
        options.FetchLatest = []
        options.Download (1, 1) function_handle = @downloadRelease
        options.Consent (1, 1) function_handle = @askToInstall
    end

    releases = installedReleases(options.Root);
    latest = newestRelease(options.FetchLatest);

    if ~isempty(latest) && (isempty(releases) || isNewer(latest.Version, releases(1).Version))
        releases = obtain(latest, releases, options);
    end
    if isempty(releases)
        throw(MException('Alakazam:AutoGEDAI', ...
            ['I''m afraid GEDAI is not installed and I could not reach GitHub to download ' ...
             'it. Please connect to the internet and run AutoGEDAI again, or install it ' ...
             'yourself from https://github.com/neurotuning/GEDAI-master.']));
    end

    installed = releases(1);
    attach(installed.Folder);
end

% ======================================================================= %
function releases = obtain(latest, releases, options)
%OBTAIN  Download LATEST, asking first when nothing is installed yet, and
%   return the releases with it first. A failed update keeps RELEASES.
    if isempty(releases)
        if ~options.Consent(latest.Version)
            throw(MException('Alakazam:AutoGEDAI', ...
                ['I''m afraid GEDAI is required but could not be found on the MATLAB path, ' ...
                 'and its installation was declined. Please install it yourself from ' ...
                 'https://github.com/neurotuning/GEDAI-master, or run AutoGEDAI again and ' ...
                 'accept the download.']));
        end
    else
        fprintf('AutoGEDAI: updating GEDAI from v%s to v%s, the newest release.\n', ...
            releases(1).Version, latest.Version);
    end

    target = fullfile(options.Root, ['v' latest.Version]);
    try
        options.Download(latest.Url, target);
    catch downloadError
        if isempty(releases)
            rethrow(downloadError);
        end
        warning('Alakazam:AutoGEDAI:update', ...
            'AutoGEDAI could not download GEDAI v%s (%s), so v%s is used.', ...
            latest.Version, downloadError.message, releases(1).Version);
        return;
    end

    fresh = installedReleases(target);
    if isempty(fresh)
        throw(MException('Alakazam:installMissing', ...
            'I''m afraid GEDAI.m was not found under %s after downloading %s.', target, latest.Url));
    end
    releases = [fresh(1), releases];
end

% ======================================================================= %
function releases = installedReleases(root)
%INSTALLEDRELEASES  Every GEDAI install under ROOT or on the path, newest
%   first, as a struct array with fields Version and Folder.
%   Both of the layouts Alakazam has used are found: the release's own
%   folder directly under ROOT (GEDAI-master-1.7, as the pinned install
%   unzipped it) and one per version (v1.8/GEDAI-master-1.8).
    folders = {};
    if isfolder(root)
        found = dir(fullfile(root, '**', 'GEDAI.m'));
        folders = {found.folder};
    end
    onPath = which('GEDAI', '-all');
    folders = unique([folders, cellfun(@fileparts, cellstr(onPath), 'UniformOutput', false)], 'stable');
    folders = folders(~cellfun(@isempty, folders));

    versions = cellfun(@releaseVersion, folders, 'UniformOutput', false);
    releases = struct('Version', versions, 'Folder', folders);
    if numel(releases) > 1
        [~, order] = sort(cellfun(@versionKey, versions), 'descend');
        releases = releases(order);
    end
end

function version = releaseVersion(folder)
%RELEASEVERSION  The version a GEDAI install declares in its EEGLAB plugin
%   file (vers = 'GEDAI v1.8 - September 2026'), or '' when it does not.
    version = '';
    pluginFile = fullfile(folder, 'eegplugin_GEDAI.m');
    if isfile(pluginFile)
        found = regexp(fileread(pluginFile), 'vers\s*=\s*[''"][^''"]*?v(\d+(?:\.\d+)*)', ...
            'tokens', 'once');
        if ~isempty(found)
            version = found{1};
        end
    end
end

% ======================================================================= %
function latest = newestRelease(fetchLatest)
%NEWESTRELEASE  The newest GEDAI release, or [] when it cannot be found.
%   GitHub is asked once per MATLAB session, the answer kept for the rest
%   of it: Apply to All runs AutoGEDAI once per recording, and twenty
%   recordings should not mean twenty requests, nor twenty timeouts
%   offline.
    persistent sessionAnswer
    if isempty(fetchLatest)
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
%ATTACH  Make FOLDER's GEDAI the one MATLAB runs: every other GEDAI folder,
%   and the auxiliaries folder each puts on the path, comes off it.
%   An older release's helpers left on the path would otherwise answer
%   for the newer one's wherever they share a name.
    notOnPath = warning('off', 'MATLAB:rmpath:DirNotFound');
    restoreWarning = onCleanup(@() warning(notOnPath));   % restores on return or on error
    for other = cellstr(which('GEDAI', '-all'))'
        otherFolder = fileparts(other{1});
        if ~isempty(otherFolder) && ~strcmp(otherFolder, folder)
            rmpath(fullfile(otherFolder, 'auxiliaries'));
            rmpath(otherFolder);
        end
    end
    addpath(folder);
end

function downloadRelease(url, folder)
%DOWNLOADRELEASE  Unzip the archive at URL into FOLDER.
    zipPath = [tempname() '.zip'];
    removeZip = onCleanup(@() deleteIfPresent(zipPath));
    try
        fprintf('Downloading %s ...\n', url);
        websave(zipPath, url, weboptions('Timeout', 600));
        fprintf('Unzipping into %s ...\n', folder);
        unzip(zipPath, folder);
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
