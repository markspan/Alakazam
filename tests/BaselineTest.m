classdef BaselineTest < matlab.unittest.TestCase
%BASELINETEST  Unit tests for src/Transformations/Baseline/Baseline.m.
%
%   Baseline is pure arithmetic (no EEGLAB pop_* call, so no EEGLAB
%   installation needed to run these), and its [EEG, opts] =
%   Baseline(input, opts) contract means calling it directly with a real
%   OPTS struct (TransTools.InitGuard's "replay" path) skips the dialog.
%
%   THE WINDOW RULE is FieldTrip's and ERPLAB's: each end goes to the
%   nearest sample, the earlier on an exact tie, an end beyond the epoch to
%   the epoch's own end, and a window wholly outside the epoch is refused.
%   The cases below set integer times (4 ms apart at 250 Hz) so that a tie
%   is a tie and not a rounding accident; FieldTripReferenceTest checks the
%   same rule against ft_preprocessing itself.
%
%   Run with: runtests('tests/BaselineTest.m').
%
%   See also MAKETESTEEG, TRANSTOOLS.NEARESTSAMPLE.

    methods (TestClassSetup)
        function addSourceToPath(testCase)
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
        function subtractsExactlyTheWindowMean(testCase)
        %SUBTRACTSEXACTLYTHEWINDOWMEAN  Every sample of the trial, not just
        %   the window, is the original minus the window's mean: -100 to 0 ms
        %   at 250 Hz is samples -100, -96, ..., 0.
            EEG = testCase.epochs();
            opts = struct('Start', -100, 'Stop', 0);

            [result, returnedOpts] = Baseline(EEG, opts);

            window = EEG.times >= -100 & EEG.times <= 0;
            expected = EEG.data - mean(EEG.data(:, window, :), 2);
            testCase.verifyEqual(result.data, expected, 'AbsTol', 1e-12);
            testCase.verifyEqual(returnedOpts, opts, 'The options come back unchanged on replay.');
            testCase.verifyEqual(result.etc.alz.baseline.samplesMs, [-100 0]);
        end

        function eachEndGoesToTheNearestSample(testCase)
        %EACHENDGOESTOTHENEARESTSAMPLE  -149 to -51 ms: -148 is nearer than
        %   -152 and -52 nearer than -48, so the window is -148 to -52.
            EEG = testCase.epochs();
            result = Baseline(EEG, struct('Start', -149, 'Stop', -51));
            testCase.verifyEqual(result.etc.alz.baseline.samplesMs, [-148 -52]);
            window = EEG.times >= -148 & EEG.times <= -52;
            testCase.verifyEqual(result.data, EEG.data - mean(EEG.data(:, window, :), 2), 'AbsTol', 1e-12);
        end

        function aTieGoesToTheEarlierSample(testCase)
        %ATIEGOESTOTHEEARLIERSAMPLE  -150 and -50 ms lie exactly halfway
        %   between samples; both ends take the earlier one, -152 and -52.
            EEG = testCase.epochs();
            result = Baseline(EEG, struct('Start', -150, 'Stop', -50));
            testCase.verifyEqual(result.etc.alz.baseline.samplesMs, [-152 -52]);
        end

        function anEndBeyondTheEpochIsTheEpochsOwnEnd(testCase)
            EEG = testCase.epochs();
            result = Baseline(EEG, struct('Start', -500, 'Stop', 0));
            testCase.verifyEqual(result.etc.alz.baseline.samples(1), 1);
            testCase.verifyEqual(result.etc.alz.baseline.samplesMs, [-200 0]);
        end

        function aWindowOutsideTheEpochIsRefused(testCase)
            EEG = testCase.epochs();
            testCase.verifyError(@() Baseline(EEG, struct('Start', -500, 'Stop', -300)), 'Alakazam:Baseline');
            testCase.verifyError(@() Baseline(EEG, struct('Start', 700, 'Stop', 900)), 'Alakazam:Baseline');
        end

        function aStartAfterTheStopIsRefused(testCase)
            EEG = testCase.epochs();
            testCase.verifyError(@() Baseline(EEG, struct('Start', 0, 'Stop', -100)), 'Alakazam:Baseline');
        end

        function aRejectedSampleIsLeftOutOfTheMean(testCase)
        %AREJECTEDSAMPLEISLEFTOUTOFTHEMEAN  As FieldTrip's
        %   ft_preproc_baselinecorrect leaves it out: one NaN in the window of
        %   channel 1, trial 2 leaves that channel's other window samples to
        %   set the baseline, and stays NaN itself. A wholly rejected channel
        %   of a trial stays wholly NaN.
            EEG = testCase.epochs();
            window = find(EEG.times >= -100 & EEG.times <= 0);
            EEG.data(1, window(3), 2) = NaN;
            EEG.data(2, :, 3) = NaN;

            result = Baseline(EEG, struct('Start', -100, 'Stop', 0));

            kept = window([1:2, 4:end]);
            testCase.verifyEqual(result.data(1, :, 2), EEG.data(1, :, 2) - mean(EEG.data(1, kept, 2)), 'AbsTol', 1e-12);
            testCase.verifyTrue(isnan(result.data(1, window(3), 2)));
            testCase.verifyTrue(all(isnan(result.data(2, :, 3))));
        end

        function rejectsContinuousData(testCase)
            EEG = makeTestEEG('DataFormat', 'CONTINUOUS');
            testCase.verifyError(@() Baseline(EEG, struct('Start', -100, 'Stop', 0)), 'Alakazam:Baseline');
        end

        function rejectsDataWithNoTrialsField(testCase)
            EEG = makeTestEEG();
            EEG = rmfield(EEG, 'trials');
            testCase.verifyError(@() Baseline(EEG, struct('Start', -100, 'Stop', 0)), 'Alakazam:Baseline');
        end
    end

    methods (Access = private)
        function EEG = epochs(~)
        %EPOCHS  makeTestEEG's -200 to 596 ms at 250 Hz, with the times set
        %   as exact integers, 4 ms apart.
            EEG = makeTestEEG();
            EEG.times = -200:4:596;
        end
    end
end
