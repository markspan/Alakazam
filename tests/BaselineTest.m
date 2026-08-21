classdef BaselineTest < matlab.unittest.TestCase
%BASELINETEST  Unit tests for src/Transformations/Baseline/Baseline.m.
%
%   Baseline is a good first example: pure arithmetic (no EEGLAB pop_*
%   call, so no EEGLAB installation needed to run these), and its
%   [EEG, opts] = Baseline(input, opts) contract means calling it directly
%   with a real OPTS struct (TransTools.InitGuard's "replay" path) skips
%   TransformOptionsDialog entirely -- no UI involved in these tests at all.
%
%   Run with: runtests('tests/BaselineTest.m'), or runtests('tests') to run
%   every test file in the folder, or right-click > Run in the editor.
%
%   See also MAKETESTEEG, TRANSTOOLS.INITGUARD.

    methods (TestClassSetup)
        function addSourceToPath(testCase)
        %ADDSOURCETOPATH  Put Baseline.m and the +TransTools package (for
        %   TransTools.InitGuard) on the path for this test class only --
        %   PathFixture restores the original path automatically once every
        %   test in this class has run, so this cannot leak into other
        %   test classes or the user's own session.
            root = fileparts(fileparts(mfilename('fullpath'))); % repo root
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'Transformations', 'Baseline')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'Transformations')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'tests', 'fixtures')));
        end
    end

    methods (Test)
        function windowMeanBecomesZero(testCase)
        %WINDOWMEANBECOMESZERO  After correction, the mean over the SAME
        %   window Baseline.m itself used (replicated here, not assumed to
        %   be samples 1:zeropoint -- see Baseline.m's own start/stop
        %   formula) should be ~0 for every channel and trial.
            EEG = makeTestEEG();
            opts = struct('Start', -100, 'Stop', 0);

            [result, returnedOpts] = Baseline(EEG, opts);

            [~, zp] = min(abs(EEG.times));
            startIdx = max(1, floor(opts.Start * EEG.srate / 1000) + zp);
            stopIdx  = min(size(EEG.data, 2), floor(opts.Stop * EEG.srate / 1000) + zp);

            windowMean = mean(result.data(:, startIdx:stopIdx, :), 2);
            testCase.verifyEqual(windowMean, zeros(EEG.nbchan, 1, EEG.trials), 'AbsTol', 1e-10);
            testCase.verifyEqual(returnedOpts, opts, ...
                'Baseline should return the same opts it was given on replay, unchanged.');
        end

        function subtractsExactlyTheWindowMean(testCase)
        %SUBTRACTSEXACTLYTHEWINDOWMEAN  A stronger check than the window's
        %   own mean being ~0: every sample in the whole trial (not just
        %   the window) should equal the ORIGINAL sample minus that same
        %   constant -- confirms the correction is a uniform per-trial
        %   shift, not something that only looks right inside the window.
            EEG = makeTestEEG('nbchan', 2, 'trials', 2);
            opts = struct('Start', -100, 'Stop', 0);

            [result, ~] = Baseline(EEG, opts);

            [~, zp] = min(abs(EEG.times));
            startIdx = max(1, floor(opts.Start * EEG.srate / 1000) + zp);
            stopIdx  = min(size(EEG.data, 2), floor(opts.Stop * EEG.srate / 1000) + zp);

            for c = 1:EEG.nbchan
                for tr = 1:EEG.trials
                    bl = mean(EEG.data(c, startIdx:stopIdx, tr));
                    expected = EEG.data(c, :, tr) - bl;
                    testCase.verifyEqual(squeeze(result.data(c, :, tr)), expected, 'AbsTol', 1e-10);
                end
            end
        end

        function rejectsContinuousData(testCase)
        %REJECTSCONTINUOUSDATA  Baseline needs segmented (epoched) data;
        %   continuous input should throw a specific, identifiable error
        %   rather than silently doing the wrong thing.
            EEG = makeTestEEG('DataFormat', 'CONTINUOUS');
            testCase.verifyError(@() Baseline(EEG, struct('Start', -100, 'Stop', 0)), 'Alakazam:Baseline');
        end

        function rejectsDataWithNoTrialsField(testCase)
        %REJECTSDATAWITHNOTRIALSFIELD  A dataset missing .trials cannot be
        %   treated as segmented data even if .data happens to be 3-D.
            EEG = makeTestEEG();
            EEG = rmfield(EEG, 'trials');
            testCase.verifyError(@() Baseline(EEG, struct('Start', -100, 'Stop', 0)), 'Alakazam:Baseline');
        end
    end
end
