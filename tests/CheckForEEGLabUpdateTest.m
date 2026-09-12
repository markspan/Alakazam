classdef CheckForEEGLabUpdateTest < matlab.unittest.TestCase
%CHECKFOREEGLABUPDATETEST  Unit tests for src/checkForEEGLabUpdate.m.
%
%   The network is never touched: every case injects a canned release
%   struct, shaped like plugin_getweb('update') answers, through the
%   function's FETCHLATESTRELEASE argument.
%
%   The installed version is injected too, so the comparison logic is tested
%   without EEGLAB on the path at all. Only one case exercises the real
%   eeg_getversion() default, and it carries its own assumption; a
%   class-level EEGLAB gate used to make every case here skip whenever this
%   file was run on its own, and a skipped test is not a passing one.
%
%   Run with: runtests('tests/CheckForEEGLabUpdateTest.m').
%
%   See also CHECKFOREEGLABUPDATE, ALAKAZAM/ONUPDATE.

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src')));
        end
    end

    methods (Test)
        function aNewerAdvertisedVersionIsAnUpdate(testCase)
            info = checkForEEGLabUpdate(testCase.release('2099.9.9'), '2026.1.0');

            testCase.verifyTrue(info.CheckSucceeded);
            testCase.verifyTrue(info.UpdateAvailable);
            testCase.verifyEqual(info.LatestVersion, '2099.9.9');
            testCase.verifyEqual(info.CurrentVersion, '2026.1.0');
        end

        function theInstalledVersionIsNotAnUpdate(testCase)
        %THEINSTALLEDVERSIONISNOTANUPDATE  Being offered exactly what is
        %   already installed must not count as an update.
            info = checkForEEGLabUpdate(testCase.release('2026.1.0'), '2026.1.0');

            testCase.verifyTrue(info.CheckSucceeded);
            testCase.verifyFalse(info.UpdateAvailable);
        end

        function withoutAnOverrideTheVersionComesFromEeglab(testCase)
        %WITHOUTANOVERRIDETHEVERSIONCOMESFROMEEGLAB  The one case that
        %   exercises the real default path, so the override cannot hide a
        %   broken eeg_getversion call. Assumed, not required: every other
        %   case here runs without EEGLAB.
            testCase.assumeNotEmpty(which('eeg_getversion'), ...
                'EEGLAB (eeg_getversion) is not on the path.');

            info = checkForEEGLabUpdate(testCase.release('2099.9.9'));

            testCase.verifyTrue(info.CheckSucceeded);
            testCase.verifyEqual(info.CurrentVersion, char(string(eeg_getversion())));
        end

        function aDevelopmentCheckoutIsNeverOfferedAnUpdate(testCase)
        %ADEVELOPMENTCHECKOUTISNEVEROFFEREDANUPDATE  eeg_getversion answers
        %   'dev' for a git checkout of EEGLAB, which does not order against
        %   a release number; replacing it would throw away someone's work.
        %
        %   The installed version is injected rather than read from this
        %   machine. Gating on the local EEGLAB actually BEING a dev checkout
        %   made this case skip on every ordinary install, which is not the
        %   same as passing.
            info = checkForEEGLabUpdate(testCase.release('2099.9.9'), 'dev');

            testCase.verifyTrue(info.CheckSucceeded);
            testCase.verifyEqual(info.CurrentVersion, 'dev');
            testCase.verifyFalse(info.UpdateAvailable, ...
                'A dev checkout must never be offered a release to overwrite it with.');
        end

        function anInjectedVersionIsWhatGetsCompared(testCase)
        %ANINJECTEDVERSIONISWHATGETSCOMPARED  Guards the seam itself: if the
        %   override were ignored, the dev case above would silently go back
        %   to testing this machine's own EEGLAB.
            same = checkForEEGLabUpdate(testCase.release('2050.1.0'), '2050.1.0');
            older = checkForEEGLabUpdate(testCase.release('2050.1.0'), '2049.9.9');

            testCase.verifyEqual(same.CurrentVersion, '2050.1.0');
            testCase.verifyFalse(same.UpdateAvailable);
            testCase.verifyEqual(older.CurrentVersion, '2049.9.9');
            testCase.verifyTrue(older.UpdateAvailable);
        end

        function anUnreachableFeedIsNotAnError(testCase)
        %ANUNREACHABLEFEEDISNOTANERROR  No network must report "could not
        %   check", not raise: onUpdate shows a gentle dialog for this.
            info = checkForEEGLabUpdate(@() error('Alakazam:test', 'no network'), '2026.1.0');

            testCase.verifyFalse(info.CheckSucceeded);
            testCase.verifyFalse(info.UpdateAvailable);
        end

        function aResponseOfAnUnexpectedShapeIsNotAnError(testCase)
            for bad = {struct(), struct('version', '2099.9.9'), 42, []}
                info = checkForEEGLabUpdate(@() bad{1}, '2026.1.0');
                testCase.verifyFalse(info.CheckSucceeded, ...
                    'A response with no usable version/zip must fail the check, not throw.');
            end
        end

        function anEmptyVersionOrZipFailsTheCheck(testCase)
            testCase.verifyFalse(checkForEEGLabUpdate( ...
                @() struct('version', '', 'zip', 'https://x/e.zip'), '2026.1.0').CheckSucceeded);
            testCase.verifyFalse(checkForEEGLabUpdate( ...
                @() struct('version', '2099.9.9', 'zip', ''), '2026.1.0').CheckSucceeded);
        end

        function aPlainHttpDownloadLinkIsUpgradedToHttps(testCase)
        %APLAINHTTPDOWNLOADLINKISUPGRADEDTOHTTPS  SCCN has served this over
        %   http before; eeglab_update rewrites it the same way rather than
        %   trusting what it is handed.
            info = checkForEEGLabUpdate(@() struct('version', '2099.9.9', ...
                'zip', 'http://sccn.ucsd.edu/eeglab/currentversion/eeglab_current.zip'), ...
                '2026.1.0');

            testCase.verifyTrue(startsWith(info.DownloadUrl, 'https://'));
            testCase.verifyFalse(contains(info.DownloadUrl, 'http://'));
        end

        function severalAdvertisedReleasesTakeTheFirst(testCase)
        %SEVERALADVERTISEDRELEASESTAKETHEFIRST  plugin_getweb can answer with
        %   more than one entry; eeglab_update takes the first, so match it.
            two = [struct('version', '2099.9.9', 'zip', 'https://x/a.zip'), ...
                   struct('version', '1999.1.1', 'zip', 'https://x/b.zip')];
            info = checkForEEGLabUpdate(@() two, '2026.1.0');

            testCase.verifyEqual(info.LatestVersion, '2099.9.9');
            testCase.verifyEqual(info.DownloadUrl, 'https://x/a.zip');
        end

        function theCriticalFlagAndNotesAreCarriedThrough(testCase)
            info = checkForEEGLabUpdate(@() struct('version', '2099.9.9', ...
                'zip', 'https://x/e.zip', 'critical', 1, ...
                'releasenotes', 'Fixes a thing.'), '2026.1.0');

            testCase.verifyTrue(info.Critical);
            testCase.verifyEqual(info.Notes, 'Fixes a thing.');
        end

        function aReleaseWithoutTheOptionalFieldsIsStillUsable(testCase)
            info = checkForEEGLabUpdate(testCase.release('2099.9.9'), '2026.1.0');

            testCase.verifyTrue(info.CheckSucceeded);
            testCase.verifyFalse(info.Critical, 'Absent means not critical.');
            testCase.verifyEmpty(info.Notes);
        end
    end

    methods (Access = private)
        function h = release(~, version)
        %RELEASE  A canned plugin_getweb('update') answer for VERSION, with
        %   only the two fields the check actually requires.
            h = @() struct('version', version, ...
                'zip', 'https://sccn.ucsd.edu/eeglab/currentversion/eeglab_current.zip');
        end
    end
end
