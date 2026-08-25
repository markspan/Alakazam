classdef ArtefactDetectTest < matlab.unittest.TestCase
%ARTEFACTDETECTTEST  Unit tests for
%   src/Transformations/ArtefactDetect/ArtefactDetect.m.
%
%   Each detector test deliberately uses a large, obvious artefact against
%   a low threshold, rather than a value placed exactly at the boundary:
%   the moving-window detectors (step function, peak-to-peak) evaluate
%   overlapping windows whose exact alignment with an injected artefact
%   this file does not try to hand-predict, so tests are written to be
%   robust to that alignment rather than assume a precise window position.
%
%   Run with: runtests('tests/ArtefactDetectTest.m').
%
%   See also MAKETESTEEG.

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'Transformations', 'ArtefactDetect')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'Transformations')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'tests', 'fixtures')));
        end
    end

    methods (Test)
        function cleanDataIsUntouched(testCase)
        %CLEANDATAISUNTOUCHED  With no artefact injected and generous
        %   default thresholds, nothing should become NaN.
            EEG = makeTestEEG('nbchan', 2, 'trials', 3);
            opts = struct('Method', {{'Absolute threshold'}}, 'Minimum', -100, 'Maximum', 100, ...
                'Scope', 'Whole epoch');

            [result, ~] = ArtefactDetect(EEG, opts);

            testCase.verifyFalse(any(isnan(result.data(:))));
            testCase.verifyEqual(result.data, EEG.data, 'AbsTol', 1e-10);
        end

        function absoluteThresholdRejectsWholeEpoch(testCase)
        %ABSOLUTETHRESHOLDREJECTSWHOLEEPOCH  One sample over Maximum, in
        %   one channel of one trial, condemns the WHOLE trial (every
        %   channel) under the default "Whole epoch" scope; the other
        %   trial is untouched.
            EEG = makeTestEEG('nbchan', 2, 'trials', 2);
            EEG.data(1, 5, 1) = 500; % channel 1, sample 5, trial 1: well over Maximum
            opts = struct('Method', {{'Absolute threshold'}}, 'Minimum', -100, 'Maximum', 100, ...
                'Scope', 'Whole epoch');

            [result, ~] = ArtefactDetect(EEG, opts);

            testCase.verifyTrue(all(isnan(result.data(:, :, 1)), 'all'));
            testCase.verifyEqual(result.data(:, :, 2), EEG.data(:, :, 2), 'AbsTol', 1e-10);
        end

        function absoluteThresholdPerChannelScopeOnlyFlagsThatChannel(testCase)
        %ABSOLUTETHRESHOLDPERCHANNELSCOPEONLYFLAGSTHATCHANNEL  Same
        %   artefact, but Scope = "This channel only": only channel 1
        %   becomes NaN, channel 2 (same trial) is untouched.
            EEG = makeTestEEG('nbchan', 2, 'trials', 2);
            EEG.data(1, 5, 1) = 500;
            opts = struct('Method', {{'Absolute threshold'}}, 'Minimum', -100, 'Maximum', 100, ...
                'Scope', 'This channel only');

            [result, ~] = ArtefactDetect(EEG, opts);

            testCase.verifyTrue(all(isnan(result.data(1, :, 1))));
            testCase.verifyEqual(result.data(2, :, 1), EEG.data(2, :, 1), 'AbsTol', 1e-10);
            testCase.verifyEqual(result.data(:, :, 2), EEG.data(:, :, 2), 'AbsTol', 1e-10);
        end

        function backwardCompatMinMaxOnlyStructActsAsAbsoluteThreshold(testCase)
        %BACKWARDCOMPATMINMAXONLYSTRUCTACTSASABSOLUTETHRESHOLD  An old
        %   options struct with no .Method field at all (pre-dating the
        %   multi-detector option) should still behave as absolute
        %   threshold, per ArtefactDetect's own documented compatibility.
            EEG = makeTestEEG('nbchan', 1, 'trials', 2);
            EEG.data(1, 5, 1) = 500;
            opts = struct('Minimum', -100, 'Maximum', 100); % no .Method

            [result, ~] = ArtefactDetect(EEG, opts);

            testCase.verifyTrue(all(isnan(result.data(:, :, 1)), 'all'));
            testCase.verifyEqual(result.data(:, :, 2), EEG.data(:, :, 2), 'AbsTol', 1e-10);
        end

        function sampleToSampleDetectsASingleSampleJump(testCase)
        %SAMPLETOSAMPLEDETECTSASINGLESAMPLEJUMP  A single-sample spike
        %   (a jump far exceeding Threshold, then back down) should trip
        %   the sample-to-sample detector.
            EEG = makeTestEEG('nbchan', 1, 'trials', 2);
            EEG.data(:) = 0; % flat baseline in both trials, no jumps at all
            EEG.data(1, 10, 2) = 150; % trial 2 only: a lone spike
            opts = struct('Method', {{'Sample-to-sample'}}, 'Threshold', 100, 'Scope', 'Whole epoch');

            [result, ~] = ArtefactDetect(EEG, opts);

            testCase.verifyFalse(any(isnan(result.data(:, :, 1)), 'all'));
            testCase.verifyTrue(all(isnan(result.data(:, :, 2)), 'all'));
        end

        function stepFunctionDetectsAMeanLevelShift(testCase)
        %STEPFUNCTIONDETECTSAMEANLEVELSHIFT  A large, sustained step in
        %   the middle of the epoch (not just one sample) should trip the
        %   step-function detector regardless of exactly where the moving
        %   window lands, since the jump (1000) is far larger than the
        %   threshold (50).
            EEG = makeTestEEG('nbchan', 1, 'trials', 2);
            EEG.data(:) = 0;
            half = round(size(EEG.data, 2) / 2);
            EEG.data(1, half:end, 2) = 1000; % trial 2 only: sustained step partway through
            opts = struct('Method', {{'Step function'}}, 'Threshold', 50, 'Window', 200, ...
                'Step', 50, 'Scope', 'Whole epoch');

            [result, ~] = ArtefactDetect(EEG, opts);

            testCase.verifyFalse(any(isnan(result.data(:, :, 1)), 'all'));
            testCase.verifyTrue(all(isnan(result.data(:, :, 2)), 'all'));
        end

        function movingWindowPeakToPeakDetectsALocalSpike(testCase)
        %MOVINGWINDOWPEAKTOPEAKDETECTSALOCALSPIKE  One large local spike
        %   should trip the peak-to-peak detector once a scanning window
        %   contains it, again using a spike (1000) far larger than the
        %   threshold (50) so exact window alignment does not matter.
            EEG = makeTestEEG('nbchan', 1, 'trials', 2);
            EEG.data(:) = 0;
            EEG.data(1, 50, 2) = 1000; % trial 2 only
            opts = struct('Method', {{'Moving-window peak-to-peak'}}, 'Threshold', 50, ...
                'Window', 200, 'Step', 50, 'Scope', 'Whole epoch');

            [result, ~] = ArtefactDetect(EEG, opts);

            testCase.verifyFalse(any(isnan(result.data(:, :, 1)), 'all'));
            testCase.verifyTrue(all(isnan(result.data(:, :, 2)), 'all'));
        end

        function testWindowRestrictsWhereDetectionLooks(testCase)
        %TESTWINDOWRESTRICTSWHEREDETECTIONLOOKS  An artefact placed
        %   OUTSIDE the [TestStart, TestStop] window must not be flagged;
        %   the same size artefact placed INSIDE it, in a different
        %   trial, must be.
            EEG = makeTestEEG('nbchan', 1, 'trials', 2); % times: -200..596 ms
            EEG.data(1, 5, 1)   = 500; % near the start of the epoch (~ -184 ms): outside the test window below
            [~, midIdx] = min(abs(EEG.times - 200)); % a sample near +200 ms: inside the test window below
            EEG.data(1, midIdx, 2) = 500;
            opts = struct('Method', {{'Absolute threshold'}}, 'Minimum', -100, 'Maximum', 100, ...
                'Scope', 'Whole epoch', 'TestStart', 100, 'TestStop', 300);

            [result, ~] = ArtefactDetect(EEG, opts);

            testCase.verifyFalse(any(isnan(result.data(:, :, 1)), 'all'), ...
                'An artefact outside the test window should not be flagged.');
            testCase.verifyTrue(all(isnan(result.data(:, :, 2)), 'all'), ...
                'An artefact inside the test window should be flagged.');
        end

        function rejectsContinuousData(testCase)
            EEG = makeTestEEG('DataFormat', 'CONTINUOUS');
            opts = struct('Method', {{'Absolute threshold'}}, 'Minimum', -100, 'Maximum', 100, ...
                'Scope', 'Whole epoch');
            testCase.verifyError(@() ArtefactDetect(EEG, opts), 'Alakazam:ArtefactDetect');
        end

        % ---- empty detector selection ---------------------------------
        function noDetectorsTickedChangesNothing(testCase)
        %NODETECTORSTICKEDCHANGESNOTHING  An empty Method used to fall back
        %   to the absolute threshold, so "I ticked nothing" silently became
        %   "reject anything outside +/-100 uV over the whole epoch". On real
        %   data that discarded 45% of a subject's trials on a threshold
        %   nobody chose. An empty selection is now a genuine no-op.
            EEG = makeTestEEG('nbchan', 2, 'trials', 3);
            EEG.data(1, 10, 2) = 5000;   % way outside the default +/-100 uV
            opts = struct('Method', {{}}, 'Minimum', -100, 'Maximum', 100, ...
                'Scope', 'Whole epoch');

            [result, ~] = ArtefactDetect(EEG, opts);

            testCase.verifyEqual(result.data, EEG.data);
            testCase.verifyFalse(any(isnan(result.data), 'all'));
        end

        function anEmptyMethodIsNotTreatedAsAnAbsentOne(testCase)
        %ANEMPTYMETHODISNOTTREATEDASANABSENTONE  The trap that made the
        %   first attempt at the fix above a no-fix: TransTools.FieldOr
        %   returns its DEFAULT for a present-but-empty field, so reading
        %   Method through it turns {} straight back into
        %   {'Absolute threshold'}. normaliseOptions therefore has to test
        %   isfield directly, and this pins that the two cases stay apart.
            EEG = makeTestEEG('nbchan', 1, 'trials', 2);
            EEG.data(1, 10, 1) = 5000;

            emptyMethod = struct('Method', {{}}, 'Minimum', -100, 'Maximum', 100, ...
                'Scope', 'Whole epoch');
            absentMethod = struct('Minimum', -100, 'Maximum', 100, 'Scope', 'Whole epoch');

            untouched = ArtefactDetect(EEG, emptyMethod);
            rejected  = ArtefactDetect(EEG, absentMethod);

            testCase.verifyFalse(any(isnan(untouched.data), 'all'), ...
                'An EMPTY Method means no detectors, so nothing should be rejected.');
            testCase.verifyTrue(all(isnan(rejected.data(:, :, 1)), 'all'), ...
                'An ABSENT Method is the old Minimum/Maximum-only struct and must still detect.');
        end

        function aBlankMethodStringIsAlsoANoOp(testCase)
        %ABLANKMETHODSTRINGISALSOANOOP  toMethodList drops blank entries, so
        %   a stored {''} (or a bare '') reduces to an empty selection and
        %   must take the same no-op path, not fall through to a detector.
            EEG = makeTestEEG('nbchan', 1, 'trials', 2);
            EEG.data(1, 10, 1) = 5000;
            opts = struct('Method', {{''}}, 'Minimum', -100, 'Maximum', 100, ...
                'Scope', 'Whole epoch');

            [result, ~] = ArtefactDetect(EEG, opts);

            testCase.verifyFalse(any(isnan(result.data), 'all'));
        end
    end
end
