classdef AlakazamUpdateCheckTest < matlab.unittest.TestCase
%ALAKAZAMUPDATECHECKTEST  Unit tests for src/isAlakazamVersionNewer.m and
%   src/checkForAlakazamUpdate.m.
%
%   checkForAlakazamUpdate never hits the real network here: every test
%   supplies its own FETCHLATESTRELEASE handle returning a canned struct, so
%   the suite does not depend on GitHub being reachable or on this
%   repository's actual release history.
%
%   Run with: runtests('tests/AlakazamUpdateCheckTest.m').

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src')));
        end
    end

    methods (Test)
        % -- isAlakazamVersionNewer -----------------------------------

        function aHigherPatchIsNewer(testCase)
            testCase.verifyTrue(isAlakazamVersionNewer('V0.4.4', 'V0.4.3'));
        end

        function anEqualVersionIsNotNewer(testCase)
            testCase.verifyFalse(isAlakazamVersionNewer('V0.4.3', 'V0.4.3'));
        end

        function aLowerVersionIsNotNewer(testCase)
            testCase.verifyFalse(isAlakazamVersionNewer('V0.4.2', 'V0.4.3'));
        end

        function extraComponentsAreCompared(testCase)
        %EXTRACOMPONENTSARECOMPARED  This repository has shipped four-part
        %   tags (V0.4.3.6), not just the three the VERSION_FALLBACK example
        %   in alakazamVersion.m shows -- the comparison must not assume a
        %   fixed arity.
            testCase.verifyTrue(isAlakazamVersionNewer('V0.4.3.6', 'V0.4.3'));
            testCase.verifyFalse(isAlakazamVersionNewer('V0.4.3', 'V0.4.3.6'));
        end

        function aGitDescribeSuffixOnTheCurrentSideDoesNotConfuseIt(testCase)
        %AGITDESCRIBESUFFIXONTHECURRENTSIDE  A developer checkout a few
        %   commits past the last tag reports e.g. 'V0.4.3-7-gabc1234-dirty'
        %   (see alakazamVersion.m); the trailing text must be ignored
        %   rather than compared as if it were more numeric components.
            testCase.verifyFalse(isAlakazamVersionNewer('V0.4.3', 'V0.4.3-7-gabc1234-dirty'));
            testCase.verifyTrue(isAlakazamVersionNewer('V0.5.0', 'V0.4.3-7-gabc1234-dirty'));
        end

        function lowercaseVIsAccepted(testCase)
            testCase.verifyTrue(isAlakazamVersionNewer('v0.4.4', 'v0.4.3'));
        end

        function anUnparsableTagReadsAsNotNewer(testCase)
        %ANUNPARSABLETAGREADSASNOTNEWER  A malformed response should not
        %   crash the comparison; it should just fail to look newer.
            testCase.verifyFalse(isAlakazamVersionNewer('not-a-version', 'V0.4.3'));
        end

        % -- checkForAlakazamUpdate ------------------------------------

        function reportsAnAvailableUpdate(testCase)
            fetch = @() struct( ...
                'tag_name', 'V99.0.0', ...
                'body', 'Release notes.', ...
                'assets', struct( ...
                    'name', 'Alakazam-V99.0.0.zip', ...
                    'browser_download_url', 'https://example.invalid/Alakazam-V99.0.0.zip'));

            info = checkForAlakazamUpdate(fetch);

            testCase.verifyTrue(info.CheckSucceeded);
            testCase.verifyTrue(info.UpdateAvailable);
            testCase.verifyEqual(info.LatestVersion, 'V99.0.0');
            testCase.verifyEqual(info.DownloadUrl, 'https://example.invalid/Alakazam-V99.0.0.zip');
            testCase.verifyEqual(info.Notes, 'Release notes.');
        end

        function reportsUpToDateWhenTheReleaseIsNotNewer(testCase)
            current = alakazamVersion().Version;
            fetch = @() struct( ...
                'tag_name', current, ...
                'body', '', ...
                'assets', struct( ...
                    'name', 'Alakazam.zip', ...
                    'browser_download_url', 'https://example.invalid/Alakazam.zip'));

            info = checkForAlakazamUpdate(fetch);

            testCase.verifyTrue(info.CheckSucceeded);
            testCase.verifyFalse(info.UpdateAvailable);
        end

        function aNetworkFailureIsReportedAsAFailedCheckNotAnError(testCase)
            fetch = @() error('Simulated:NoNetwork', 'no network');

            info = checkForAlakazamUpdate(fetch);

            testCase.verifyFalse(info.CheckSucceeded);
            testCase.verifyFalse(info.UpdateAvailable);
        end

        function aReleaseWithNoZipAssetIsReportedAsAFailedCheck(testCase)
        %ARELEASEWITHNOZIPASSET  A draft or source-only release has nothing
        %   to offer downloadAlakazamUpdate; the button should say "couldn't
        %   check" rather than dangle a Download option with no target.
            fetch = @() struct( ...
                'tag_name', 'V99.0.0', ...
                'body', '', ...
                'assets', struct( ...
                    'name', 'notes.txt', ...
                    'browser_download_url', 'https://example.invalid/notes.txt'));

            info = checkForAlakazamUpdate(fetch);

            testCase.verifyFalse(info.CheckSucceeded);
        end

        function currentVersionAlwaysComesFromAlakazamVersion(testCase)
            fetch = @() struct( ...
                'tag_name', 'V0.0.1', 'body', '', ...
                'assets', struct('name', 'x.zip', 'browser_download_url', 'https://example.invalid/x.zip'));

            info = checkForAlakazamUpdate(fetch);

            testCase.verifyEqual(info.CurrentVersion, alakazamVersion().Version);
        end
    end
end
