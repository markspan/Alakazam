classdef PluginsTest < matlab.unittest.TestCase
%PLUGINSTEST  Installing transformations from a zip file or a link (Plugins):
%   what is found in an archive, what is refused and why, what installing
%   and uninstalling do to the folder, the path and the record, how GitHub
%   links are read, and that the ribbon, the tree, Recalculate and the
%   script exporter find an installed plugin as they find a built-in one.
%
%   Every case works in a temporary plugin folder (ALAKAZAM_PLUGIN_FOLDER),
%   with plugins and archives built on the spot, and no network: links are
%   fetched through the Download and FetchJson seams.
%
%   See also PLUGINS, PLUGINSDIALOG, PLUGINSOURCEDIALOG.

    properties
        Work        % where plugins and zips are built
        PluginRoot  % the plugin folder under test
        BuiltIn     % a stand-in for src/Transformations
    end

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            for p = {fullfile(root, 'src'), fullfile(root, 'src', 'Support'), ...
                     fullfile(root, 'src', 'Dialogs'), fullfile(root, 'src', 'IO'), ...
                     fullfile(root, 'src', 'Transformations')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
        end
    end

    methods (TestMethodSetup)
        function useAPluginFolderOfItsOwn(testCase)
            base = tempname;
            testCase.Work = fullfile(base, 'work');
            testCase.PluginRoot = fullfile(base, 'plugins');
            testCase.BuiltIn = fullfile(base, 'builtin');
            mkdir(testCase.Work);
            mkdir(testCase.BuiltIn);
            was = getenv('ALAKAZAM_PLUGIN_FOLDER');
            setenv('ALAKAZAM_PLUGIN_FOLDER', testCase.PluginRoot);
            testCase.addTeardown(@() cleanUp(base, was));
        end
    end

    methods (Test)
        % ---- finding and installing ------------------------------------
        function installsAPluginFromAZipOfItsFolder(testCase)
            folder = testCase.makePlugin('AlzPlugOne', 'Version', '1.0');
            zipFile = testCase.zipOf(folder, 'folder');

            candidate = Plugins.prepare(zipFile, 'BuiltInRoot', testCase.BuiltIn);
            testCase.verifyEqual({candidate.Plugins.Name}, {'AlzPlugOne'});
            testCase.verifyEmpty(candidate.Plugins.Problems);
            testCase.verifyFalse(isfolder(fullfile(testCase.PluginRoot, 'AlzPlugOne')), ...
                'Preparing must install nothing.');

            names = Plugins.install(candidate);
            testCase.verifyEqual(names, {'AlzPlugOne'});
            installed = fullfile(testCase.PluginRoot, 'AlzPlugOne');
            testCase.verifyTrue(isfile(fullfile(installed, 'AlzPlugOne.m')));
            testCase.verifyTrue(startsWith(which('AlzPlugOne'), installed), 'It is on the path.');
            testCase.verifyFalse(isfolder(candidate.Staging), 'The staging folder is removed.');
            list = Plugins.installed();
            testCase.verifyEqual(list.Name, 'AlzPlugOne');
            testCase.verifyEqual(list.Version, '1.0');
            testCase.verifyEqual(list.Source, zipFile, 'Where it came from is recorded.');
        end

        function aFlatZipIsInstalledUnderItsName(testCase)
            folder = testCase.makePlugin('AlzPlugFlat');
            candidate = Plugins.prepare(testCase.zipOf(folder, 'flat'), 'BuiltInRoot', testCase.BuiltIn);
            Plugins.install(candidate);
            testCase.verifyTrue(isfile(fullfile(testCase.PluginRoot, 'AlzPlugFlat', 'AlzPlugFlat.json')));
        end

        function findsThePluginsInAGitHubArchive(testCase)
        %   A repository archive unpacks into one top folder (repo-main), with
        %   the plugin either at its top or in a folder of its own.
            inner = testCase.makePlugin('AlzPlugInner');
            top = fullfile(testCase.Work, 'repo-main');
            mkdir(fullfile(top, 'plugins'));
            movefile(inner, fullfile(top, 'plugins', 'AlzPlugInner'));
            zipFile = fullfile(testCase.Work, 'repo.zip');
            zip(zipFile, 'repo-main', testCase.Work);
            candidate = Plugins.prepare(zipFile, 'BuiltInRoot', testCase.BuiltIn);
            testCase.verifyEqual({candidate.Plugins.Name}, {'AlzPlugInner'});
            Plugins.discard(candidate);

            whole = testCase.makePlugin('AlzPlugRepo');
            movefile(whole, fullfile(testCase.Work, 'AlzPlugRepo-main'));
            zipFile = fullfile(testCase.Work, 'whole.zip');
            zip(zipFile, 'AlzPlugRepo-main', testCase.Work);
            candidate = Plugins.prepare(zipFile, 'BuiltInRoot', testCase.BuiltIn);
            testCase.verifyEqual({candidate.Plugins.Name}, {'AlzPlugRepo'}, ...
                'The folder''s own name (repo-main) does not have to be the plugin''s.');
            Plugins.install(candidate);
            testCase.verifyTrue(isfile(fullfile(testCase.PluginRoot, 'AlzPlugRepo', 'AlzPlugRepo.m')));
        end

        function installingAgainReplacesAndSaysWhat(testCase)
            Plugins.install(Plugins.prepare(testCase.zipOf( ...
                testCase.makePlugin('AlzPlugTwice', 'Version', '1.0'), 'folder'), ...
                'BuiltInRoot', testCase.BuiltIn));
            rmdir(fullfile(testCase.Work, 'AlzPlugTwice'), 's');
            newer = testCase.makePlugin('AlzPlugTwice', 'Version', '2.0', 'Width', 35);
            candidate = Plugins.prepare(testCase.zipOf(newer, 'folder'), 'BuiltInRoot', testCase.BuiltIn);
            testCase.verifyEmpty(candidate.Plugins.Problems, ...
                'Its own installed version is an update, not a clash.');
            testCase.verifyEqual(candidate.Plugins.Replaces, '1.0');
            testCase.verifyTrue(contains(Plugins.describe(candidate), 'AlzPlugTwice 2.0 (replaces 1.0)'));
            Plugins.install(candidate);
            [~, options] = TransTools.invoke('AlzPlugTwice', struct('data', 1), struct());
            testCase.verifyEqual(options.Width, 35, 'The new version runs, not the one in memory.');
        end

        function aWarningDoesNotStopTheInstall(testCase)
            folder = testCase.makePlugin('AlzPlugWarned', 'Icon', false, ...
                'Requires', {'alzNoSuchToolboxFunction'});
            candidate = Plugins.prepare(testCase.zipOf(folder, 'folder'), 'BuiltInRoot', testCase.BuiltIn);
            plugin = candidate.Plugins;
            testCase.verifyEmpty(plugin.Problems);
            testCase.verifyTrue(any(contains(plugin.Warnings, 'icon')));
            testCase.verifyTrue(any(contains(plugin.Warnings, 'alzNoSuchToolboxFunction')));
            testCase.verifyEqual(Plugins.install(candidate), {'AlzPlugWarned'});
        end

        % ---- refusing ---------------------------------------------------
        function refusesAManifestWithoutItsSixFields(testCase)
            folder = testCase.makePlugin('AlzPlugBare', 'Drop', {'Section', 'Category'});
            candidate = Plugins.prepare(testCase.zipOf(folder, 'folder'), 'BuiltInRoot', testCase.BuiltIn);
            testCase.verifyTrue(contains(strjoin(candidate.Plugins.Problems), 'Section, Category'));
            text = Plugins.describe(candidate);
            testCase.verifyTrue(contains(text, 'Not installed'));
            testCase.verifyFalse(contains(text, 'runs with your rights'), ...
                'Nothing to install, so no warning about installing.');
            testCase.verifyEmpty(Plugins.install(candidate));
            testCase.verifyFalse(isfolder(fullfile(testCase.PluginRoot, 'AlzPlugBare')));
        end

        function refusesTheNameOfABuiltInTransformation(testCase)
            mkdir(fullfile(testCase.BuiltIn, 'AlzPlugTaken'));
            folder = testCase.makePlugin('AlzPlugTaken');
            candidate = Plugins.prepare(testCase.zipOf(folder, 'folder'), 'BuiltInRoot', testCase.BuiltIn);
            testCase.verifyTrue(contains(strjoin(candidate.Plugins.Problems), 'already has a transformation'));
            Plugins.discard(candidate);
        end

        function refusesAnEntryThatWouldHideAFunction(testCase)
            folder = testCase.makePlugin('magic');
            candidate = Plugins.prepare(testCase.zipOf(folder, 'folder'), 'BuiltInRoot', testCase.BuiltIn);
            testCase.verifyTrue(contains(strjoin(candidate.Plugins.Problems), 'already on the path'));
            Plugins.discard(candidate);
        end

        function refusesAZipThatWouldUnpackOutsideItsFolder(testCase)
            zipFile = fullfile(testCase.Work, 'slip.zip');
            craftZip(zipFile, '../AlzEscaped.txt', 'out');
            testCase.verifyError(@() Plugins.prepare(zipFile, 'BuiltInRoot', testCase.BuiltIn), ...
                'Alakazam:Plugins:unsafeZip');
        end

        function refusesWhatIsNotAZip(testCase)
            fake = fullfile(testCase.Work, 'page.zip');
            fid = fopen(fake, 'w');
            fprintf(fid, '<html>Not found</html>');
            fclose(fid);
            testCase.verifyError(@() Plugins.prepare(fake, 'BuiltInRoot', testCase.BuiltIn), ...
                'Alakazam:Plugins:notZip');
        end

        function aZipWithoutAPluginSaysWhatAPluginIs(testCase)
            empty = fullfile(testCase.Work, 'nothing');
            mkdir(empty);
            fid = fopen(fullfile(empty, 'readme.txt'), 'w');
            fprintf(fid, 'hello');
            fclose(fid);
            zipFile = fullfile(testCase.Work, 'nothing.zip');
            zip(zipFile, 'nothing', testCase.Work);
            testCase.verifyError(@() Plugins.prepare(zipFile, 'BuiltInRoot', testCase.BuiltIn), ...
                'Alakazam:Plugins:noPlugin');
        end

        function refusesPlainHttpAndNonsense(testCase)
            testCase.verifyError(@() Plugins.resolveSource('http://example.org/p.zip'), ...
                'Alakazam:Plugins:insecure');
            testCase.verifyError(@() Plugins.resolveSource('not a thing'), ...
                'Alakazam:Plugins:noSource');
        end

        % ---- uninstalling -----------------------------------------------
        function uninstallRemovesTheFolderThePathAndTheRecord(testCase)
            Plugins.install(Plugins.prepare(testCase.zipOf( ...
                testCase.makePlugin('AlzPlugGone'), 'folder'), 'BuiltInRoot', testCase.BuiltIn));
            installed = fullfile(testCase.PluginRoot, 'AlzPlugGone');
            testCase.assertTrue(isfolder(installed));
            Plugins.uninstall('AlzPlugGone');
            testCase.verifyFalse(isfolder(installed));
            testCase.verifyFalse(startsWith(which('AlzPlugGone'), installed));
            testCase.verifyEmpty(Plugins.installed());
            registry = jsondecode(fileread(fullfile(testCase.PluginRoot, 'plugins.json')));
            testCase.verifyEmpty(registry);
            testCase.verifyError(@() Plugins.uninstall('AlzPlugGone'), 'Alakazam:Plugins:notInstalled');
        end

        % ---- links ------------------------------------------------------
        function readsGitHubLinks(testCase)
            withAsset = struct('tag_name', 'v1.2', 'assets', struct( ...
                'name', {'notes.txt', 'Plug-1.2.zip'}, ...
                'browser_download_url', {'https://x/notes.txt', 'https://x/Plug-1.2.zip'}));
            spec = Plugins.resolveSource('https://github.com/me/plug', @(url) withAsset);
            testCase.verifyEqual(spec.Location, 'https://x/Plug-1.2.zip', 'The release''s own zip.');

            bare = struct('tag_name', 'v1.3', 'assets', []);
            spec = Plugins.resolveSource('https://github.com/me/plug.git', @(url) bare);
            testCase.verifyEqual(spec.Location, 'https://github.com/me/plug/archive/refs/tags/v1.3.zip', ...
                'No asset: the source at the release''s tag.');

            spec = Plugins.resolveSource('https://github.com/me/plug/', @noReleaseYet);
            testCase.verifyEqual(spec.Location, 'https://github.com/me/plug/archive/refs/heads/trunk.zip', ...
                'No release: the default branch.');

            asked = {};
            spec = Plugins.resolveSource('https://github.com/me/plug/releases/tag/v2', ...
                @(url) remember(url, bare));
            testCase.verifyEqual(asked{1}, 'https://api.github.com/repos/me/plug/releases/tags/v2');
            testCase.verifyEqual(spec.Location, 'https://github.com/me/plug/archive/refs/tags/v1.3.zip');

            spec = Plugins.resolveSource('https://github.com/me/plug/tree/main/plugins/Plug');
            testCase.verifyEqual(spec.Location, 'https://github.com/me/plug/archive/refs/heads/main.zip');
            testCase.verifyEqual(spec.Subfolder, 'plugins/Plug');

            direct = 'https://github.com/me/plug/releases/download/v1/Plug.zip';
            spec = Plugins.resolveSource(direct);
            testCase.verifyEqual(spec.Location, direct);
            other = 'https://example.org/files/plug.zip';
            spec = Plugins.resolveSource(other);
            testCase.verifyEqual(spec.Location, other);

            function data = remember(url, data)
                asked{end + 1} = url;
            end
        end

        function aLinkToAFolderTakesOnlyThePluginsInIt(testCase)
            top = fullfile(testCase.Work, 'plug-main');
            mkdir(fullfile(top, 'plugins'));
            mkdir(fullfile(top, 'other'));
            movefile(testCase.makePlugin('AlzPlugWanted'), fullfile(top, 'plugins', 'AlzPlugWanted'));
            movefile(testCase.makePlugin('AlzPlugElse'), fullfile(top, 'other', 'AlzPlugElse'));
            archive = fullfile(testCase.Work, 'branch.zip');
            zip(archive, 'plug-main', testCase.Work);

            fetched = {};
            candidate = Plugins.prepare('https://github.com/me/plug/tree/main/plugins', ...
                'BuiltInRoot', testCase.BuiltIn, 'Download', @fetch);
            testCase.verifyEqual(fetched, {'https://github.com/me/plug/archive/refs/heads/main.zip'});
            testCase.verifyEqual({candidate.Plugins.Name}, {'AlzPlugWanted'});
            testCase.verifyTrue(contains(candidate.Source, 'folder plugins'));
            Plugins.discard(candidate);

            function fetch(url, file)
                fetched{end + 1} = url;
                copyfile(archive, file);
            end
        end

        % ---- the rest of the application finds it ----------------------
        function theRibbonScansThePluginsAfterTheBuiltIns(testCase)
            builtIn = testCase.makePluginIn(testCase.BuiltIn, 'AlzShared', 'Version', 'built-in');
            testCase.assertTrue(isfolder(builtIn));
            mkdir(testCase.PluginRoot);
            testCase.makePluginIn(testCase.PluginRoot, 'AlzShared', 'Version', 'plugin');
            testCase.makePluginIn(testCase.PluginRoot, 'AlzOnlyPlugin', 'Version', '0.1');
            infos = testCase.verifyWarning(@() AlakazamRibbon.ScanTransformations( ...
                {testCase.BuiltIn, testCase.PluginRoot}), 'Alakazam:AlakazamRibbon');
            testCase.verifyEqual(sort({infos.Folder}), {'AlzOnlyPlugin', 'AlzShared'});
            shared = infos(strcmp({infos.Folder}, 'AlzShared'));
            testCase.verifyEqual(shared.Version, 'built-in', 'The built-in one wins.');
            testCase.verifyEqual(shared.Root, testCase.BuiltIn);
            testCase.verifyEqual(infos(strcmp({infos.Folder}, 'AlzOnlyPlugin')).Root, testCase.PluginRoot);
            testCase.verifyEqual(Plugins.roots(testCase.BuiltIn), {testCase.BuiltIn, testCase.PluginRoot});
        end

        function theTreeAndTheExporterFindAnInstalledPlugin(testCase)
            Plugins.install(Plugins.prepare(testCase.zipOf( ...
                testCase.makePlugin('AlzPlugFound', 'Width', 27), 'folder'), 'BuiltInRoot', testCase.BuiltIn));
            icon = WorkSpaceTree.iconForResult(struct('Call', 'AlzPlugFound', ...
                'DataType', 'TimeDomain'), testCase.BuiltIn);
            testCase.verifyTrue(startsWith(icon, 'data:image/png;base64,'), 'Its icon in the tree.');
            defaults = transformDefaults('AlzPlugFound', testCase.BuiltIn);
            testCase.verifyEqual(defaults.Width, 27, 'Its defaults in an exported script.');
            [EEG, options] = TransTools.invoke('AlzPlugFound', struct('data', 1), struct());
            testCase.verifyEqual(EEG.data, 1);
            testCase.verifyEqual(options.Width, 27, 'It runs through the one seam every step uses.');
        end

        function aPluginDeclaresItselfRecalculable(testCase)
            Plugins.install(Plugins.prepare(testCase.zipOf( ...
                testCase.makePlugin('AlzPlugAgain', 'Recalculable', true), 'folder'), ...
                'BuiltInRoot', testCase.BuiltIn));
            Plugins.install(Plugins.prepare(testCase.zipOf( ...
                testCase.makePlugin('AlzPlugOnce'), 'folder'), 'BuiltInRoot', testCase.BuiltIn));
            testCase.verifyTrue(WorkSpaceTree.isRecalculable('AlzPlugAgain'));
            testCase.verifyFalse(WorkSpaceTree.isRecalculable('AlzPlugOnce'));
            testCase.verifyTrue(WorkSpaceTree.isRecalculable('Baseline'), 'The built-in list still counts.');
            testCase.verifyFalse(WorkSpaceTree.isRecalculable('Average'));
        end

        % ---- the dialogs ------------------------------------------------
        function theListShowsAndUninstalls(testCase)
            Plugins.install(Plugins.prepare(testCase.zipOf( ...
                testCase.makePlugin('AlzPlugListed', 'Version', '3.1'), 'folder'), ...
                'BuiltInRoot', testCase.BuiltIn));
            asked = {};
            fig = PluginsDialog([], 'Visible', false, ...
                'Confirm', @(message, ~) confirm(message));
            closeFig = onCleanup(@() delete(fig));
            table = findobj(fig, 'Tag', 'PluginTable');
            testCase.verifyEqual(table.Data(1, 1:3), {'AlzPlugListed', 'AlzPlugListed', '3.1'});
            empty = findobj(fig, 'Tag', 'NoPlugins');
            testCase.verifyFalse(logical(empty.Visible));

            table.Selection = 1;
            table.SelectionChangedFcn(table, []);
            button = findobj(fig, 'Tag', 'Uninstall');
            button.ButtonPushedFcn(button, []);
            testCase.verifyTrue(contains(asked{1}, 'Uninstall AlzPlugListed?'));
            testCase.verifyEmpty(Plugins.installed());
            testCase.verifyEmpty(table.Data);
            testCase.verifyTrue(logical(empty.Visible));

            function answer = confirm(message)
                asked{end + 1} = message;
                answer = 'Uninstall';
            end
        end

        function theSourceDialogReturnsTheLink(testCase)
            [~, fig] = PluginSourceDialog([], 'Wait', false);
            closeFig = onCleanup(@() delete(fig));
            field = findobj(fig, 'Tag', 'Link');
            field.Value = '  https://github.com/me/plug  ';
            button = findobj(fig, 'Tag', 'UseLink');
            button.ButtonPushedFcn(button, []);
            testCase.verifyEqual(getappdata(fig, 'Source'), 'https://github.com/me/plug');
        end
    end

    methods (Access = private)
        function folder = makePlugin(testCase, name, varargin)
            folder = testCase.makePluginIn(testCase.Work, name, varargin{:});
        end

        function folder = makePluginIn(~, parent, name, varargin)
        %MAKEPLUGININ  A plugin that follows the contract: it returns its input,
        %   with options carrying Width.
            p = inputParser();
            p.addParameter('Version', '');
            p.addParameter('Width', 20);
            p.addParameter('Icon', true);
            p.addParameter('Requires', {});
            p.addParameter('Recalculable', []);
            p.addParameter('Drop', {});
            p.parse(varargin{:});
            o = p.Results;

            folder = fullfile(parent, name);
            mkdir(folder);
            manifest = struct('Name', name, 'Description', ['A test plugin, ' name '.'], ...
                'Entry', [name '.m'], 'Icon', [name '.png'], 'Section', '1. Preprocessing', ...
                'Category', 'EEG');
            if ~isempty(o.Version)
                manifest.Version = o.Version;
            end
            if ~isempty(o.Requires)
                manifest.Requires = o.Requires;
            end
            if ~isempty(o.Recalculable)
                manifest.Recalculable = o.Recalculable;
            end
            manifest = rmfield(manifest, o.Drop);
            writeText(fullfile(folder, [name '.json']), jsonencode(manifest));
            writeText(fullfile(folder, [name '.m']), strjoin({ ...
                sprintf('function [EEG, options] = %s(input, varargin)', name), ...
                sprintf('    [opts, interactive] = TransTools.InitGuard(nargin, ''Alakazam:%s'', varargin{:});', name), ...
                '    if interactive', ...
                '        options = struct();', ...
                '    else', ...
                '        options = opts;', ...
                '    end', ...
                sprintf('    options.Width = TransTools.FieldOr(options, ''Width'', %d);', o.Width), ...
                '    EEG = input;', ...
                'end'}, newline));
            if o.Icon
                imwrite(uint8(repmat(reshape([74 127 201], 1, 1, 3), 8, 8)), fullfile(folder, [name '.png']));
            end
        end

        function zipFile = zipOf(testCase, folder, layout)
        %ZIPOF  FOLDER zipped as a folder (Name/...) or flat (its files at the top).
            [parent, name] = fileparts(folder);
            zipFile = fullfile(testCase.Work, [name '-' layout '.zip']);
            switch layout
                case 'folder'
                    zip(zipFile, name, parent);
                case 'flat'
                    listing = dir(folder);
                    zip(zipFile, {listing(~[listing.isdir]).name}, folder);
            end
        end
    end
end

% ======================================================================= %
function cleanUp(base, was)
    onPath = strsplit(path, pathsep);
    mine = onPath(startsWith(onPath, base));
    if ~isempty(mine)
        rmpath(mine{:});
    end
    setenv('ALAKAZAM_PLUGIN_FOLDER', was);
    if isfolder(base)
        rmdir(base, 's');
    end
    rehash;
end

function writeText(file, text)
    fid = fopen(file, 'w');
    fwrite(fid, text);
    fclose(fid);
end

function craftZip(file, entryName, content)
%CRAFTZIP  A zip with one entry of the given name, which MATLAB's zip will
%   not write when the name climbs out of its folder.
    stream = java.util.zip.ZipOutputStream(java.io.FileOutputStream(file));
    stream.putNextEntry(java.util.zip.ZipEntry(entryName));
    stream.write(int8(content));
    stream.closeEntry();
    stream.close();
end

function data = noReleaseYet(url)
    if endsWith(url, '/releases/latest')
        throw(MException('Test:HTTP404', 'The server returned the status 404 (Not Found).'));
    end
    data = struct('default_branch', 'trunk');
end
