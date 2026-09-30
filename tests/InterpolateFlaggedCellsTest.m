classdef InterpolateFlaggedCellsTest < matlab.unittest.TestCase
%INTERPOLATEFLAGGEDCELLSTEST  TransTools.InterpolateFlaggedCells, which
%   rebuilds flagged channels of flagged trials from their neighbours, and
%   TransTools.RecordInterpolated, which records that it did.
%
%   Trials that share a set of bad channels are interpolated in one call
%   rather than one call each. The spline weights depend only on which
%   channels are bad, and eeg_interp applies them sample by sample, so the
%   two must agree to rounding; that is checked here against the one-call-
%   per-trial loop this replaced, on a montage where the sets repeat.
%
%   Run with: runtests('tests/InterpolateFlaggedCellsTest.m').
%
%   See also TRANSTOOLS.INTERPOLATEFLAGGEDCELLS, TRANSTOOLS.RECORDINTERPOLATED.

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            for p = {fullfile(root, 'src', 'Transformations'), ...
                     fullfile(root, 'src', 'Support'), ...
                     fullfile(root, 'src'), ...
                     fullfile(root, 'tests', 'fixtures')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
        end
    end

    methods (Test)
        function groupingGivesWhatOneCallPerTrialGave(testCase)
            testCase.requireEeglab();
            EEG = makeScalpEEG('trials', 12, 'seed', 41);
            flags = false(EEG.nbchan, EEG.trials);
            flags(9, [2 5 7 11]) = true;          % C3 alone, four times
            flags([1 2], [3 8]) = true;           % Fp1 and Fp2 together, twice
            flags(15, 12) = true;                 % Pz once

            grouped = TransTools.InterpolateFlaggedCells(EEG, flags);

            expected = EEG.data;
            for t = find(any(flags, 1))
                oneTrial = EEG;
                oneTrial.data = EEG.data(:, :, t);
                oneTrial.trials = 1;
                oneTrial = eeg_interp(oneTrial, find(flags(:, t)), 'spherical');
                expected(flags(:, t), :, t) = oneTrial.data(flags(:, t), :);
            end
            testCase.verifyEqual(grouped.data, expected, 'AbsTol', 1e-9);
        end

        function unflaggedCellsAreUntouched(testCase)
            testCase.requireEeglab();
            EEG = makeScalpEEG('trials', 6, 'seed', 42);
            flags = false(EEG.nbchan, EEG.trials);
            flags(9, [2 4]) = true;

            out = TransTools.InterpolateFlaggedCells(EEG, flags);

            testCase.verifyEqual(out.data(~flags(:, 1), :, 1), EEG.data(~flags(:, 1), :, 1));
            testCase.verifyEqual(out.data(:, :, [1 3 5 6]), EEG.data(:, :, [1 3 5 6]));
        end

        function whatWasRebuiltIsRecorded(testCase)
            testCase.requireEeglab();
            EEG = makeScalpEEG('trials', 6, 'seed', 43);
            flags = false(EEG.nbchan, EEG.trials);
            flags(9, [2 4]) = true;

            [out, n] = TransTools.InterpolateFlaggedCells(EEG, flags);

            testCase.verifyEqual(n, 2);
            testCase.verifyEqual(out.etc.alz.interpolated, flags);
        end

        % ---- the record ---------------------------------------------------
        function aSecondRoundIsAddedToTheFirst(testCase)
            EEG = struct('data', zeros(3, 10, 4), 'etc', struct());
            first = false(3, 4);  first(1, 2) = true;
            second = false(3, 4); second(3, 4) = true;

            EEG = TransTools.RecordInterpolated(EEG, first);
            EEG = TransTools.RecordInterpolated(EEG, second);

            testCase.verifyEqual(EEG.etc.alz.interpolated, first | second);
        end

        function aRecordOfAnotherShapeIsDroppedNotMisaligned(testCase)
        %ARECORDOFANOTHERSHAPEISDROPPEDNOTMISALIGNED  A mask written before a
        %   channel edit or a resample describes a different dataset.
            EEG = struct('data', zeros(3, 10, 4), 'etc', struct('alz', struct('interpolated', true(5, 4))));
            flags = false(3, 4); flags(2, 1) = true;

            EEG = TransTools.RecordInterpolated(EEG, flags);

            testCase.verifyEqual(EEG.etc.alz.interpolated, flags);
        end

        function aForeignEtcFieldDoesNotError(testCase)
            EEG = struct('data', zeros(2, 5, 3), 'etc', 'written by some toolbox');

            EEG = TransTools.RecordInterpolated(EEG, true(2, 3));

            testCase.verifyEqual(EEG.etc.alz.interpolated, true(2, 3));
        end
    end

    methods (Access = private)
        function requireEeglab(testCase)
            try
                EEGLabEnvironment.ensure();
            catch
            end
            testCase.assumeTrue(exist('eeg_interp', 'file') == 2 && exist('pop_chanedit', 'file') == 2, ...
                'EEGLAB is not on the path, so interpolation cannot be exercised.');
        end
    end
end
