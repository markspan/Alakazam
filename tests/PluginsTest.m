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
                     fullfile(root, 'src', 'Transformations'), fullfile(root, 'tests', 'fixtures')}
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

        function aLinkMatlabCanReachIsStillALink(testCase)
        %ALINKMATLABCANREACHISSTILLALINK  isfile answers true for an https
        %   address it can reach (R2026a does), so a link to a real
        %   repository was taken for a zip on this computer, and GitHub's web
        %   page was read as one: no plugin installed from a real link. The
        %   made-up links above cannot be reached, which is why they never
        %   showed it. Runs only where the trap is there to fall into.
            link = 'https://github.com/markspan/Alakazam';
            testCase.assumeTrue(isfile(link), ['isfile does not take this link for a file ' ...
                'here (an older MATLAB, or no network), so there is nothing to fall into.']);
            withAsset = struct('tag_name', 'v1', 'assets', struct('name', {'Plug-1.zip'}, ...
                'browser_download_url', {'https://x/Plug-1.zip'}));

            spec = Plugins.resolveSource(link, @(url) withAsset);

            testCase.verifyEqual(spec.Kind, 'url');
            testCase.verifyEqual(spec.Location, 'https://x/Plug-1.zip');
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
            fig = PluginsDialog([], 'Visible', false, 'Repos', PluginsTest.noRepos(), ...
                'Confirm', @(message, ~) confirm(message));
            closeFig = onCleanup(@() delete(fig));
            table = findobj(fig, 'Tag', 'PluginTable');
            testCase.verifyEqual(table.Data(1, 1:2), {'AlzPlugListed', '3.1'});
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

        % ---- the account's repositories ----------------------------------
        function theAccountsAlakazamRepositoriesAreOffered(testCase)
        %THEACCOUNTSALAKAZAMREPOSITORIESAREOFFERED  Every repository whose name
        %   starts with Alakazam, Alakazam itself left out, malformed ones too.
            repos = PluginsTest.offered();

            testCase.verifyEqual({repos.Repo}, {'AlakazamBroken', 'AlakazamGood'});
            good = repos(2);
            testCase.verifyEqual(good.Tools, {'AlzGood'});
            testCase.verifyEqual(good.Version, '0.2.0');
            testCase.verifyEqual(good.Asset, 'AlzGood-0.2.0.zip');
            testCase.verifyEqual(good.Link, 'https://github.com/me/AlakazamGood');
            testCase.verifyEmpty(good.Problem);
            broken = repos(1);
            testCase.verifyEmpty(broken.Tools);
            testCase.verifySubstring(broken.Problem, 'holds no plugin');
            testCase.verifyEqual(Plugins.providerOf('AlzGood', repos).Repo, 'AlakazamGood');
            testCase.verifyEmpty(Plugins.providerOf('Elsewhere', repos));
        end

        function theListSaysWhatCanBeDone(testCase)
        %THELISTSAYSWHATCANBEDONE  Not installed, an update, not a plugin yet;
        %   Install for the first, Upgrade for the second.
            Plugins.install(Plugins.prepare(testCase.zipOf( ...
                testCase.makePlugin('AlzGood', 'Version', '0.1.0'), 'folder'), ...
                'BuiltInRoot', testCase.BuiltIn));
            installed = {};
            fig = PluginsDialog([], 'Visible', false, 'Repos', PluginsTest.offered(), ...
                'InstallFcn', @(link, repo) install(link, repo));
            closeFig = onCleanup(@() delete(fig));
            table = findobj(fig, 'Tag', 'PluginTable');

            testCase.verifyEqual(reshape(table.ColumnName, 1, []), {'Plugin', 'Installed', 'Latest', 'Status'}, ...
                'No column of repository names: a plugin is named by its own name.');
            testCase.verifyEqual(table.Data(:, 1)', {'AlakazamBroken', 'AlzGood'}, ...
                'A repository with no plugin in it yet goes by its own name.');
            testCase.verifySubstring(table.Data{1, 4}, 'Not a plugin yet');
            testCase.verifyEqual(table.Data(2, 2:4), {'0.1.0', '0.2.0', 'Update available: 0.2.0'});

            table.Selection = 2;
            table.SelectionChangedFcn(table, []);
            testCase.verifyFalse(logical(findobj(fig, 'Tag', 'Install').Enable));
            upgrade = findobj(fig, 'Tag', 'Upgrade');
            testCase.verifyTrue(logical(upgrade.Enable));
            upgrade.ButtonPushedFcn(upgrade, []);
            testCase.verifyEqual(installed, {'https://github.com/me/AlakazamGood', 'AlakazamGood'});

            table.Selection = 1;
            table.SelectionChangedFcn(table, []);
            testCase.verifyTrue(logical(findobj(fig, 'Tag', 'Install').Enable), ...
                'A malformed one can be tried: the install says, kindly, what is missing.');

            function install(link, repo)
                installed = {link, repo};
            end
        end

        function aMalformedPluginIsRefusedVeryKindly(testCase)
            text = Plugins.notAPluginMessage('AlakazamBroken', 'there is no plugin folder in it');
            testCase.verifySubstring(text, 'AlakazamBroken');
            testCase.verifySubstring(text, 'so very sorry');
            testCase.verifySubstring(text, 'nothing has been installed or changed');
            testCase.verifySubstring(text, '<Name>.json');
        end

        function aLinkIsRecordedForUpgrading(testCase)
        %ALINKISRECORDEDFORUPGRADING  Where a plugin came from, as a link Update
        %   can fetch again; one recorded before links were is read from its
        %   source ("github.com/owner/repo, release ...").
            zipFile = testCase.zipOf(testCase.makePlugin('AlzPlugLinked'), 'folder');
            Plugins.install(Plugins.prepare(zipFile, 'BuiltInRoot', testCase.BuiltIn));
            testCase.verifyEmpty(Plugins.installed().Link, 'A zip file has no link.');

            file = fullfile(testCase.PluginRoot, Plugins.RegistryFile);
            registry = jsondecode(fileread(file));
            registry.source = 'github.com/me/AlakazamLinked, release V1 (AlzPlugLinked-1.zip)';
            registry = rmfield(registry, 'link');
            writeText(file, jsonencode({registry}));
            testCase.verifyEqual(Plugins.installed().Link, 'https://github.com/me/AlakazamLinked');
        end

        function aPluginsManualIsItsOwnOrItsRepositorysPages(testCase)
        %APLUGINSMANUALISITSOWNORITSREPOSITORYSPAGES  Where a plugin's ? leads
        %   (manualAddress): where its manifest says (a web address, or an
        %   anchor in Alakazam's manual), else the GitHub Pages of the
        %   repository it was installed from, else nowhere.
            builtIn = testCase.BuiltIn;
            install = @(name, varargin) Plugins.install(Plugins.prepare(testCase.zipOf( ...
                testCase.makePlugin(name, varargin{:}), 'folder'), 'BuiltInRoot', builtIn));
            install('AlzPlugOwnManual', 'Manual', 'https://example.org/own-manual/');
            install('AlzPlugAnchored', 'Manual', '#sec-plugins');
            install('AlzPlugFromZip');
            testCase.verifyEqual(manualAddress('AlzPlugOwnManual'), 'https://example.org/own-manual/');
            testCase.verifyEqual(manualAddress('AlzPlugAnchored'), ...
                'https://markspan.github.io/Alakazam/#sec-plugins');
            testCase.verifyEmpty(manualAddress('AlzPlugFromZip'), 'A zip file says nothing of a manual.');

            file = fullfile(testCase.PluginRoot, Plugins.RegistryFile);
            registry = jsondecode(fileread(file));
            if ~iscell(registry)
                registry = num2cell(registry);
            end
            for k = 1:numel(registry)
                if strcmp(registry{k}.name, 'AlzPlugFromZip')
                    registry{k}.link = 'https://github.com/Me/AlakazamFromZip';
                end
            end
            writeText(file, jsonencode(registry));
            testCase.verifyEqual(manualAddress('AlzPlugFromZip'), 'https://me.github.io/AlakazamFromZip/', ...
                'Installed from a repository: its GitHub Pages.');
        end

        function theListOpensAPluginsManualInstalledOrNot(testCase)
        %THELISTOPENSAPLUGINSMANUALINSTALLEDORNOT  Manual in Install plugins
        %   opens the selected plugin's manual: for one on offer, not
        %   installed, its repository's GitHub Pages. A stand-in
        %   openInBrowser records the address instead of opening it.
            folder = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture).Folder;
            writeText(fullfile(folder, 'openInBrowser.m'), strjoin({ ...
                'function openInBrowser(url)', ...
                'setappdata(groot, ''OpenedInBrowser'', [getappdata(groot, ''OpenedInBrowser''), {char(url)}]);', ...
                'end'}, newline));
            testCase.addTeardown(@rehash);   % after the path is restored: no stand-in stays cached
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(folder));
            rehash;
            setappdata(groot, 'OpenedInBrowser', {});
            testCase.addTeardown(@() rmappdata(groot, 'OpenedInBrowser'));
            fig = PluginsDialog([], 'Visible', false, 'Repos', PluginsTest.offered());
            closeFig = onCleanup(@() delete(fig));
            table = findobj(fig, 'Tag', 'PluginTable');
            manual = findobj(fig, 'Tag', 'Manual');
            testCase.verifyFalse(logical(manual.Enable), 'Nothing selected, nothing to open.');

            table.Selection = 2;
            table.SelectionChangedFcn(table, []);
            testCase.assertTrue(logical(manual.Enable));
            manual.ButtonPushedFcn(manual, []);
            testCase.verifyEqual(getappdata(groot, 'OpenedInBrowser'), {'https://me.github.io/AlakazamGood/'});
        end

        function aMissingToolIsOfferedFromItsRepository(testCase)
        %AMISSINGTOOLISOFFEREDFROMITSREPOSITORY  A step naming a tool that is not
        %   here, held by one of the account's repositories: asked, installed
        %   on yes; not asked for a tool no repository holds.
            Plugins.available('Refresh', true, 'FetchJson', @PluginsTest.fakeGitHub);
            forget = onCleanup(@() Plugins.available('Refresh', true, 'FetchJson', @(url) []));
            folder = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture).Folder;
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(folder));
            MethodCopy.make(folder, '@Alakazam', 'ensureTransformation', 'ensureCopy');
            rehash;
            app = FakeApp(struct('MainFigure', [], 'Installed', {{}}));
            app.addprop('onInstallPlugin');
            app.onInstallPlugin = @(link, repo) record(link, repo);
            asked = {};

            testCase.verifyFalse(ensureCopy(app, 'AlzGood', @(varargin) say(varargin{2}, 'Not now')));
            testCase.verifySubstring(asked{1}, 'AlakazamGood');
            testCase.verifyEmpty(app.Installed);
            ensureCopy(app, 'AlzGood', @(varargin) say(varargin{2}, 'Install'));
            testCase.verifyEqual(app.Installed, {['https://github.com/' Plugins.Account '/AlakazamGood'], ...
                'AlakazamGood'});
            asked = {};
            testCase.verifyFalse(ensureCopy(app, 'AlzNowhere', @(varargin) say(varargin{2}, 'Install')));
            testCase.verifyEmpty(asked, 'No repository holds it: nothing to offer.');

            function choice = say(message, choice)
                asked{end + 1} = message;
            end
            function record(link, repo)
                app.Installed = {link, repo};
            end
        end

        function theInstallersQuestionsAreShownWhereInstallWasPressed(testCase)
        %THEINSTALLERSQUESTIONSARESHOWNWHEREINSTALLWASPRESSED  The progress,
        %   the confirmation and the alerts are drawn in the window given,
        %   the Install plugins window, which is in front: drawn in the main
        %   window behind it they were hidden, and the application seemed
        %   stuck. Without a window given, the main window. Stand-ins first
        %   on the path record where each prompt was put.
            folder = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture).Folder;
            writeText(fullfile(folder, 'uiprogressdlg.m'), strjoin({ ...
                'function d = uiprogressdlg(f, varargin)', ...
                'setappdata(groot, ''PluginPromptFigures'', [getappdata(groot, ''PluginPromptFigures''), {f}]);', ...
                'd = figure(''Visible'', ''off'');', ...
                'end'}, newline));
            writeText(fullfile(folder, 'uialert.m'), strjoin({ ...
                'function uialert(f, varargin)', ...
                'setappdata(groot, ''PluginPromptFigures'', [getappdata(groot, ''PluginPromptFigures''), {f}]);', ...
                'end'}, newline));
            MethodCopy.make(folder, '@Alakazam', 'onInstallPlugin', 'installCopy');
            testCase.addTeardown(@rehash);   % after the path is restored: no stand-in stays cached
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(folder));
            rehash;
            testCase.addTeardown(@() rmappdata(groot, 'PluginPromptFigures'));
            main = uifigure('Visible', 'off');
            testCase.addTeardown(@() delete(main));
            pluginsWindow = uifigure('Visible', 'off');
            testCase.addTeardown(@() delete(pluginsWindow));
            app = FakeApp(struct('MainFigure', main));
            nowhere = fullfile(testCase.PluginRoot, 'no-such-plugin.zip');

            setappdata(groot, 'PluginPromptFigures', {});
            installCopy(app, nowhere, 'AlakazamNothing', pluginsWindow);
            shown = getappdata(groot, 'PluginPromptFigures');
            testCase.verifyNotEmpty(shown, 'The failed fetch was not reported.');
            testCase.verifyTrue(all(cellfun(@(f) isequal(f, pluginsWindow), shown)), ...
                'A prompt went to another window than the one Install was pressed in.');

            setappdata(groot, 'PluginPromptFigures', {});
            installCopy(app, nowhere, 'AlakazamNothing');
            shown = getappdata(groot, 'PluginPromptFigures');
            testCase.verifyNotEmpty(shown);
            testCase.verifyTrue(all(cellfun(@(f) isequal(f, main), shown)), ...
                'Without a window given, the prompts belong in the main window.');
        end

        function installPluginsPassesItsOwnWindow(testCase)
        %INSTALLPLUGINSPASSESITSOWNWINDOW  Install in the list installs with
        %   the list's own window as the one to ask in: the window made by
        %   PluginsDialog, not the empty handle an anonymous function would
        %   have captured before the window existed. A stand-in
        %   PluginsDialog hands back a window and keeps the install function.
            folder = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture).Folder;
            writeText(fullfile(folder, 'PluginsDialog.m'), strjoin({ ...
                'function fig = PluginsDialog(~, varargin)', ...
                'o = struct(varargin{:});', ...
                'setappdata(groot, ''StandInInstallFcn'', o.InstallFcn);', ...
                'fig = uifigure(''Visible'', ''off'');', ...
                'setappdata(groot, ''StandInPluginsWindow'', fig);', ...
                'end'}, newline));
            MethodCopy.make(folder, '@Alakazam', 'onManagePlugins', 'manageCopy');
            testCase.addTeardown(@rehash);   % after the path is restored: no stand-in stays cached
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(folder));
            rehash;
            testCase.addTeardown(@() rmappdata(groot, 'StandInInstallFcn'));
            testCase.addTeardown(@() rmappdata(groot, 'StandInPluginsWindow'));
            app = FakeApp(struct('MainFigure', [], 'Asked', {{}}));
            app.addprop('onInstallPlugin');
            app.onInstallPlugin = @(link, repo, host) record(link, repo, host);

            manageCopy(app);
            window = getappdata(groot, 'StandInPluginsWindow');
            testCase.addTeardown(@() delete(window));
            installFcn = getappdata(groot, 'StandInInstallFcn');
            installFcn('https://github.com/me/AlakazamGood', 'AlakazamGood');

            testCase.assertNumElements(app.Asked, 3);
            testCase.verifyEqual(app.Asked(1:2), {'https://github.com/me/AlakazamGood', 'AlakazamGood'});
            testCase.verifyTrue(isequal(app.Asked{3}, window), ...
                'The install was not given the Install plugins window to ask in.');

            function record(link, repo, host)
                app.Asked = {link, repo, host};
            end
        end

        function installPluginsShowsTheBusyCursorUntilItsWindowIsThere(testCase)
        %INSTALLPLUGINSSHOWSTHEBUSYCURSORUNTILITSWINDOWISTHERE  From the press
        %   until the window is made (asking GitHub takes some seconds), the
        %   busy cursor over the main window and over the ribbon, whose page
        %   draws its own cursors; the usual ones after, an error included. A
        %   stand-in PluginsDialog records the main window's cursor while it
        %   runs, and fails when asked to.
            folder = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture).Folder;
            writeText(fullfile(folder, 'PluginsDialog.m'), strjoin({ ...
                'function fig = PluginsDialog(parent, varargin)', ...
                'setappdata(groot, ''StandInPointer'', char(parent.Pointer));', ...
                'if isappdata(groot, ''StandInFails''), error(''StandIn:fails'', ''No window''); end', ...
                'fig = [];', ...
                'end'}, newline));
            MethodCopy.make(folder, '@Alakazam', 'onManagePlugins', 'manageCopy');
            testCase.addTeardown(@rehash);   % after the path is restored: no stand-in stays cached
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(folder));
            rehash;
            testCase.addTeardown(@() rmappdata(groot, 'StandInPointer'));
            main = uifigure('Visible', 'off');
            testCase.addTeardown(@() delete(main));
            ribbon = {};
            app = FakeApp(struct('MainFigure', main, ...
                'Ribbon', struct('setBusy', @(busy) setBusy(busy))));

            manageCopy(app);
            testCase.verifyEqual(getappdata(groot, 'StandInPointer'), 'watch', ...
                'No busy cursor over the main window while the list was made.');
            testCase.verifyEqual(char(main.Pointer), 'arrow');
            testCase.verifyEqual(ribbon, {true, false}, 'The ribbon was not told, or not told back.');

            ribbon = {};
            setappdata(groot, 'StandInFails', true);
            testCase.addTeardown(@() rmappdata(groot, 'StandInFails'));
            testCase.verifyError(@() manageCopy(app), 'StandIn:fails');
            testCase.verifyEqual(char(main.Pointer), 'arrow', 'An error left the busy cursor on.');
            testCase.verifyEqual(ribbon, {true, false});

            function setBusy(busy)
                ribbon{end + 1} = busy;
            end
        end

        function theListShowsTheBusyCursorWhileAskingGitHub(testCase)
        %THELISTSHOWSTHEBUSYCURSORWHILEASKINGGITHUB  The Install plugins
        %   window's own cursor is the busy one while the repositories are
        %   asked for, on opening and on Refresh, and the usual one after.
            seen = {};
            fig = PluginsDialog([], 'Visible', false, 'Repos', @(~) asked());
            closeFig = onCleanup(@() delete(fig));
            testCase.verifyEqual(seen, {'watch'});
            testCase.verifyEqual(char(fig.Pointer), 'arrow');

            refresh = findobj(fig, 'Tag', 'Refresh');
            refresh.ButtonPushedFcn(refresh, []);
            testCase.verifyEqual(seen, {'watch', 'watch'});
            testCase.verifyEqual(char(fig.Pointer), 'arrow');

            function repos = asked()
                window = findall(groot, 'Type', 'figure', 'Tag', 'PluginsDialog');
                seen{end + 1} = char(window(1).Pointer);
                repos = PluginsTest.noRepos();
            end
        end

        function theRibbonPageHasABusyCursor(testCase)
        %THERIBBONPAGEHASABUSYCURSOR  What AlakazamRibbon.setBusy sends, the
        %   page listens for, and its busy rule outranks the buttons' hand.
            source = fullfile(fileparts(fileparts(mfilename('fullpath'))), 'src');
            page = fileread(fullfile(source, 'AlakazamRibbon.html'));
            testCase.verifySubstring(page, 'addEventListener(''busy''');
            testCase.verifySubstring(page, 'body.alz-busy * { cursor: wait !important; }');
            code = fileread(fullfile(source, 'AlakazamRibbon.m'));
            testCase.verifySubstring(code, 'sendEventToHTMLSource(this.Component, ''busy''');
        end

        % ---- asking GitHub as little as can be -----------------------------
        function theListIsKeptForTheNextSession(testCase)
        %THELISTISKEPTFORTHENEXTSESSION  The list GitHub gave is saved beside
        %   the plugins; a new session takes it while it is less than a day
        %   old, and says so, and asks GitHub again once it is older.
            asked = {};
            first = Plugins.available('Refresh', true, 'Account', 'me', ...
                'FetchJson', @(url) ask(url), 'FetchIndex', @(~) []);
            testCase.verifyTrue(isfile(Plugins.listingFile()));
            testCase.verifyNumElements(asked, 5, ...
                'The repositories, then the files and the release of each of two.');

            [again, notice] = Plugins.available('Account', 'me', 'Session', false, ...
                'FetchJson', @(url) ask(url), 'FetchIndex', @(~) []);
            testCase.verifyNumElements(asked, 5, 'A new session: GitHub is not asked.');
            testCase.verifyEqual(again, first);
            testCase.verifySubstring(notice, 'The list is the one GitHub gave today at');
            testCase.verifySubstring(notice, 'Refresh asks GitHub itself');

            PluginsTest.ageListing(hours(31));
            [~, notice] = Plugins.available('Account', 'me', 'Session', false, ...
                'FetchJson', @(url) ask(url), 'FetchIndex', @(~) []);
            testCase.verifyNumElements(asked, 10, 'A day and more old: GitHub is asked again.');
            testCase.verifyEmpty(notice, 'GitHub''s answer just now needs no word.');

            function data = ask(url)
                asked{end + 1} = url;
                data = PluginsTest.fakeGitHub(url);
            end
        end

        function thePluginIndexIsReadAsGitHubsOwnAnswers(testCase)
        %THEPLUGININDEXISREADASGITHUBSOWNANSWERS  The index holds GitHub's
        %   answers to the requests the list makes; read, they make the very
        %   list GitHub's do, without asking GitHub. An index lacking an
        %   answer, or another account's, is passed over.
            fromGitHub = PluginsTest.offered();
            delete(Plugins.listingFile());
            index = PluginsTest.indexOf('me', datetime('now') - minutes(10));

            [repos, notice] = Plugins.available('Account', 'me', 'Session', false, ...
                'FetchJson', @notAsked, 'FetchIndex', @(~) index);
            testCase.verifyEqual(repos, fromGitHub);
            testCase.verifySubstring(notice, 'The list is Alakazam''s plugin index of');
            testCase.verifySubstring(notice, 'Refresh asks GitHub itself');

            asked = 0;
            gap = index;
            gap.responses(end) = [];
            delete(Plugins.listingFile());
            Plugins.available('Account', 'me', 'Session', false, ...
                'FetchJson', @(url) ask(url), 'FetchIndex', @(~) gap);
            testCase.verifyGreaterThan(asked, 0, 'An index lacking an answer: GitHub is asked.');

            asked = 0;
            other = index;
            other.account = 'someoneElse';
            delete(Plugins.listingFile());
            Plugins.available('Account', 'me', 'Session', false, ...
                'FetchJson', @(url) ask(url), 'FetchIndex', @(~) other);
            testCase.verifyGreaterThan(asked, 0, 'Another account''s index: GitHub is asked.');

            function data = ask(url)
                asked = asked + 1;
                data = PluginsTest.fakeGitHub(url);
            end
        end

        function theNewerOfTheIndexAndTheSavedListIsShown(testCase)
        %THENEWEROFTHEINDEXANDTHESAVEDLISTISSHOWN  Both at hand: the one
        %   GitHub gave later, whichever it is. The index here knows a newer
        %   release of AlakazamGood than the list saved two hours ago.
            PluginsTest.offered();
            PluginsTest.ageListing(hours(2));
            newerRelease = @(index) PluginsTest.withRelease(index, 'AlakazamGood', 'V0.3.0');

            index = newerRelease(PluginsTest.indexOf('me', datetime('now') - minutes(30)));
            [repos, notice] = Plugins.available('Account', 'me', 'Session', false, ...
                'FetchJson', @notAsked, 'FetchIndex', @(~) index);
            testCase.verifyEqual(repos(strcmp({repos.Repo}, 'AlakazamGood')).Version, '0.3.0');
            testCase.verifySubstring(notice, 'plugin index');

            PluginsTest.offered();
            PluginsTest.ageListing(hours(2));
            index = newerRelease(PluginsTest.indexOf('me', datetime('now') - hours(3)));
            [repos, notice] = Plugins.available('Account', 'me', 'Session', false, ...
                'FetchJson', @notAsked, 'FetchIndex', @(~) index);
            testCase.verifyEqual(repos(strcmp({repos.Repo}, 'AlakazamGood')).Version, '0.2.0');
            testCase.verifySubstring(notice, 'the one GitHub gave');
        end

        function aRealIndexIsRead(testCase)
        %AREALINDEXISREAD  An index the Manual site workflow's script wrote
        %   for markspan on 2026-10-18 (tests/fixtures/plugin-index-sample.json):
        %   eleven repositories, Heartbeats 0.2.0 among them.
            fixtures = fullfile(fileparts(mfilename('fullpath')), 'fixtures');
            sample = jsondecode(fileread(fullfile(fixtures, 'plugin-index-sample.json')));
            sample.generated = PluginsTest.utcText(datetime('now') - hours(1));
            forget = onCleanup(@() Plugins.available('Refresh', true, 'FetchJson', @(url) [], ...
                'FetchIndex', @(~) []));

            repos = Plugins.available('Session', false, 'FetchJson', @notAsked, ...
                'FetchIndex', @(~) sample);
            testCase.verifyNumElements(repos, 11);
            testCase.verifyTrue(all(~cellfun(@isempty, {repos.Release})), 'Every one has a release.');
            heartbeats = repos(strcmp({repos.Repo}, 'AlakazamHREvoked'));
            testCase.verifyEqual(heartbeats.Tools, {'Heartbeats'});
            testCase.verifyEqual(heartbeats.Version, '0.2.0');
            testCase.verifyEqual(heartbeats.Asset, 'Heartbeats-0.2.0.zip');
            testCase.verifyEmpty(heartbeats.Problem);
            testCase.verifyEqual(heartbeats.Link, 'https://github.com/markspan/AlakazamHREvoked');
        end

        function whenGitHubRefusesTheLastListIsShownAndItWaits(testCase)
        %WHENGITHUBREFUSESTHELASTLISTISSHOWNANDITWAITS  GitHub's limit used up:
        %   the list saved is shown, with the time GitHub takes requests
        %   again, and GitHub is not asked before then, in a new session
        %   either.
            first = PluginsTest.offered();
            reset = dateshift(datetime('now') + minutes(40), 'start', 'minute');
            asked = 0;

            [repos, notice] = Plugins.available('Refresh', true, 'Account', 'me', ...
                'FetchJson', @(url) refuseNow(url), 'FetchIndex', @(~) []);
            testCase.verifyEqual(asked, 1);
            testCase.verifyEqual(repos, first);
            testCase.verifySubstring(notice, char(reset, 'HH:mm'));
            testCase.verifySubstring(notice, 'without a token it allows 60 an hour');
            testCase.verifySubstring(notice, 'The list is the one GitHub gave today at');

            [~, notice] = Plugins.available('Refresh', true, 'Account', 'me', 'Session', false, ...
                'FetchJson', @(url) refuseNow(url), 'FetchIndex', @(~) []);
            testCase.verifyEqual(asked, 1, 'Not asked again before the time it named.');
            testCase.verifySubstring(notice, char(reset, 'HH:mm'));

            function data = refuseNow(~) %#ok<STOUT>
                asked = asked + 1;
                throw(GitHubRateLimit(reset));
            end
        end

        function aRefusalPartWayEndsTheList(testCase)
        %AREFUSALPARTWAYENDSTHELIST  The limit reached after the first
        %   request: not a list whose repositories each say the limit, but
        %   the last whole one.
            first = PluginsTest.offered();
            reset = datetime('now') + minutes(30);
            [repos, notice] = Plugins.available('Refresh', true, 'Account', 'me', ...
                'FetchJson', @(url) refuseFiles(url), 'FetchIndex', @(~) []);
            testCase.verifyEqual(repos, first);
            testCase.verifySubstring(notice, 'limit of requests');

            function data = refuseFiles(url)
                if contains(url, '/git/trees/')
                    throw(GitHubRateLimit(reset));
                end
                data = PluginsTest.fakeGitHub(url);
            end
        end

        function aRefusalWithNothingSavedSaysWhen(testCase)
        %AREFUSALWITHNOTHINGSAVEDSAYSWHEN  No list saved and no index: the
        %   refusal itself, which the dialog shows. With an index, the index.
            reset = datetime('now') + minutes(30);
            refusing = @(url) refuse(url, reset);
            testCase.verifyError(@() Plugins.available('Refresh', true, 'Account', 'me', ...
                'FetchJson', refusing, 'FetchIndex', @(~) []), 'Alakazam:Plugins:rateLimited');
            try
                Plugins.available('Refresh', true, 'Account', 'me', 'Session', false, ...
                    'FetchJson', refusing, 'FetchIndex', @(~) []);
            catch err
                testCase.verifySubstring(err.message, char(reset, 'HH:mm'));
            end

            index = PluginsTest.indexOf('me', datetime('now') - hours(2));
            [repos, notice] = Plugins.available('Refresh', true, 'Account', 'me', 'Session', false, ...
                'FetchJson', refusing, 'FetchIndex', @(~) index);
            testCase.verifyEqual({repos.Repo}, {'AlakazamBroken', 'AlakazamGood'});
            testCase.verifySubstring(notice, 'limit of requests');
            testCase.verifySubstring(notice, 'The list is Alakazam''s plugin index of');
        end

        function githubsRefusalForItsLimitIsToldApart(testCase)
        %GITHUBSREFUSALFORITSLIMITISTOLDAPART  A 403 or 429 with none left on
        %   /rate_limit lifts at its reset time; a burst limit in a minute;
        %   any other refusal is not the limit.
            err = MException('MATLAB:webservices:HTTP403StatusCodeError', ['The server returned ' ...
                'the status 403 with message "rate limit exceeded" in response to the request ' ...
                'to URL https://api.github.com/users/me/repos.']);
            later = datetime('now') + minutes(20);
            epoch = posixtime(datetime(later, 'TimeZone', 'local'));
            info = struct('resources', struct('core', struct('limit', 60, 'remaining', 0, ...
                'reset', round(epoch), 'used', 60)));

            limit = Plugins.rateLimitOf(err, @() info);
            testCase.verifyClass(limit, 'GitHubRateLimit');
            testCase.verifyEqual(limit.identifier, 'Alakazam:Plugins:rateLimited');
            testCase.verifyLessThan(abs(seconds(limit.ResetTime - later)), 1);

            info.resources.core.remaining = 12;
            limit = Plugins.rateLimitOf(err, @() info);
            testCase.verifyLessThan(abs(seconds(limit.ResetTime - (datetime('now') + minutes(1)))), 5, ...
                'Requests left yet "rate limit": a burst limit, a minute.');

            other = MException('MATLAB:webservices:HTTP403StatusCodeError', ['The server returned ' ...
                'the status 403 with message "Repository access blocked" in response to ...']);
            testCase.verifyEmpty(Plugins.rateLimitOf(other, @() info));
            missing = MException('MATLAB:webservices:HTTP404StatusCodeError', ...
                'The server returned the status 404 with message "Not Found" in response to ...');
            testCase.verifyEmpty(Plugins.rateLimitOf(missing, @() info));
            info.resources.core.remaining = 0;
            testCase.verifyNotEmpty(Plugins.rateLimitOf(other, @() info), ...
                'None left: a 403 is the limit, whatever it says.');
        end

        function aListedPluginInstallsTheReleaseTheListShows(testCase)
        %ALISTEDPLUGININSTALLSTHERELEASETHELISTSHOWS  A repository the list
        %   holds with a release is fetched from that release's download
        %   address, without asking GitHub's API; by default the list is the
        %   one Install plugins shows.
            known = PluginsTest.offered();
            spec = Plugins.resolveSource('https://github.com/me/AlakazamGood', @notAsked, known);
            testCase.verifyEqual(spec.Location, ...
                'https://github.com/me/AlakazamGood/releases/download/V0.2.0/AlzGood-0.2.0.zip');
            testCase.verifySubstring(spec.Label, 'release V0.2.0');
            spec = Plugins.resolveSource('https://github.com/me/AlakazamBroken', @noReleaseYet, known);
            testCase.verifyEqual(spec.Location, ...
                'https://github.com/me/AlakazamBroken/archive/refs/heads/trunk.zip', ...
                'Listed without a release: GitHub is asked.');

            Plugins.available('Refresh', true, 'FetchJson', @PluginsTest.fakeGitHub, 'FetchIndex', @(~) []);
            forget = onCleanup(@() Plugins.available('Refresh', true, 'FetchJson', @(url) [], ...
                'FetchIndex', @(~) []));
            zipFile = testCase.zipOf(testCase.makePlugin('AlzGood'), 'folder');
            fetched = {};
            candidate = Plugins.prepare(['https://github.com/' Plugins.Account '/AlakazamGood'], ...
                'BuiltInRoot', testCase.BuiltIn, 'FetchJson', @notAsked, ...
                'Download', @(url, file) fetch(url, file));
            Plugins.discard(candidate);
            testCase.verifyEqual(fetched, {sprintf( ...
                'https://github.com/%s/AlakazamGood/releases/download/V0.2.0/AlzGood-0.2.0.zip', ...
                Plugins.Account)});

            function fetch(url, file)
                fetched{end + 1} = url;
                copyfile(zipFile, file);
            end
        end

        function theListSaysWhereItComesFrom(testCase)
            notice = 'The list is Alakazam''s plugin index of today at 05:17. Refresh asks GitHub itself.';
            fig = PluginsDialog([], 'Visible', false, 'Repos', ...
                @(~) struct('Repos', {PluginsTest.noRepos()}, 'Notice', notice));
            closeFig = onCleanup(@() delete(fig));
            testCase.verifySubstring(findobj(fig, 'Tag', 'Where').Text, notice);
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

    methods (Static)
        function repos = noRepos()
            repos = struct('Repo', {}, 'Link', {}, 'Description', {}, 'Release', {}, ...
                'Version', {}, 'Asset', {}, 'Tools', {}, 'Problem', {});
        end

        function repos = offered()
        %OFFERED  Plugins.available on PluginsTest.fakeGitHub's account.
            repos = Plugins.available('Refresh', true, 'Account', 'me', ...
                'FetchJson', @PluginsTest.fakeGitHub);
        end

        function data = fakeGitHub(url)
        %FAKEGITHUB  An account "me" with Alakazam itself, a plugin repository
        %   with a release (AlakazamGood), one without a plugin or a release
        %   (AlakazamBroken) and one by another name.
            if contains(url, '/users/')
                data = struct('name', {'Alakazam', 'AlakazamGood', 'AlakazamBroken', 'Other'}, ...
                    'description', {'the app', 'a good one', 'not yet', 'else'}, ...
                    'default_branch', {'main', 'main', 'main', 'main'});
            elseif contains(url, 'AlakazamGood/git/trees')
                data = struct('tree', struct('path', {'README.md', 'AlzGood', 'AlzGood/AlzGood.json', ...
                    'AlzGood/AlzGood.m', 'AlzGood/+Helpers/x.m'}));
            elseif contains(url, 'AlakazamBroken/git/trees')
                data = struct('tree', struct('path', {'README.md', 'notes.txt'}));
            elseif contains(url, 'AlakazamGood/releases/latest')
                data = struct('tag_name', 'V0.2.0', 'assets', struct('name', 'AlzGood-0.2.0.zip'));
            elseif contains(url, 'releases/latest')
                throw(MException('MATLAB:webservices:HTTP404StatusCodeError', 'Not Found (404)'));
            else
                data = [];
            end
        end

        function index = indexOf(account, generated)
        %INDEXOF  The plugin index of fakeGitHub's account, made at GENERATED,
        %   as the Manual site workflow's script writes it (GitHub's answer
        %   to each request the list makes, a 404 as its status) and as it is
        %   read back from JSON.
            responses = struct('url', {}, 'status', {}, 'body', {});
            users = sprintf('https://api.github.com/users/%s/repos?per_page=100&page=1', account);
            repositories = PluginsTest.fakeGitHub(users);
            responses(end + 1) = struct('url', users, 'status', 200, 'body', {repositories});
            for name = {repositories.name}
                if ~startsWith(name{1}, 'Alakazam') || strcmp(name{1}, 'Alakazam')
                    continue;
                end
                api = sprintf('https://api.github.com/repos/%s/%s', account, name{1});
                for url = {[api '/git/trees/main?recursive=1'], [api '/releases/latest']}
                    try
                        responses(end + 1) = struct('url', url{1}, 'status', 200, ...
                            'body', {PluginsTest.fakeGitHub(url{1})}); %#ok<AGROW>
                    catch
                        responses(end + 1) = struct('url', url{1}, 'status', 404, 'body', []); %#ok<AGROW>
                    end
                end
            end
            index = jsondecode(jsonencode(struct('format', 1, 'account', account, ...
                'generated', PluginsTest.utcText(generated), 'responses', responses)));
        end

        function index = withRelease(index, repo, tag)
        %WITHRELEASE  INDEX with REPO's latest release answered as TAG.
            for k = 1:numel(index.responses)
                if endsWith(index.responses(k).url, ['/' repo '/releases/latest'])
                    index.responses(k).body.tag_name = tag;
                end
            end
        end

        function text = utcText(t)
        %UTCTEXT  A local time as GitHub and the index write it, in UTC.
            t.TimeZone = 'local';
            t.TimeZone = 'UTC';
            text = char(t, 'yyyy-MM-dd''T''HH:mm:ss''Z''');
        end

        function ageListing(age)
        %AGELISTING  Make the list saved on this computer AGE old.
            file = Plugins.listingFile();
            record = jsondecode(fileread(file));
            record.fetched = char(datetime('now') - age, 'yyyy-MM-dd''T''HH:mm:ss');
            writeText(file, jsonencode(record));
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
            p.addParameter('Manual', '');
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
            if ~isempty(o.Manual)
                manifest.Manual = o.Manual;
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

function data = notAsked(url) %#ok<STOUT>
%NOTASKED  A FetchJson that must not be called: GitHub was not to be asked.
    error('PluginsTest:asked', 'GitHub was asked for %s.', url);
end

function data = refuse(~, reset) %#ok<STOUT>
%REFUSE  A FetchJson GitHub's limit refuses, until RESET.
    throw(GitHubRateLimit(reset));
end

function data = noReleaseYet(url)
    if endsWith(url, '/releases/latest')
        throw(MException('Test:HTTP404', 'The server returned the status 404 (Not Found).'));
    end
    data = struct('default_branch', 'trunk');
end
