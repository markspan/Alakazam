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
%   branch when it has no release; a link to a release (.../releases/tag/T)
%   takes that release; and a link to a folder (.../tree/BRANCH/PATH) takes
%   the plugins inside that folder of the branch. Only https is accepted.
%
%   See also ALAKAZAMRIBBON, WORKSPACETREE.ISRECALCULABLE, NEWTRANSFORMATION.

    properties (Constant)
        % The six fields every manifest carries (see DEVELOPER.md).
        ManifestFields = {'Name', 'Description', 'Entry', 'Icon', 'Section', 'Category'}
        RegistryFile = 'plugins.json'
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
                'Description', {}, 'Source', {}, 'Installed', {}, 'Folder', {});
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
                    'Source', record.source, 'Installed', record.installed, ...
                    'Folder', fullfile(root, name)); %#ok<AGROW>
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
        %   check), Download (@(url, file) writes the zip at URL to FILE) and
        %   FetchJson (@(url) the decoded JSON at URL, for GitHub's API).
            arguments
                source
                opts.BuiltInRoot = fullfile(fileparts(mfilename('fullpath')), 'Transformations')
                opts.Download = @defaultDownload
                opts.FetchJson = @defaultFetchJson
            end
            spec = Plugins.resolveSource(source, opts.FetchJson);

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
            candidate = struct('Source', spec.Label, 'Staging', staging, 'Plugins', plugins);
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
                    registry = setRecord(registry, p.Name, candidate.Source, p.Version);
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

        function spec = resolveSource(source, fetchJson)
        %RESOLVESOURCE  What to fetch for SOURCE, and how to describe it.
        %   SPEC.Kind is 'file' (a zip on this computer) or 'url';
        %   .Location the file or the URL of the zip; .Subfolder the folder
        %   inside the archive to look in ('' for all of it); .Label how the
        %   source is named to the user. FETCHJSON (@(url) decoded JSON) is
        %   used for GitHub's API only.
            if nargin < 2
                fetchJson = @defaultFetchJson;
            end
            source = strtrim(char(string(source)));
            spec = struct('Kind', 'url', 'Location', source, 'Subfolder', '', 'Label', source);
            if isempty(source)
                throw(MException('Alakazam:Plugins:noSource', ...
                    'I am afraid no zip file or link was given.'));
            end
            if isfile(source)
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
                [spec.Location, spec.Label] = latestRelease(gh, api, repo, fetchJson);
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

function registry = readRegistry(root)
%READREGISTRY  The record of where each plugin came from, as a struct array
%   with .name, .source, .version and .installed.
    registry = struct('name', {}, 'source', {}, 'version', {}, 'installed', {});
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
            'installed', textField(r, 'installed', '')); %#ok<AGROW>
    end
end

function record = registryRecord(registry, name)
    record = struct('name', name, 'source', '', 'version', '', 'installed', '');
    hit = find(strcmp({registry.name}, name), 1);
    if ~isempty(hit)
        record = registry(hit);
    end
end

function registry = setRecord(registry, name, source, version)
    record = struct('name', name, 'source', source, 'version', version, ...
        'installed', char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm')));
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
    data = webread(url, weboptions('ContentType', 'json', 'Timeout', 30, ...
        'HeaderFields', {'Accept', 'application/vnd.github+json'; 'User-Agent', 'Alakazam'}));
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
