classdef EnsureLatestGEDAITest < matlab.unittest.TestCase
%ENSURELATESTGEDAITEST  Which GEDAI release ensureLatestGEDAI puts on the
%   path, and when it downloads, asks, or makes do.
%
%   No network and no real GEDAI: every case installs stand-in releases (a
%   GEDAI.m, an EEGLAB plugin file declaring a version, an auxiliaries
%   folder) under a temporary root, and passes the updater a newest
%   release, a download and an answer to the consent question of its own,
%   logging what was called. Any GEDAI on the path when a case starts is
%   taken off it for the case, and the path is put back afterwards.
%
%   Run with: runtests('tests/EnsureLatestGEDAITest.m').
%
%   See also ENSURELATESTGEDAI, AUTOGEDAITEST.

    properties (Access = private)
        Scratch char    % temporary folder, holding Root and anything else a case makes
        Root char       % where the updater installs releases
        Log             % containers.Map: 'consent' and 'download', each a cell of what was passed
    end

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'Transformations', 'AutoGEDAI')));
        end
    end

    methods (TestMethodSetup)
        function startWithNoGEDAI(testCase)
            testCase.Scratch = testCase.applyFixture( ...
                matlab.unittest.fixtures.TemporaryFolderFixture()).Folder;
            testCase.Root = fullfile(testCase.Scratch, 'GEDAI');
            testCase.addTeardown(@path, path());   % runs before the folder goes
            for found = reshape(cellstr(which('GEDAI', '-all')), 1, [])
                if ~isempty(found{1})
                    rmpath(fileparts(found{1}));
                end
            end
            testCase.Log = containers.Map({'consent', 'download'}, {{}, {}});
        end
    end

    methods (Test)
        function aFirstInstallAsksAndInstallsTheNewest(testCase)
            installed = testCase.update(newest('1.8'), true);

            testCase.verifyEqual(testCase.Log('consent'), {'1.8'}, 'Asked once, about v1.8.');
            testCase.verifyEqual(installed.Version, '1.8');
            testCase.verifyEqual(installed.Folder, fullfile(testCase.Root, 'v1.8', 'GEDAI-master-1.8'));
            testCase.verifyEqual(onPath(), {installed.Folder});
        end

        function aDeclinedFirstInstallInstallsNothing(testCase)
            testCase.verifyError(@() testCase.update(newest('1.8'), false), ...
                'Alakazam:AutoGEDAI:notInstalled');

            testCase.verifyEmpty(testCase.Log('download'));
            testCase.verifyEmpty(onPath());
        end

        function anUpdateIsNotAskedButSaid(testCase)
        %ANUPDATEISNOTASKEDBUTSAID  The release the pinned install unzipped
        %   straight under the root is found, replaced by the newest without
        %   asking, and left on disk.
            old = makeRelease(fullfile(testCase.Root, 'GEDAI-master-1.7'), '1.7');

            [printed, installed] = printedBy(@() testCase.update(newest('1.8'), false));

            testCase.verifyEmpty(testCase.Log('consent'), 'An update must not ask again.');
            testCase.verifySubstring(printed, 'updating GEDAI from v1.7 to v1.8');
            testCase.verifyEqual(installed.Version, '1.8');
            testCase.verifyEqual(onPath(), {installed.Folder});
            testCase.verifyTrue(isfile(fullfile(old, 'GEDAI.m')), 'The old release stays on disk.');
        end

        function anUpToDateInstallDownloadsNothing(testCase)
            current = makeRelease(fullfile(testCase.Root, 'v1.8', 'GEDAI-master-1.8'), '1.8');

            installed = testCase.update(newest('1.8'), false);

            testCase.verifyEmpty(testCase.Log('download'));
            testCase.verifyEqual(installed, struct('Version', '1.8', 'Folder', current));
            testCase.verifyEqual(onPath(), {current});
        end

        function theVersionIsTheTagsNotThePluginFiles(testCase)
        %THEVERSIONISTHETAGSNOTTHEPLUGINFILES  v1.7.1's eegplugin_GEDAI.m
        %   still says v1.7. Read from there, v1.7.1 would be downloaded
        %   again every session; its folder names the tag. (Its ".7.1" is
        %   also what fileparts would take for an extension.)
            current = makeRelease(fullfile(testCase.Root, 'v1.7.1', 'GEDAI-master-1.7.1'), '1.7');

            installed = testCase.update(newest('1.7.1'), false);

            testCase.verifyEmpty(testCase.Log('download'), 'v1.7.1 is installed already.');
            testCase.verifyEqual(installed, struct('Version', '1.7.1', 'Folder', current));
        end

        function offlineTheNewestInstalledRuns(testCase)
        %OFFLINETHENEWESTINSTALLEDRUNS  And newest as versions go: 1.10
        %   after 1.9, whatever the order on disk.
            makeRelease(fullfile(testCase.Root, 'GEDAI-master-1.7'), '1.7');
            makeRelease(fullfile(testCase.Root, 'v1.9', 'GEDAI-master-1.9'), '1.9');
            newestOnDisk = makeRelease(fullfile(testCase.Root, 'v1.10', 'GEDAI-master-1.10'), '1.10');

            [~, installed] = printedBy(@() testCase.update(@unreachable, false));

            testCase.verifyEqual(installed, struct('Version', '1.10', 'Folder', newestOnDisk));
            testCase.verifyEqual(onPath(), {newestOnDisk});
        end

        function offlineWithNothingInstalledIsAnError(testCase)
            testCase.verifyError(@() printedBy(@() testCase.update(@unreachable, true)), ...
                'Alakazam:AutoGEDAI:notInstalled');

            testCase.verifyEmpty(testCase.Log('consent'), 'Nothing to agree to: nothing can be had.');
        end

        function aFailedUpdateKeepsTheInstalledRelease(testCase)
            old = makeRelease(fullfile(testCase.Root, 'GEDAI-master-1.7'), '1.7');

            installed = testCase.verifyWarning( ...
                @() testCase.update(newest('1.8'), false, @failingDownload), ...
                'Alakazam:AutoGEDAI:update');

            testCase.verifyEqual(installed, struct('Version', '1.7', 'Folder', old));
            testCase.verifyEqual(onPath(), {old});
        end

        function aDownloadWithoutGEDAIKeepsTheInstalledRelease(testCase)
            old = makeRelease(fullfile(testCase.Root, 'GEDAI-master-1.7'), '1.7');

            installed = testCase.verifyWarning( ...
                @() testCase.update(newest('1.8'), false, @(~, folder) mkdir(folder)), ...
                'Alakazam:AutoGEDAI:update');

            testCase.verifyEqual(installed.Folder, old);
        end

        function severalGEDAIsOnThePathAreNoError(testCase)
        %SEVERALGEDAISONTHEPATHARENOERROR  Two installs outside the root,
        %   both on the path, and one in it: the newest runs, and the others
        %   come off the path with the folders under them that were on it
        %   too. (The draft failed only with both: dir lists the root's as a
        %   row, which lists the path's as a column, and MATLAB lets an
        %   empty row join a column.)
            makeRelease(fullfile(testCase.Root, 'GEDAI-master-1.5'), '1.5');
            older = makeRelease(fullfile(testCase.Scratch, 'elsewhere', 'GEDAI-master-1.6'), '1.6');
            newer = makeRelease(fullfile(testCase.Scratch, 'plugins', 'GEDAI1.7'), '1.7');
            addpath(newer, older, fullfile(older, 'auxiliaries'));

            [~, installed] = printedBy(@() testCase.update(@unreachable, false));

            testCase.verifyEqual(installed, struct('Version', '1.7', 'Folder', newer));
            testCase.verifyEqual(onPath(), {newer});
            testCase.verifyFalse(contains(path(), older), ...
                'The older install''s auxiliaries are still on the path.');
        end

        function aReleaseOnThePathCountsAsAgreedTo(testCase)
        %ARELEASEONTHEPATHCOUNTSASAGREEDTO  A GEDAI from EEGLAB's plugin
        %   manager is updated without asking. The download's own folder is
        %   the one used, though its plugin file names an older release
        %   than the one on the path.
            plugin = makeRelease(fullfile(testCase.Scratch, 'plugins', 'GEDAI1.7.5'), '1.7.5');
            addpath(plugin);

            installed = testCase.update(newest('1.8', '1.7'), false);

            testCase.verifyEmpty(testCase.Log('consent'));
            testCase.verifyEqual(installed, struct('Version', '1.8', ...
                'Folder', fullfile(testCase.Root, 'v1.8', 'GEDAI-master-1.8')));
            testCase.verifyEqual(onPath(), {installed.Folder});
        end
    end

    methods (Access = private)
        function installed = update(testCase, fetchLatest, consent, download)
        %UPDATE  ensureLatestGEDAI under the temporary root, with the newest
        %   release FETCHLATEST gives, CONSENT as the answer when asked, and
        %   DOWNLOAD (by default, a release named for its tag) as the
        %   download, all logged.
            log = testCase.Log;
            if nargin < 4
                download = @(url, folder) makeTagArchive(url, folder);
            end
            installed = ensureLatestGEDAI('Root', testCase.Root, 'FetchLatest', fetchLatest, ...
                'Consent', @(version) answer(log, version, consent), ...
                'Download', @(url, folder) logged(log, download, url, folder));
        end
    end
