classdef Plugins
%PLUGINS  Transformations the user installs, from a zip file or a link, into
%   a folder of their own outside the application.
%
%   A plugin is a transformation folder exactly like those under
%   src/Transformations: <Name>/<Name>.json (the manifest), <Name>/<Name>.m
%   (the entry function) and its icon, with anything else it needs beside
%   them. Installing one copies that folder into Plugins.folder() and puts it
%   on the path. The ribbon scans that folder after src/Transformations, so
%   the plugin's button appears in its manifest's Section like any other.
%
%   WHY A FOLDER OF ITS OWN, OUTSIDE THE APPLICATION. An update replaces the
%   whole application folder and carries over only Data/ and the workspaces
%   (see applyPendingAlakazamUpdate), so a plugin copied into
%   src/Transformations would be deleted by the next update. The default,
%   <home>/Documents/MATLAB/AlakazamPlugins, sits beside EEGLAB, FieldTrip
%   and the other toolboxes Alakazam installs. The environment variable
%   ALAKAZAM_PLUGIN_FOLDER overrides it; the tests use that.
%
%   TWO STEPS, SO THAT NOTHING IS INSTALLED BEFORE THE USER HAS SEEN WHAT IT
%   IS. PREPARE fetches the zip, unpacks it in a staging folder, and finds
%   and checks every plugin in it; it installs nothing and runs none of its
%   code. The caller shows DESCRIBE's summary and asks. INSTALL then moves
%   the plugins that passed into place, and DISCARD throws a refused one
%   away. A plugin is MATLAB code that runs with the user's rights, and the
%   summary says so.
%
%   WHAT IS CHECKED, before anything is installed:
%     - the manifest has the six fields every transformation has, and its
%       Entry is <Name>.m, present beside it: the ribbon dispatches on that
%       name, and the tree finds the icon by it;
%     - <Name> is not a transformation Alakazam already has, and no other
%       function of that name is on the path, which the plugin would hide
%       or be hidden by (an installed older version of the same plugin is
%       an update, and allowed);
%     - the zip holds no entry that would unpack outside its own folder.
%   Reported but not refused: a missing icon, and a function named in the
%   manifest's optional Requires that is not on the path yet.
%
%   OPTIONAL MANIFEST FIELDS a plugin may add to the six:
%     "Version"       shown in the summary and the list of plugins;
%     "Requires"      functions it needs, e.g. ["ft_defaults"], checked at
%                     install time so a missing toolbox is said before the
%                     first run rather than in the middle of it;
%     "Recalculable"  true when the plugin seeds its dialog from
%                     TransformSettings (the contract newTransformation
%                     writes), so Recalculate can reopen it with a node's
%                     own settings (see WorkSpaceTree.isRecalculable).
%
%   LINKS. A link to a zip file is downloaded as it is. A link to a GitHub
%   repository takes its latest release (the release's own .zip asset when
%   it has one, else the source at the release's tag), or the default
%   branch when it has no release; when the list on offer holds the
%   repository (Plugins.listed), it takes the release the list shows,
%   without asking GitHub (AVAILABLE says why GitHub is asked little). A
%   link to a release (.../releases/tag/T) takes that release; and a link
%   to a folder (.../tree/BRANCH/PATH) takes the plugins inside that folder
%   of the branch. Only https is accepted.
%
%   See also ALAKAZAMRIBBON, WORKSPACETREE.ISRECALCULABLE, NEWTRANSFORMATION.

    properties (Constant)
        % The six fields every manifest carries (see DEVELOPER.md).
        ManifestFields = {'Name', 'Description', 'Entry', 'Icon', 'Section', 'Category'}
        RegistryFile = 'plugins.json'
        % The GitHub account whose Alakazam* repositories the Install plugins
        % list offers (Plugins.available).
        Account = 'markspan'
        % The plugin index: GitHub's answers about Account's repositories,
        % saved daily on Alakazam's web site (.github/scripts/plugin_index.py).
        IndexAddress = 'https://markspan.github.io/Alakazam/plugin-index.json'
        % How old a list (the index, or the one saved here) may be before
        % GitHub is asked: a day, with room for a daily index running late.
        MaxAge = hours(30)
    end

    methods (Static)
        function root = folder()
        %FOLDER  Where plugins are installed.
            root = getenv('ALAKAZAM_PLUGIN_FOLDER');
            if isempty(root)
                home = getenv('USERPROFILE');
                if isempty(home)
                    home = getenv('HOME');
                end
                if isempty(home)
                    home = char(java.lang.System.getProperty('user.home'));
                end
                root = fullfile(home, 'Documents', 'MATLAB', 'AlakazamPlugins');
            end
            root = char(root);
        end

        function roots = roots(builtInRoot)
        %ROOTS  The folders transformations are found in: the built-in ones
        %   first, which win any clash, then the plugins', when it exists.
            roots = {char(builtInRoot)};
            if isfolder(Plugins.folder())
                roots{end + 1} = Plugins.folder();
            end
        end

        function addToPath()
        %ADDTOPATH  Put every installed plugin on the path, after the
        %   application's own folders. Called once at startup.
            root = Plugins.folder();
            if isfolder(root)
                addpath(genpath(root), '-end');
            end
        end

        function folder = transformationFolder(transformId, builtInRoot)
        %TRANSFORMATIONFOLDER  The folder holding TRANSFORMID's manifest: under
        %   BUILTINROOT when it is there, else in the plugin folder, else ''.
        %   Used wherever a transformation is looked up by its id (the tree's
        %   icons, the script exporter's defaults), so a plugin is found the
        %   same way a built-in one is.
            folder = '';
            transformId = char(string(transformId));
            if ~isvarname(transformId)
                return;   % a grand average's name, a raw file: not a transformation
            end
            candidates = {};
            if nargin >= 2 && ~isempty(builtInRoot)
                candidates{end + 1} = fullfile(char(builtInRoot), transformId);
            end
            candidates{end + 1} = fullfile(Plugins.folder(), transformId);
            for c = candidates
                if isfile(fullfile(c{1}, [transformId '.json']))
                    folder = c{1};
                    return;
                end
            end
        end

        function m = manifest(transformId, builtInRoot)
        %MANIFEST  TRANSFORMID's decoded manifest, built-in or plugin; an
        %   empty struct when there is none.
            if nargin < 2
                builtInRoot = '';
            end
            m = struct([]);
            folder = Plugins.transformationFolder(transformId, builtInRoot);
            if ~isempty(folder)
                m = readManifest(folder, char(string(transformId)));
            end
        end

        function info = installed()
        %INSTALLED  Every installed plugin: its manifest's name, version and
        %   description, and the source and date of its installation.
            info = struct('Name', {}, 'Label', {}, 'Version', {}, ...
                'Description', {}, 'Source', {}, 'Link', {}, 'Installed', {}, 'Folder', {});
            root = Plugins.folder();
            if ~isfolder(root)
                return;
            end
            registry = readRegistry(root);
            entries = dir(root);
            entries = entries([entries.isdir]);
            for k = 1:numel(entries)
                name = entries(k).name;
                if ~isvarname(name)
                    continue;   % '.', '..', and anything that cannot be a plugin
                end
                m = readManifest(fullfile(root, name), name);
                if isempty(m)
                    continue;
                end
                record = registryRecord(registry, name);
                info(end + 1) = struct('Name', name, ...
                    'Label', textField(m, 'Name', name), ...
                    'Version', textField(m, 'Version', ''), ...
                    'Description', textField(m, 'Description', ''), ...
                    'Source', record.source, 'Link', linkOf(record), ...
                    'Installed', record.installed, 'Folder', fullfile(root, name)); %#ok<AGROW>
            end
        end

        function candidate = prepare(source, opts)
        %PREPARE  Fetch SOURCE, a zip file on this computer or an https link,
        %   unpack it in a staging folder and check every plugin in it.
        %   Installs nothing and runs none of its code.
        %
        %   CANDIDATE has .Source (where it came from, as said to the user),
        %   .Staging (the folder to DISCARD) and .Plugins, one element per
        %   plugin found: .Name, .Label, .Version, .Description, .Folder (in
        %   the staging folder), .Files, .Replaces (the installed version it
        %   would replace, or ''), .Problems (why it would not be installed;
        %   empty when it would) and .Warnings.
        %
        %   Name-value options, for the tests and for a caller with its own
        %   transport: BuiltInRoot (the built-in transformations, for the name
        %   check), Download (@(url, file) writes the zip at URL to FILE),
        %   FetchJson (@(url) the decoded JSON at URL, for GitHub's API) and
        %   Known (the repositories whose listed release a link to them takes,
        %   without asking GitHub: by default the list Install plugins shows,
        %   Plugins.listed).
            arguments
                source
                opts.BuiltInRoot = fullfile(fileparts(mfilename('fullpath')), 'Transformations')
                opts.Download = @defaultDownload
                opts.FetchJson = @defaultFetchJson
                opts.Known = Plugins.listed()
            end
            spec = Plugins.resolveSource(source, opts.FetchJson, opts.Known);

            staging = tempname;
            mkdir(staging);
            try
                if strcmp(spec.Kind, 'file')
                    zipFile = spec.Location;
                else
                    zipFile = fullfile(staging, 'download.zip');
                    opts.Download(spec.Location, zipFile);
                end
                requireZip(zipFile, spec.Label);
                unpacked = fullfile(staging, 'unpacked');
                safeUnzip(zipFile, unpacked, spec.Label);
                found = findPlugins(unpacked, spec.Subfolder);
                if isempty(found)
                    throw(MException('Alakazam:Plugins:noPlugin', ...
                        ['I am afraid there is no plugin in %s. A plugin is a folder ' ...
                         'holding <Name>.json, its manifest, and <Name>.m, its entry ' ...
                         'function, as each transformation under src/Transformations does.'], ...
                        spec.Label));
                end
                plugins = arrayfun(@(f) checkPlugin(f, opts.BuiltInRoot), found);
            catch err
                removeFolder(staging);
                rethrow(err);
            end
            % The link as given, when it is one: what Update fetches again.
            link = '';
            if strcmp(spec.Kind, 'url')
                link = strtrim(char(string(source)));
            end
            candidate = struct('Source', spec.Label, 'Link', link, 'Staging', staging, ...
                'Plugins', plugins);
        end

        function text = describe(candidate)
        %DESCRIBE  What PREPARE found, in the words the confirmation shows:
        %   what would be installed, what would not and why, and that a
        %   plugin is code that runs with the user's rights.
            lines = {sprintf('From %s', candidate.Source), ''};
            ok = arrayfun(@(p) isempty(p.Problems), candidate.Plugins);
            if any(ok)
                lines{end + 1} = 'To install:';
                for p = candidate.Plugins(ok)
                    lines{end + 1} = ['  ' pluginLine(p)]; %#ok<AGROW>
                    for w = p.Warnings
                        lines{end + 1} = ['    Note: ' w{1}]; %#ok<AGROW>
                    end
                end
            end
            if any(~ok)
                if any(ok)
                    lines{end + 1} = '';
                end
                lines{end + 1} = 'Not installed:';
                for p = candidate.Plugins(~ok)
                    lines{end + 1} = sprintf('  %s: %s', p.Name, strjoin(p.Problems, ' ')); %#ok<AGROW>
                end
            end
            if any(ok)
                lines = [lines, {'', ['A plugin is MATLAB code that runs with your rights. ' ...
                    'Install it only if you trust where it comes from.']}];
            end
            text = strjoin(lines, newline);
        end

        function names = install(candidate)
        %INSTALL  Move every plugin of CANDIDATE that passed its checks into the
        %   plugin folder, put it on the path and record where it came from.
        %   An installed plugin of the same name is replaced. The staging
        %   folder is removed. Returns the names installed.
            names = {};
            root = Plugins.folder();
            if ~isfolder(root)
                mkdir(root);
            end
            try
                registry = readRegistry(root);
                for p = candidate.Plugins
                    if ~isempty(p.Problems)
                        continue;
                    end
                    destination = fullfile(root, p.Name);
                    if isfolder(destination)
                        takeOffPath(destination);
                        removeFolder(destination);
                    end
                    copyPlugin(p.Folder, destination);
                    forgetFunction(p.Name);   % a replaced version may still be in memory
                    addpath(genpath(destination), '-end');
                    registry = setRecord(registry, p.Name, candidate.Source, p.Version, ...
                        candidateLink(candidate));
                    names{end + 1} = p.Name; %#ok<AGROW>
                end
                writeRegistry(root, registry);
            catch err
                Plugins.discard(candidate);
                rethrow(err);
            end
            Plugins.discard(candidate);
            rehash;
        end

        function discard(candidate)
        %DISCARD  Remove CANDIDATE's staging folder, installing nothing.
            removeFolder(candidate.Staging);
        end

        function uninstall(name)
        %UNINSTALL  Take the plugin NAME off the path and delete its folder.
            name = char(name);
            root = Plugins.folder();
            folder = fullfile(root, name);
            if ~isvarname(name) || ~isfolder(folder)
                throw(MException('Alakazam:Plugins:notInstalled', ...
                    'I am afraid there is no plugin called "%s" installed in %s.', name, root));
            end
            takeOffPath(folder);
            forgetFunction(name);
            removeFolder(folder);
            registry = readRegistry(root);
            writeRegistry(root, registry(~strcmp({registry.name}, name)));
            rehash;
        end

        function spec = resolveSource(source, fetchJson, known)
        %RESOLVESOURCE  What to fetch for SOURCE, and how to describe it.
        %   SPEC.Kind is 'file' (a zip on this computer) or 'url';
        %   .Location the file or the URL of the zip; .Subfolder the folder
        %   inside the archive to look in ('' for all of it); .Label how the
        %   source is named to the user. FETCHJSON (@(url) decoded JSON) is
        %   used for GitHub's API only. KNOWN is a list of repositories as
        %   Plugins.available returns it: a link to a repository it lists
        %   with a release takes that release, and GitHub is not asked.
            if nargin < 2 || isempty(fetchJson)
                fetchJson = @defaultFetchJson;
            end
            if nargin < 3
                known = emptyRepos();
            end
            source = strtrim(char(string(source)));
            spec = struct('Kind', 'url', 'Location', source, 'Subfolder', '', 'Label', source);
            if isempty(source)
                throw(MException('Alakazam:Plugins:noSource', ...
                    'I am afraid no zip file or link was given.'));
            end
            % A link first: isfile answers true for an https address it can
            % reach, and the page there would then be read as the zip.
            isLink = startsWith(source, {'http://', 'https://'}, 'IgnoreCase', true);
            if ~isLink && isfile(source)
                spec.Kind = 'file';
                return;
            end
            if startsWith(source, 'http://', 'IgnoreCase', true)
                throw(MException('Alakazam:Plugins:insecure', ...
                    ['I am afraid only https links are accepted: a plugin is code that ' ...
                     'will run on this computer, and over plain http it could be changed ' ...
                     'on its way here. Try the same link with https.']));
            end
            if ~startsWith(source, 'https://', 'IgnoreCase', true)
                throw(MException('Alakazam:Plugins:noSource', ...
                    'I am afraid "%s" is neither a zip file on this computer nor an https link.', ...
                    source));
            end

            gh = regexp(source, ['^https://github\.com/(?<owner>[^/?#]+)/(?<repo>[^/?#]+?)' ...
                '(?:\.git)?(?<rest>/[^?#]*)?/?(?:[?#].*)?$'], 'names', 'once');
            if isempty(gh)
                return;   % any other https link: downloaded as it is
            end
            rest = regexprep(char(gh.rest), '/+$', '');
            repo = sprintf('github.com/%s/%s', gh.owner, gh.repo);
            api = sprintf('https://api.github.com/repos/%s/%s', gh.owner, gh.repo);

            tagged = regexp(rest, '^/releases/tag/(?<tag>.+)$', 'names', 'once');
            tree = regexp(rest, '^/tree/(?<branch>[^/]+)(?<path>/.*)?$', 'names', 'once');
            if isempty(rest) || strcmp(rest, '/releases/latest')
                entry = listedEntry(known, gh);
                if isempty(entry)
                    [spec.Location, spec.Label] = latestRelease(gh, api, repo, fetchJson);
                else
                    [spec.Location, spec.Label] = listedRelease(gh, entry, repo);
                end
            elseif ~isempty(tagged)
                release = fetchJson(sprintf('%s/releases/tags/%s', api, tagged.tag));
                [spec.Location, spec.Label] = releaseZip(gh, release, repo);
            elseif ~isempty(tree)
                spec.Location = archiveUrl(gh, 'heads', tree.branch);
                spec.Subfolder = regexprep(char(tree.path), '^/+', '');
                spec.Label = sprintf('%s, branch %s', repo, tree.branch);
                if ~isempty(spec.Subfolder)
                    spec.Label = sprintf('%s, folder %s', spec.Label, spec.Subfolder);
                end
            end
            % Anything else on github.com (an archive or a release asset) is a
            % link to a zip already, and is downloaded as it is.
        end

        function [repos, notice] = available(opts)
        %AVAILABLE  The plugins on offer: every repository of the account
        %   (Plugins.Account) whose name starts with "Alakazam", Alakazam
        %   itself left out, so a new one is offered as soon as it exists.
        %   Malformed ones are listed too, with what is wrong.
        %
        %   REPOS is a struct array, one per repository: .Repo, .Link (its
        %   https address, what installing it fetches), .Description,
        %   .Release (the latest release's tag, '' when it has none), .Version
        %   (that tag without its leading v), .Asset (the release's zip, ''
        %   when it has none, and the source is then installed), .Tools (the
        %   plugins in it: each folder holding <Name>.json and <Name>.m), and
        %   .Problem ('' or why it cannot be installed as it is).
        %
        %   WHERE THE LIST COMES FROM. Without a token GitHub answers 60
        %   requests an hour from one network address, shared by everyone
        %   behind it, and the list costs one request for the account's
        %   repositories and two for each of them (its files and its latest
        %   release): 23 for eleven repositories. So GitHub is asked last:
        %     1. the list already had this session;
        %     2. the newer of the plugin index (Plugins.IndexAddress) and the
        %        list saved on this computer (Plugins.listingFile), when it is
        %        less than MaxAge old. The index is GitHub's own answers to
        %        those same requests, saved every day on Alakazam's web site
        %        by its Manual site workflow and read here exactly as GitHub's
        %        would be: one request, to a site without that limit;
        %     3. GitHub itself, unless it refused until a time not yet come;
        %     4. the newer of the index and the saved list, however old.
        %   REFRESH asks GitHub first, then falls back to 4. When GitHub
        %   refuses for its limit (GitHubRateLimit), the time it takes
        %   requests again is saved, and it is not asked before then, in this
        %   session or another. A token in the environment variable
        %   GITHUB_TOKEN raises the limit to 5,000 an hour.
        %
        %   NOTICE says where the list comes from when it is not GitHub's
        %   answer just now ('' when it is), and why, in the words Install
        %   plugins shows.
        %
        %   Name-value options: Refresh; Account; Session (false: start
        %   without the list had this session, as a new session would); and,
        %   for the tests, FetchJson (@(url) the decoded JSON at URL) and
        %   FetchIndex (@(account) the decoded index, [] when there is none).
            arguments
                opts.Refresh (1, 1) logical = false
                opts.Account = Plugins.Account
                opts.Session (1, 1) logical = true
                opts.FetchJson = @defaultFetchJson
                opts.FetchIndex = @defaultFetchIndex
            end
            account = char(opts.Account);
            had = sessionListing();
            if ~opts.Refresh && opts.Session && isstruct(had) && strcmp(had.account, account)
                repos = had.repos;
                notice = had.notice;
                return;
            end

            saved = readListing();
            savedList = [];
            blockedUntil = NaT;
            if isstruct(saved)
                blockedUntil = saved.blockedUntil;
                if strcmp(saved.account, account)
                    savedList = struct('repos', {saved.repos}, 'fetched', saved.fetched, ...
                        'source', saved.source, 'fromDisk', true);
                end
            end
            refusal = [];
            index = [];
            if opts.Refresh
                [listing, refusal] = askGitHub(account, opts.FetchJson, blockedUntil);
            else
                index = fromIndex(account, opts.FetchIndex);
                listing = newer(index, savedList);
                if isempty(listing) || ~(datetime('now') - listing.fetched < Plugins.MaxAge)
                    [listing, refusal] = askGitHub(account, opts.FetchJson, blockedUntil);
                end
            end
            if isa(refusal, 'GitHubRateLimit')
                blockedUntil = refusal.ResetTime;
            end
            if isempty(listing)
                if opts.Refresh
                    index = fromIndex(account, opts.FetchIndex);
                end
                listing = newer(index, savedList);
            end
            if isempty(listing)
                saveBlock(saved, blockedUntil);
                throw(refusal);
            end

            repos = listing.repos;
            notice = noticeOf(listing, refusal);
            if ~listing.fromDisk
                writeListing(account, listing, blockedUntil);
            else
                saveBlock(saved, blockedUntil);
            end
            sessionListing(struct('account', account, 'repos', repos, 'notice', notice));
        end

        function repos = listed()
        %LISTED  The list Install plugins showed last: had this session, or
        %   saved on this computer. Asks nothing of the network; empty when
        %   there is none. Installing a repository it lists takes the
        %   release it lists (Plugins.prepare), without asking GitHub.
            repos = emptyRepos();
            had = sessionListing();
            if isstruct(had) && strcmp(had.account, Plugins.Account)
                repos = had.repos;
                return;
            end
            saved = readListing();
            if isstruct(saved) && strcmp(saved.account, Plugins.Account)
                repos = saved.repos;
            end
        end

        function file = listingFile()
        %LISTINGFILE  Where the list of plugins on offer is saved between
        %   sessions, with the time GitHub takes requests again when it has
        %   refused: beside the installed plugins.
            file = fullfile(Plugins.folder(), 'plugin-listing.json');
        end

        function repo = providerOf(transformId, repos)
        %PROVIDEROF  The entry of REPOS (Plugins.available) whose repository
        %   holds the plugin TRANSFORMID, or [] when none does.
            repo = [];
            for k = 1:numel(repos)
                if any(strcmp(repos(k).Tools, char(transformId)))
                    repo = repos(k);
                    return;
                end
            end
        end

        function url = pagesAddress(link)
        %PAGESADDRESS  The GitHub Pages address of the repository LINK points
        %   to (https://github.com/owner/repo, with or without .git or a path
        %   after it): https://owner.github.io/repo/, where every plugin of
        %   the account keeps its manual. '' for a link that is not a GitHub
        %   repository's (a zip file, another site).
            url = '';
            parts = regexp(char(string(link)), ...
                '^https?://(?:www\.)?github\.com/([^/\s?#]+)/([^/\s?#]+)', 'tokens', 'once');
            if isempty(parts)
                return;
            end
            repo = regexprep(parts{2}, '\.git$', '');
            url = sprintf('https://%s.github.io/%s/', lower(parts{1}), repo);
        end

        function text = notAPluginMessage(repo, detail)
        %NOTAPLUGINMESSAGE  What installing REPO, a repository that turned out
        %   not to hold a plugin, says: warmly, since it is nobody's fault
        %   here, and with what was missing (DETAIL).
            text = sprintf([ ...
                'Oh, I am so very sorry! I went off to fetch %s for you with the greatest of ' ...
                'pleasure, but it turns out it is not quite a plugin yet: %s. Please do not ' ...
                'worry in the slightest, as nothing has been installed or changed, and this is ' ...
                'not your doing at all. Its author may well still be putting the finishing ' ...
                'touches to it. A plugin is a folder holding <Name>.json, its manifest, and ' ...
                '<Name>.m, its entry function, as each tool on the Tools tab is. It would be a ' ...
                'delight to try again once it has one. Thank you ever so much for your ' ...
                'patience, and do have a lovely day!'], repo, detail);
        end
    end

    methods (Static, Hidden)
        function limit = rateLimitOf(err, askLimit)
        %RATELIMITOF  A GitHubRateLimit when ERR is GitHub refusing a request
        %   for its rate limit, else []. A 403 or 429 is one when GitHub's
        %   /rate_limit (ASKLIMIT, which costs no request) has none left:
        %   until its reset time. Or, with requests left, when the refusal
        %   says "rate limit" itself or is a 429: a limit on bursts, which
        %   GitHub asks to wait a minute out.
            limit = [];
            status = regexp(err.identifier, 'HTTP(403|429)', 'tokens', 'once');
            if isempty(status)
                status = regexp(err.message, 'status (403|429)\>', 'tokens', 'once');
            end
            if isempty(status)
                return;
            end
            try
                info = askLimit();
                core = info.resources.core;
                if double(core.remaining) == 0
                    reset = datetime(double(core.reset), 'ConvertFrom', 'posixtime', 'TimeZone', 'local');
                    reset.TimeZone = '';
                    limit = GitHubRateLimit(reset);
                    return;
                end
            catch
                % No answer from /rate_limit either: judged by the refusal alone.
            end
            if strcmp(status{1}, '429') || contains(lower(err.message), 'rate limit')
                limit = GitHubRateLimit(datetime('now') + minutes(1));
            end
        end
    end
end

function tools = toolsInTree(tree)
%TOOLSINTREE  The plugins in a repository's file tree (GitHub's git/trees,
%   recursive): each folder X holding X.json and X.m.
    tools = {};
    if ~isstruct(tree) || ~isfield(tree, 'tree')
        return;
    end
    entries = asCells(tree.tree);
    paths = cellfun(@(e) char(string(e.path)), entries, 'UniformOutput', false);
    for k = 1:numel(paths)
        parts = regexp(paths{k}, '(?:^|/)([A-Za-z]\w*)/\1\.json$', 'tokens', 'once');
        if isempty(parts)
            continue;
        end
        entry = regexprep(paths{k}, '\.json$', '.m');
        if any(strcmp(paths, entry)) && ~any(strcmp(tools, parts{1}))
            tools{end + 1} = parts{1}; %#ok<AGROW>
        end
    end
end

function name = zipAsset(release)
%ZIPASSET  The name of a release's .zip asset, '' when it has none.
    name = '';
    if ~isfield(release, 'assets') || isempty(release.assets)
        return;
    end
    assets = asCells(release.assets);
    names = cellfun(@(a) char(string(a.name)), assets, 'UniformOutput', false);
    hit = find(endsWith(names, '.zip', 'IgnoreCase', true), 1);
    if ~isempty(hit)
        name = names{hit};
    end
end

function c = asCells(x)
%ASCELLS  A decoded JSON array as a row cell, whether jsondecode made it a
%   struct array (all elements alike) or a cell (they differ).
    if isempty(x)
        c = {};
    elseif iscell(x)
        c = reshape(x, 1, []);
    else
        c = reshape(num2cell(x), 1, []);
    end
end

% ======================================================================= %
% The list on offer: from GitHub, the plugin index, or saved here
% ======================================================================= %
function repos = emptyRepos()
    repos = struct('Repo', {}, 'Link', {}, 'Description', {}, 'Release', {}, ...
        'Version', {}, 'Asset', {}, 'Tools', {}, 'Problem', {});
end

function repos = listFrom(account, fetchJson)
%LISTFROM  The account's Alakazam repositories, from GitHub's answers as
%   FETCHJSON gives them: GitHub itself, or the plugin index. A refusal for
%   GitHub's limit, or a question the index has no answer to, ends it: a
%   list half made of errors would be worse than the last whole one.
    repos = emptyRepos();
    listing = {};
    for page = 1:10
        batch = fetchJson(sprintf( ...
            'https://api.github.com/users/%s/repos?per_page=100&page=%d', account, page));
        batch = asCells(batch);
        listing = [listing, batch]; %#ok<AGROW>
        if numel(batch) < 100
            break;
        end
    end
    for k = 1:numel(listing)
        r = listing{k};
        name = char(string(r.name));
        if ~startsWith(name, 'Alakazam') || strcmp(name, 'Alakazam')
            continue;
        end
        entry = struct('Repo', name, 'Link', sprintf('https://github.com/%s/%s', account, name), ...
            'Description', textField(r, 'description', ''), 'Release', '', 'Version', '', ...
            'Asset', '', 'Tools', {{}}, 'Problem', '');
        api = sprintf('https://api.github.com/repos/%s/%s', account, name);
        try
            branch = textField(r, 'default_branch', 'main');
            tree = fetchJson(sprintf('%s/git/trees/%s?recursive=1', api, branch));
            entry.Tools = toolsInTree(tree);
        catch err
            endsTheList(err);
            entry.Problem = sprintf('its files could not be read (%s)', err.message);
        end
        try
            release = fetchJson([api '/releases/latest']);
            entry.Release = char(string(release.tag_name));
            entry.Version = regexprep(entry.Release, '^[vV]', '');
            entry.Asset = zipAsset(release);
        catch err
            endsTheList(err);
            if ~contains(err.message, '404') && ~contains(err.identifier, '404') ...
                    && isempty(entry.Problem)
                entry.Problem = sprintf('its releases could not be read (%s)', err.message);
            end
        end
        if isempty(entry.Problem) && isempty(entry.Tools)
            entry.Problem = ['it holds no plugin: no folder with <Name>.json and ' ...
                '<Name>.m beside it'];
        end
        repos(end + 1) = entry; %#ok<AGROW>
    end
    [~, order] = sort(lower({repos.Repo}));
    repos = repos(order);
end

function endsTheList(err)
%ENDSTHELIST  Throw ERR again when it is about the whole list, not one
%   repository: GitHub's limit, or an index without the answer.
    if isa(err, 'GitHubRateLimit') || strcmp(err.identifier, 'Alakazam:Plugins:notInIndex')
        throw(err);
    end
end

function [listing, refusal] = askGitHub(account, fetchJson, blockedUntil)
%ASKGITHUB  The list from GitHub itself, or [] and why not (REFUSAL): a
%   GitHubRateLimit when its limit is used up, and without asking at all
%   while BLOCKEDUNTIL, the time it named before, has not come.
    listing = [];
    refusal = [];
    if ~isnat(blockedUntil) && blockedUntil > datetime('now')
        refusal = GitHubRateLimit(blockedUntil);
        return;
    end
    try
        repos = listFrom(account, fetchJson);
    catch err
        refusal = err;
        return;
    end
    listing = struct('repos', {repos}, 'fetched', datetime('now'), 'source', 'github', ...
        'fromDisk', false);
end

function listing = fromIndex(account, fetchIndex)
%FROMINDEX  The list from the plugin index, GitHub's answers saved: [] when
%   there is none, it is another account's, or it lacks an answer the list
%   needs.
    listing = [];
    try
        index = fetchIndex(account);
        if ~isstruct(index) || ~all(isfield(index, {'account', 'generated', 'responses'})) ...
                || ~strcmpi(char(string(index.account)), account)
            return;
        end
        responses = asCells(index.responses);
        urls = cellfun(@(r) char(string(r.url)), responses, 'UniformOutput', false);
        repos = listFrom(account, @(url) answerIn(url, urls, responses));
        listing = struct('repos', {repos}, 'fetched', utcTime(index.generated), ...
            'source', 'index', 'fromDisk', false);
    catch
        listing = [];
    end
end

function data = answerIn(url, urls, responses)
%ANSWERIN  The index's answer to URL as GitHub gave it: the body, or the
%   error a 404 would be.
    k = find(strcmp(urls, url), 1);
    if isempty(k)
        throw(MException('Alakazam:Plugins:notInIndex', 'The plugin index has no answer for %s.', url));
    end
    status = double(responses{k}.status);
    if status == 404
        throw(MException('Alakazam:Plugins:HTTP404', 'Not Found (404): %s', url));
    elseif status ~= 200
        throw(MException('Alakazam:Plugins:notInIndex', 'The plugin index has status %d for %s.', ...
            status, url));
    end
    data = responses{k}.body;
end

function listing = newer(a, b)
%NEWER  Of two lists, either of them [], the one GitHub gave later.
    if isempty(a)
        listing = b;
    elseif isempty(b) || ~(b.fetched > a.fetched)
        listing = a;
    else
        listing = b;
    end
end

function text = noticeOf(listing, refusal)
%NOTICEOF  Where the list comes from, when it is not GitHub's answer just
%   now, and why.
    text = '';
    if isempty(refusal) && strcmp(listing.source, 'github') && ~listing.fromDisk
        return;
    end
    if strcmp(listing.source, 'index')
        text = sprintf('The list is Alakazam''s plugin index of %s.', whenText(listing.fetched));
    else
        text = sprintf('The list is the one GitHub gave %s.', whenText(listing.fetched));
    end
    if isempty(refusal)
        text = [text ' Refresh asks GitHub itself.'];
    elseif isa(refusal, 'GitHubRateLimit')
        text = sprintf('%s. %s', refusal.message, text);
    else
        text = sprintf('GitHub could not be asked just now (%s). %s', refusal.message, text);
    end
end

function text = whenText(t)
%WHENTEXT  A time as the notice says it: today at 14:32, yesterday at
%   09:05, or 3 Oct 2026 at 18:00.
    day = dateshift(t, 'start', 'day');
    today = dateshift(datetime('now'), 'start', 'day');
    clock = char(t, 'HH:mm', 'en_GB');
    if day == today
        text = ['today at ' clock];
    elseif day == today - caldays(1)
        text = ['yesterday at ' clock];
    else
        text = [char(t, 'd MMM yyyy', 'en_GB') ' at ' clock];
    end
end

function value = sessionListing(newValue)
%SESSIONLISTING  The list had this session (account, repos, notice), or []:
%   set with an argument, read without.
    persistent kept
    if nargin
        kept = newValue;
    end
    value = kept;
end

function saved = readListing()
%READLISTING  The list saved on this computer (Plugins.listingFile): the
%   account, when GitHub gave it, from where ('github' or 'index'), until
%   when GitHub refuses requests (NaT when it does not), and the repos; []
%   when there is none or it cannot be read.
    saved = [];
    file = Plugins.listingFile();
    if ~isfile(file)
        return;
    end
    try
        raw = jsondecode(fileread(file));
        saved = struct('account', char(string(raw.account)), 'fetched', isoTime(raw.fetched), ...
            'source', char(string(raw.source)), 'blockedUntil', isoTime(raw.blockedUntil), ...
            'repos', {normaliseRepos(raw.repos)});
    catch
        saved = [];
    end
end

function writeListing(account, listing, blockedUntil)
%WRITELISTING  Save LISTING (repos, fetched, source) for ACCOUNT, with the
%   time GitHub takes requests again. Not being able to write it only means
%   the next session asks again.
    if ~isnat(blockedUntil) && blockedUntil <= datetime('now')
        blockedUntil = NaT;
    end
    record = struct('format', 1, 'account', account, 'fetched', isoText(listing.fetched), ...
        'source', listing.source, 'blockedUntil', isoText(blockedUntil), 'repos', {listing.repos});
    try
        file = Plugins.listingFile();
        folder = fileparts(file);
        if ~isfolder(folder)
            mkdir(folder);
        end
        fid = fopen(file, 'w');
        if fid < 0
            return;
        end
        closeFile = onCleanup(@() fclose(fid));
        fwrite(fid, unicode2native(jsonencode(record, 'PrettyPrint', true), 'UTF-8'));
    catch
    end
end

function saveBlock(saved, blockedUntil)
%SAVEBLOCK  Save the time GitHub takes requests again with the list saved
%   (SAVED, or none), when it is new.
    if isnat(blockedUntil) || (isstruct(saved) && saved.blockedUntil == blockedUntil)
        return;
    end
    if isstruct(saved)
        writeListing(saved.account, saved, blockedUntil);
    else
        writeListing('', struct('fetched', NaT, 'source', '', 'repos', {emptyRepos()}), blockedUntil);
    end
end

function repos = normaliseRepos(raw)
%NORMALISEREPOS  Repositories read back from JSON as Plugins.available
%   makes them: text as char, Tools a row cell even of one tool or none.
    repos = emptyRepos();
    for r = asCells(raw)
        e = r{1};
        tools = {};
        if isfield(e, 'Tools') && ~isempty(e.Tools)
            tools = reshape(cellstr(string(e.Tools)), 1, []);
        end
        repos(end + 1) = struct('Repo', textField(e, 'Repo', ''), 'Link', textField(e, 'Link', ''), ...
            'Description', textField(e, 'Description', ''), 'Release', textField(e, 'Release', ''), ...
            'Version', textField(e, 'Version', ''), 'Asset', textField(e, 'Asset', ''), ...
            'Tools', {tools}, 'Problem', textField(e, 'Problem', '')); %#ok<AGROW>
    end
end

function text = isoText(t)
    text = '';
    if ~isnat(t)
        text = char(t, 'yyyy-MM-dd''T''HH:mm:ss');
    end
end

function t = isoTime(text)
    t = NaT;
    text = char(string(text));
    if ~isempty(text)
        t = datetime(text, 'InputFormat', 'yyyy-MM-dd''T''HH:mm:ss');
    end
end

function t = utcTime(text)
%UTCTIME  A time GitHub writes (UTC, ending in Z) as the clock here shows it.
    t = datetime(char(string(text)), 'InputFormat', 'yyyy-MM-dd''T''HH:mm:ss''Z''', 'TimeZone', 'UTC');
    t.TimeZone = 'local';
    t.TimeZone = '';
end

function entry = listedEntry(known, gh)
%LISTEDENTRY  KNOWN's entry for the repository of the link GH when it lists
%   a release whose download address can be written from it; [] otherwise.
    entry = [];
    if isempty(known) || ~isfield(known, 'Link')
        return;
    end
    plain = @(s) ~isempty(regexp(s, '^[\w.\-]+$', 'once'));
    link = sprintf('https://github.com/%s/%s', gh.owner, gh.repo);
    for k = 1:numel(known)
        e = known(k);
        if strcmpi(e.Link, link) && plain(e.Release) && (isempty(e.Asset) || plain(e.Asset))
            entry = e;
            return;
        end
    end
end

function [location, label] = listedRelease(gh, entry, repo)
%LISTEDRELEASE  The release a listed repository's entry names, as
%   RELEASEZIP takes it from GitHub's answer: its .zip asset (at GitHub's
%   download address for it), else the source at its tag.
    tag = entry.Release;
    if isempty(entry.Asset)
        location = archiveUrl(gh, 'tags', tag);
        label = sprintf('%s, release %s', repo, tag);
    else
        location = sprintf('https://github.com/%s/%s/releases/download/%s/%s', ...
            gh.owner, gh.repo, tag, entry.Asset);
        label = sprintf('%s, release %s (%s)', repo, tag, entry.Asset);
    end
end

% ======================================================================= %
% Manifests and the registry
% ======================================================================= %
function m = readManifest(folder, name)
%READMANIFEST  FOLDER/NAME.json decoded, or an empty struct when it is not
%   there or is not JSON.
    m = struct([]);
    file = fullfile(folder, [name '.json']);
    if ~isfile(file)
        return;
    end
    try
        m = jsondecode(fileread(file));
    catch
        m = struct([]);
    end
end

function t = textField(m, field, default)
%TEXTFIELD  M.FIELD as text, or DEFAULT when it is absent or empty. A
%   numeric Version (1.2 written without quotes) is shown as written.
    t = default;
    if isstruct(m) && isfield(m, field) && ~isempty(m.(field))
        value = m.(field);
        if isnumeric(value)
            t = num2str(value);
        else
            t = char(string(value));
        end
    end
end

function link = candidateLink(candidate)
%CANDIDATELINK  The link a candidate was fetched from, '' for a zip file.
    link = '';
    if isfield(candidate, 'Link')
        link = candidate.Link;
    end
end

function link = linkOf(record)
%LINKOF  Where a plugin can be fetched again: the link it was installed
%   from, or, for one recorded before links were, the GitHub repository its
%   source names ("github.com/owner/repo, release ...").
    link = record.link;
    if isempty(link)
        gh = regexp(record.source, '^github\.com/([^/,\s]+)/([^/,\s]+)', 'tokens', 'once');
        if ~isempty(gh)
            link = sprintf('https://github.com/%s/%s', gh{1}, gh{2});
        elseif startsWith(record.source, 'https://')
            link = record.source;
        end
    end
end

function registry = readRegistry(root)
%READREGISTRY  The record of where each plugin came from, as a struct array
%   with .name, .source, .version and .installed.
    registry = struct('name', {}, 'source', {}, 'version', {}, 'installed', {}, 'link', {});
    file = fullfile(root, Plugins.RegistryFile);
    if ~isfile(file)
        return;
    end
    try
        decoded = jsondecode(fileread(file));
    catch
        return;   % unreadable: treated as empty, and rewritten on the next install
    end
    for k = 1:numel(decoded)
        r = decoded(k);
        registry(end + 1) = struct('name', char(string(r.name)), ...
            'source', textField(r, 'source', ''), 'version', textField(r, 'version', ''), ...
            'installed', textField(r, 'installed', ''), 'link', textField(r, 'link', '')); %#ok<AGROW>
    end
end

function record = registryRecord(registry, name)
    record = struct('name', name, 'source', '', 'version', '', 'installed', '', 'link', '');
    hit = find(strcmp({registry.name}, name), 1);
    if ~isempty(hit)
        record = registry(hit);
    end
end

function registry = setRecord(registry, name, source, version, link)
    if nargin < 5
        link = '';
    end
    record = struct('name', name, 'source', source, 'version', version, ...
        'installed', char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm')), 'link', link);
    hit = find(strcmp({registry.name}, name), 1);
    if isempty(hit)
        registry(end + 1) = record;
    else
        registry(hit) = record;
    end
end

function writeRegistry(root, registry)
    file = fullfile(root, Plugins.RegistryFile);
    if isempty(registry)
        text = '[]';
    else
        text = jsonencode(num2cell(registry), 'PrettyPrint', true);
    end
    fid = fopen(file, 'w', 'n', 'UTF-8');
    if fid < 0
        throw(MException('Alakazam:Plugins:registry', ...
            'I am afraid I could not write %s.', file));
    end
    closeFile = onCleanup(@() fclose(fid));
    fwrite(fid, unicode2native(text, 'UTF-8'));
end

% ======================================================================= %
% Fetching and unpacking
% ======================================================================= %
function defaultDownload(url, file)
    websave(file, url, weboptions('Timeout', 300));
end

function data = defaultFetchJson(url)
%DEFAULTFETCHJSON  GitHub's API, with the token in GITHUB_TOKEN when there
%   is one: it raises the limit of 60 requests an hour to 5,000. A refusal
%   for the limit is thrown as a GitHubRateLimit, saying when it lifts.
    headers = {'Accept', 'application/vnd.github+json'; 'User-Agent', 'Alakazam'};
    token = getenv('GITHUB_TOKEN');
    if ~isempty(token)
        headers(end + 1, :) = {'Authorization', ['Bearer ' token]};
    end
    options = weboptions('ContentType', 'json', 'Timeout', 30, 'HeaderFields', headers);
    try
        data = webread(url, options);
    catch err
        limit = Plugins.rateLimitOf(err, @() webread('https://api.github.com/rate_limit', options));
        if isempty(limit)
            rethrow(err);
        end
        throw(limit);
    end
end

function index = defaultFetchIndex(account)
%DEFAULTFETCHINDEX  The plugin index on Alakazam's web site, which is about
%   Plugins.Account's repositories only; [] when it cannot be had.
    index = [];
    if ~strcmpi(account, Plugins.Account)
        return;
    end
    try
        index = webread(Plugins.IndexAddress, weboptions('ContentType', 'json', 'Timeout', 15));
    catch
        index = [];
    end
end

function [location, label] = latestRelease(gh, api, repo, fetchJson)
%LATESTRELEASE  The repository's latest release, or its default branch when
%   it has none (GitHub answers 404 for a repository without releases).
    try
        release = fetchJson([api '/releases/latest']);
    catch err
        if ~contains(err.identifier, '404') && ~contains(err.message, '404')
            rethrow(err);
        end
        info = fetchJson(api);
        location = archiveUrl(gh, 'heads', char(info.default_branch));
        label = sprintf('%s, branch %s (it has no release)', repo, char(info.default_branch));
        return;
    end
    [location, label] = releaseZip(gh, release, repo);
end

function [location, label] = releaseZip(gh, release, repo)
%RELEASEZIP  A release's own .zip asset when it has one (a packaged plugin),
%   else the source of the repository at the release's tag.
    tag = char(release.tag_name);
    location = '';
    if isfield(release, 'assets') && ~isempty(release.assets)
        assets = release.assets;
        if iscell(assets)
            assets = [assets{:}];
        end
        names = arrayfun(@(a) char(a.name), assets, 'UniformOutput', false);
        hit = find(endsWith(names, '.zip', 'IgnoreCase', true), 1);
        if ~isempty(hit)
            location = char(assets(hit).browser_download_url);
            label = sprintf('%s, release %s (%s)', repo, tag, names{hit});
        end
    end
    if isempty(location)
        location = archiveUrl(gh, 'tags', tag);
        label = sprintf('%s, release %s', repo, tag);
    end
end

function url = archiveUrl(gh, kind, ref)
    url = sprintf('https://github.com/%s/%s/archive/refs/%s/%s.zip', gh.owner, gh.repo, kind, ref);
end

function requireZip(file, label)
%REQUIREZIP  Refuse a download that is not a zip file (a web page saved in
%   its place, typically) before trying to unpack it.
    fid = fopen(file, 'r');
    if fid < 0
        throw(MException('Alakazam:Plugins:notZip', 'I am afraid %s could not be read.', label));
    end
    magic = fread(fid, 4, '*uint8')';
    fclose(fid);
    if numel(magic) < 4 || ~isequal(magic(1:2), uint8('PK'))
        throw(MException('Alakazam:Plugins:notZip', ...
            ['I am afraid %s is not a zip file. A link has to lead to the zip itself, ' ...
             'or to a GitHub repository, release or folder.'], label));
    end
end

function safeUnzip(zipFile, destination, label)
%SAFEUNZIP  Unpack ZIPFILE into DESTINATION, refusing first an archive with
%   an entry that would land outside it ("zip slip": an absolute path, a
%   drive, or a .. step), since unpacking is the one step that writes to
%   disk before anything has been checked.
    archive = java.util.zip.ZipFile(java.io.File(zipFile));
    closeArchive = onCleanup(@() archive.close());
    entries = archive.entries();
    while entries.hasMoreElements()
        name = char(entries.nextElement().getName());
        parts = strsplit(strrep(name, '\', '/'), '/');
        if startsWith(name, {'/', '\'}) || contains(name, ':') || any(strcmp(parts, '..'))
            throw(MException('Alakazam:Plugins:unsafeZip', ...
                ['I am afraid %s was refused: it holds "%s", which would be written ' ...
                 'outside the folder it is unpacked into.'], label, name));
        end
    end
    clear closeArchive
    unzip(zipFile, destination);
end

function found = findPlugins(unpacked, subfolder)
%FINDPLUGINS  Every plugin under UNPACKED: a folder holding S.json and S.m,
%   whose manifest's Entry is S.m. The folder's own name does not have to be
%   S, which is what lets a GitHub archive's top folder (repo-main) be the
%   plugin. A plugin's own subfolders are not searched, and macOS's
%   __MACOSX folder never is.
    found = struct('Name', {}, 'Folder', {});
    base = unpacked;
    if ~isempty(subfolder)
        tops = dir(unpacked);
        tops = tops([tops.isdir] & ~ismember({tops.name}, {'.', '..', '__MACOSX'}));
        if isscalar(tops)
            base = fullfile(unpacked, tops(1).name, subfolder);
        else
            base = fullfile(unpacked, subfolder);
        end
        if ~isfolder(base)
            return;
        end
    end
    found = search(base, 0, found);
end

function found = search(folder, depth, found)
    files = dir(fullfile(folder, '*.json'));
    for k = 1:numel(files)
        [~, stem] = fileparts(files(k).name);
        if isvarname(stem) && isfile(fullfile(folder, [stem '.m']))
            m = readManifest(folder, stem);
            if isstruct(m) && ~isempty(m) && strcmp(textField(m, 'Entry', ''), [stem '.m'])
                found(end + 1) = struct('Name', stem, 'Folder', folder); %#ok<AGROW>
                return;   % a plugin's own folders are its business
            end
        end
    end
    if depth >= 3
        return;
    end
    subs = dir(folder);
    subs = subs([subs.isdir] & ~ismember({subs.name}, {'.', '..', '__MACOSX'}));
    for k = 1:numel(subs)
        found = search(fullfile(folder, subs(k).name), depth + 1, found);
    end
end

% ======================================================================= %
% Checking a plugin
% ======================================================================= %
function p = checkPlugin(f, builtInRoot)
%CHECKPLUGIN  What installing the plugin F would do, and whether it may.
    name = f.Name;
    m = readManifest(f.Folder, name);
    p = struct('Name', name, 'Label', textField(m, 'Name', name), ...
        'Version', textField(m, 'Version', ''), ...
        'Description', textField(m, 'Description', ''), ...
        'Folder', f.Folder, 'Files', countFiles(f.Folder), 'Replaces', '', ...
        'Problems', {{}}, 'Warnings', {{}});

    missing = Plugins.ManifestFields(~cellfun(@(k) ~isempty(textField(m, k, '')), ...
        Plugins.ManifestFields));
    if ~isempty(missing)
        p.Problems{end + 1} = sprintf('Its manifest lacks %s.', strjoin(missing, ', '));
    end
    if isfolder(fullfile(builtInRoot, name))
        p.Problems{end + 1} = sprintf('Alakazam already has a transformation called %s.', name);
    end
    installedHere = fullfile(Plugins.folder(), name);
    if isempty(p.Problems)
        existing = which(name);
        if ~isempty(existing) && ~startsWith(existing, [installedHere filesep])
            p.Problems{end + 1} = sprintf(['A function called %s is already on the path ' ...
                '(%s); the plugin''s entry function would hide it or be hidden by it.'], ...
                name, existing);
        end
    end
    if isfolder(installedHere)
        old = readManifest(installedHere, name);
        p.Replaces = textField(old, 'Version', 'the installed version');
    end

    icon = textField(m, 'Icon', '');
    if isempty(p.Problems) && (isempty(icon) || ~isfile(fullfile(f.Folder, icon)))
        p.Warnings{end + 1} = 'Its icon is missing, so its button will have none.';
    end
    if isstruct(m) && isfield(m, 'Requires') && ~isempty(m.Requires)
        needed = cellstr(string(m.Requires));
        absent = needed(cellfun(@(r) exist(r) == 0, needed)); %#ok<EXIST>
        if ~isempty(absent)
            p.Warnings{end + 1} = sprintf(['It needs %s, not on the path yet; install that ' ...
                'before running it.'], strjoin(absent, ', '));
        end
    end
end

function line = pluginLine(p)
    line = p.Name;
    if ~isempty(p.Version)
        line = sprintf('%s %s', line, p.Version);
    end
    if ~isempty(p.Replaces)
        line = sprintf('%s (replaces %s)', line, p.Replaces);
    end
    description = p.Description;
    if strlength(description) > 160
        description = [extractBefore(description, 158) '...'];
    end
    line = sprintf('%s: %s (%d file%s)', line, description, p.Files, plural(p.Files));
end

function s = plural(n)
    s = '';
    if n ~= 1
        s = 's';
    end
end

function n = countFiles(folder)
    listing = dir(fullfile(folder, '**', '*'));
    n = nnz(~[listing.isdir]);
end

% ======================================================================= %
% The file system
% ======================================================================= %
function copyPlugin(source, destination)
%COPYPLUGIN  Copy the plugin folder SOURCE to DESTINATION. Copied, not moved:
%   the staging folder may be on another drive, and is removed afterwards.
    mkdir(destination);
    [ok, message] = copyfile(fullfile(source, '*'), destination, 'f');
    if ~ok
        removeFolder(destination);
        throw(MException('Alakazam:Plugins:copy', ...
            'I am afraid the plugin could not be copied into %s: %s', destination, message));
    end
end

function takeOffPath(folder)
%TAKEOFFPATH  Remove FOLDER and its subfolders from the path, those that are
%   on it, without warnings for those that are not.
    onPath = strsplit(path, pathsep);
    mine = onPath(strcmp(onPath, folder) | startsWith(onPath, [folder filesep]));
    if ~isempty(mine)
        rmpath(mine{:});
    end
end

function forgetFunction(functionToForget__)
%FORGETFUNCTION  Drop a function from memory, so that the next call reads its
%   file again. A helper of its own, so that clear can never meet a local
%   variable of the plugin's name.
    clear(functionToForget__);
end

function removeFolder(folder)
    if ~isempty(folder) && isfolder(folder)
        [ok, message] = rmdir(folder, 's');
        if ~ok
            warning('Alakazam:Plugins:remove', 'Could not remove %s: %s', folder, message);
        end
    end
end
