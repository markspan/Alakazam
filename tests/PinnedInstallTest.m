classdef PinnedInstallTest < matlab.unittest.TestCase
%PINNEDINSTALLTEST  A pinned toolbox is used at its pinned release, not at
%   whichever install happens to be on disk.
%
%   Every pinned toolbox unzips into a folder named after its release
%   (fieldtrip-20260924, EEG-Clean-Tools-0.57.0). EEGLabEnvironment.
%   findInstalled returned the first install it found under the toolbox's
%   folder, which with two side by side was the older one, so moving a pin
%   changed nothing on a machine that had the previous one. Only the pinned
%   release's folder counts now, and the older install stays on disk.
%
%   The installs here are stand-ins under a temporary USERPROFILE (where
%   findInstalled looks), so the real ones are not touched, and the path is
%   left as it was found.
%
%   Run with: runtests('tests/PinnedInstallTest.m').
%
%   See also EEGLABENVIRONMENT.FINDINSTALLED, TRANSTOOLS.FIELDTRIPRELEASE,
%   PREPTOOLBOX.

    properties (Constant)
        Root = fileparts(fileparts(mfilename('fullpath')))
    end

    properties
        TempHome = ''
    end

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            for p = {fullfile(PinnedInstallTest.Root, 'src'), ...
                     fullfile(PinnedInstallTest.Root, 'src', 'Transformations'), ...
                     fullfile(PinnedInstallTest.Root, 'src', 'Transformations', 'PREP')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
        end
    end

    methods (TestMethodSetup)
        function isolateTheHomeFolder(testCase)
            previousProfile = getenv('USERPROFILE');
            previousPath = path();
            testCase.addTeardown(@() setenv('USERPROFILE', previousProfile));
            testCase.addTeardown(@() path(previousPath));
            folder = testCase.applyFixture( ...
                matlab.unittest.fixtures.TemporaryFolderFixture()).Folder;
            setenv('USERPROFILE', folder);
            testCase.TempHome = folder;
        end
    end

    methods (Test)
        function anOlderReleaseIsNotTakenForThePinnedOne(testCase)
            old = testCase.fakeInstall('fieldtrip', 'fieldtrip-20260812', '', 'ft_defaults.m');

            testCase.verifyEmpty(EEGLabEnvironment.findInstalled('fieldtrip', 'ft_defaults.m', ...
                'fieldtrip-20260924'), 'The previous pin''s install is not the pinned one.');
            testCase.verifyEqual(EEGLabEnvironment.findInstalled('fieldtrip', 'ft_defaults.m'), old, ...
                'Without a release, any install still counts.');
        end

        function thePinnedReleaseIsFoundBesideAnOlderOne(testCase)
            testCase.fakeInstall('fieldtrip', 'fieldtrip-20260812', '', 'ft_defaults.m');
            pinned = testCase.fakeInstall('fieldtrip', 'fieldtrip-20260924', '', 'ft_defaults.m');

            testCase.verifyEqual(EEGLabEnvironment.findInstalled('fieldtrip', 'ft_defaults.m', ...
                'fieldtrip-20260924'), pinned);
        end

        function anInstalledPinIsAttachedNotDownloaded(testCase)
            pinned = testCase.fakeInstall('fieldtrip', 'fieldtrip-20260924', '', 'ft_defaults.m');

            % An address that cannot be fetched: any attempt to download fails.
            EEGLabEnvironment.installFromZip('https://alakazam.invalid/none.zip', 'fieldtrip', ...
                'ft_defaults.m', 'fieldtrip-20260924');

            testCase.verifyTrue(contains(path(), pinned), 'The pinned install is put on the path.');
        end

        function prepIsNotUsedFromAnOlderRelease(testCase)
            spec = prepToolbox();
            testCase.assumeEmpty(which(spec.Probe), ...
                'PREP is on this path already, so whether it is found cannot be tested.');
            testCase.assumeEmpty(which('prepPipeline'), ...
                'PREP''s entry point is on this path already (an EEGLAB plugin, say).');
            testCase.fakePrep('EEG-Clean-Tools-0.56.0');

            testCase.verifyFalse(TransTools.ToolboxAvailable(spec), ...
                'An install of the previous pin is not used.');

            testCase.fakePrep(spec.Release);
            testCase.verifyTrue(TransTools.ToolboxAvailable(spec), ...
                'The pinned release is attached, its subfolders with it.');
        end

        function eachPinNamesTheFolderItsArchiveUnzipsInto(testCase)
        %EACHPINNAMESTHEFOLDERITSARCHIVEUNZIPSINTO  A release folder that
        %   does not match the archive would never be found, and the
        %   toolbox would be downloaded again on every use.
            spec = prepToolbox();
            testCase.verifyEqual(spec.Release, ['EEG-Clean-Tools-' spec.Version], ...
                'GitHub unzips tag vX into <repository>-X.');
            testCase.verifySubstring(spec.Url, ['/v' spec.Version '.zip']);

            release = TransTools.fieldTripRelease();
            testCase.verifyMatches(release, '^fieldtrip-\d{8}$');
            source = fileread(fullfile(PinnedInstallTest.Root, 'src', 'Transformations', ...
                '+TransTools', 'ensureFieldTrip.m'));
            testCase.verifySubstring(source, '''https://download.fieldtriptoolbox.org/'' release ''.zip''', ...
                'The archive downloaded is the release looked for.');

            manual = fileread(fullfile(PinnedInstallTest.Root, 'manual', 'chapters', '_02-installation.qmd'));
            testCase.verifySubstring(manual, strrep(release, 'fieldtrip-', ''), ...
                'The manual''s table of toolboxes names the pinned FieldTrip build.');
        end
    end

    methods (Access = private)
        function folder = fakeInstall(testCase, target, release, subfolder, probeFile)
        %FAKEINSTALL  A stand-in install: PROBEFILE, a function doing
        %   nothing, in Documents/MATLAB/<target>/<release>/<subfolder>.
            folder = fullfile(testCase.TempHome, 'Documents', 'MATLAB', target, release);
            if ~isempty(subfolder)
                folder = fullfile(folder, subfolder);
            end
            if ~isfolder(folder)
                mkdir(folder);
            end
            [~, name] = fileparts(probeFile);
            fid = fopen(fullfile(folder, probeFile), 'w');
            fprintf(fid, 'function %s(varargin)\nend\n', name);
            fclose(fid);
        end

        function fakePrep(testCase, release)
        %FAKEPREP  PREP as its archive lays it out: prepPipeline in the
        %   PrepPipeline folder, the helpers in its subfolders.
            folder = testCase.fakeInstall('PrepPipeline', release, 'PrepPipeline', 'prepPipeline.m');
            mkdir(fullfile(folder, 'utilities'));
            fid = fopen(fullfile(folder, 'utilities', 'getPrepDefaults.m'), 'w');
            fprintf(fid, 'function getPrepDefaults(varargin)\nend\n');
            fclose(fid);
        end
    end
end