end

% ======================================================================= %
function fetch = newest(version, pluginVersion)
%NEWEST  A FetchLatest giving VERSION, whose archive's plugin file declares
%   PLUGINVERSION (VERSION unless given), carried in the URL.
    if nargin < 2
        pluginVersion = version;
    end
    fetch = @() struct('Version', version, 'Url', sprintf( ...
        'https://example.invalid/GEDAI-master-%s.zip#plugin=%s', version, pluginVersion));
end

function latest = unreachable() %#ok<STOUT>
    error('EnsureLatestGEDAITest:offline', 'GitHub cannot be reached (a test).');
end

function ok = answer(log, version, consent)
    log('consent') = [log('consent'), {version}]; %#ok<NASGU>  a containers.Map: the case's own log
    ok = consent;
end

function logged(log, download, url, folder)
    log('download') = [log('download'), {url}]; %#ok<NASGU>  a containers.Map: the case's own log
    download(url, folder);
end

function makeTagArchive(url, folder)
%MAKETAGARCHIVE  What unzipping a tag's archive into FOLDER gives: one
%   folder named GEDAI-master-<version>, here with the plugin file the URL
%   asks for.
    parts = regexp(url, 'GEDAI-master-([\d.]+)\.zip#plugin=([\d.]+)$', 'tokens', 'once');
    makeRelease(fullfile(folder, ['GEDAI-master-' parts{1}]), parts{2});
end

function failingDownload(url, ~)
    error('EnsureLatestGEDAITest:download', 'Could not download %s (a test).', url);
end

function folder = makeRelease(folder, pluginVersion)
%MAKERELEASE  A stand-in GEDAI release in FOLDER, its plugin file
%   declaring PLUGINVERSION as GEDAI's own does.
    mkdir(fullfile(folder, 'auxiliaries'));
    writelines('function GEDAI(), end', fullfile(folder, 'GEDAI.m'));
    writelines(sprintf('vers = ''GEDAI v%s - May 2026'';', pluginVersion), ...
        fullfile(folder, 'eegplugin_GEDAI.m'));
end

function [printed, installed] = printedBy(call) %#ok<INUSD>  called inside evalc
%PRINTEDBY  What CALL prints to the command window, and what it returns.
    installed = [];
    printed = evalc('installed = call();');
end

function folders = onPath()
%ONPATH  The folder of every GEDAI on the path, the one that runs first.
    folders = reshape(cellfun(@fileparts, cellstr(which('GEDAI', '-all')), ...
        'UniformOutput', false), 1, []);
    folders = folders(~cellfun(@isempty, folders));
end
