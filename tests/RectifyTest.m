classdef RectifyTest < matlab.unittest.TestCase
%RECTIFYTEST  Unit tests for src/Transformations/Rectify/Rectify.m.
%
%   Run with: runtests('tests/RectifyTest.m').

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            for p = {fullfile(root, 'src', 'Transformations', 'Rectify'), ...
                     fullfile(root, 'src', 'Transformations'), ...
                     fullfile(root, 'src', 'Support'), ...
                     fullfile(root, 'src', 'Dialogs'), ...
                     fullfile(root, 'tests', 'fixtures')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
        end
    end

    methods (Test)
        function fullWaveTakesTheMagnitude(testCase)
            EEG = testCase.fixture();
            out = Rectify(EEG, testCase.opts({'Fz'}, 'Full wave (|x|)'));

            fz = testCase.rowOf(EEG, 'Fz');
            testCase.verifyEqual(out.data(fz, :, :), abs(EEG.data(fz, :, :)), 'AbsTol', 1e-12);
        end

        function halfWaveZeroesTheNegatives(testCase)
            EEG = testCase.fixture();
            out = Rectify(EEG, testCase.opts({'Fz'}, 'Half wave (negatives to zero)'));

            fz = testCase.rowOf(EEG, 'Fz');
            expected = EEG.data(fz, :, :);
            expected(expected < 0) = 0;
            testCase.verifyEqual(out.data(fz, :, :), expected, 'AbsTol', 1e-12);
        end

        function squaredTakesTheSquare(testCase)
            EEG = testCase.fixture();
            out = Rectify(EEG, testCase.opts({'Fz'}, 'Squared (x^2)'));

            fz = testCase.rowOf(EEG, 'Fz');
            testCase.verifyEqual(out.data(fz, :, :), EEG.data(fz, :, :) .^ 2, 'AbsTol', 1e-10);
        end

        function squaredRecordsTheUnitChange(testCase)
        %SQUAREDRECORDSTHEUNITCHANGE  uV becomes uV^2, and nothing
        %   downstream can see that by looking at the numbers.
            EEG = testCase.fixture();

            squared = Rectify(EEG, testCase.opts({'Fz'}, 'Squared (x^2)'));
            full    = Rectify(EEG, testCase.opts({'Fz'}, 'Full wave (|x|)'));

            testCase.verifyEqual(squared.etc.alz.rectifyMode, 'squared');
            testCase.verifyTrue(squared.etc.alz.rectifySquared);
            testCase.verifyEqual(full.etc.alz.rectifyMode, 'full');
            testCase.verifyFalse(full.etc.alz.rectifySquared, ...
                'Only the squared mode changes the unit.');
        end

        function squaredKeepsRejectedSamplesRejected(testCase)
            EEG = testCase.fixture();
            fz = testCase.rowOf(EEG, 'Fz');
            EEG.data(fz, 12:18, 3) = NaN;

            out = Rectify(EEG, testCase.opts({'Fz'}, 'Squared (x^2)'));

            testCase.verifyTrue(all(isnan(out.data(fz, 12:18, 3))));
            testCase.verifyEqual(nnz(isnan(out.data)), nnz(isnan(EEG.data)));
        end

        function squaredIsNeverNegative(testCase)
        %SQUAREDISNEVERNEGATIVE  The point of the mode: sign is gone, so a
        %   later average measures magnitude instead of cancelling.
            EEG = testCase.fixture();
            out = Rectify(EEG, testCase.opts({'Fz', 'Pz', 'Oz'}, 'Squared (x^2)'));

            finite = out.data(isfinite(out.data));
            testCase.verifyGreaterThanOrEqual(min(finite), 0);
        end

        function unselectedChannelsAreUntouched(testCase)
            EEG = testCase.fixture();
            out = Rectify(EEG, testCase.opts({'Fz'}, 'Full wave (|x|)'));

            pz = testCase.rowOf(EEG, 'Pz');
            testCase.verifyEqual(out.data(pz, :, :), EEG.data(pz, :, :), ...
                'A channel that was not selected must be left exactly as it was.');
        end

        function rejectedSamplesStayRejected(testCase)
        %REJECTEDSAMPLESSTAYREJECTED  NaN is Alakazam's rejection marker; a
        %   rectified channel whose NaNs had been filled would re-enter
        %   averaging as real data.
            EEG = testCase.fixture();
            fz = testCase.rowOf(EEG, 'Fz');
            EEG.data(fz, 10:20, 2) = NaN;

            out = Rectify(EEG, testCase.opts({'Fz'}, 'Full wave (|x|)'));

            testCase.verifyTrue(all(isnan(out.data(fz, 10:20, 2))));
            testCase.verifyEqual(nnz(isnan(out.data)), nnz(isnan(EEG.data)), ...
                'Rectifying must not create or remove rejected samples.');
        end

        function halfWaveLeavesRejectedSamplesAsNaNNotZero(testCase)
        %HALFWAVELEAVESREJECTEDSAMPLESASNANNOTZERO  The half-wave branch
        %   assigns zero to negatives, and NaN < 0 is false -- but a naive
        %   implementation that tested ~(x >= 0) instead would turn every
        %   rejected sample into a real zero.
            EEG = testCase.fixture();
            fz = testCase.rowOf(EEG, 'Fz');
            EEG.data(fz, 5:8, 1) = NaN;

            out = Rectify(EEG, testCase.opts({'Fz'}, 'Half wave (negatives to zero)'));

            testCase.verifyTrue(all(isnan(out.data(fz, 5:8, 1))));
        end

        function theRectificationIsRecordedForAudit(testCase)
        %THERECTIFICATIONISRECORDEDFORAUDIT  A step that changes what the
        %   numbers MEAN while leaving them looking ordinary has to leave a
        %   trace -- the same argument InterpolateFlaggedCells makes.
            EEG = testCase.fixture();
            out = Rectify(EEG, testCase.opts({'Fz', 'Oz'}, 'Full wave (|x|)'));

            mask = out.etc.alz.rectified;
            testCase.assertEqual(numel(mask), out.nbchan);
            testCase.verifyTrue(mask(testCase.rowOf(EEG, 'Fz')));
            testCase.verifyTrue(mask(testCase.rowOf(EEG, 'Oz')));
            testCase.verifyFalse(mask(testCase.rowOf(EEG, 'Pz')));
            testCase.verifyEqual(out.etc.alz.rectifyMode, 'full');
        end

        function aSecondRectifyKeepsTheFirstInTheMask(testCase)
            EEG = testCase.fixture();
            once  = Rectify(EEG,  testCase.opts({'Fz'}, 'Full wave (|x|)'));
            twice = Rectify(once, testCase.opts({'Pz'}, 'Full wave (|x|)'));

            mask = twice.etc.alz.rectified;
            testCase.verifyTrue(mask(testCase.rowOf(EEG, 'Fz')), ...
                'The earlier rectification must not be forgotten.');
            testCase.verifyTrue(mask(testCase.rowOf(EEG, 'Pz')));
        end

        function whetherItRanBeforeAveragingIsRecorded(testCase)
        %WHETHERITRANBEFOREAVERAGINGISRECORDED  mean(|x|) is not |mean(x)|,
        %   so which side of Average this ran on changes what the channel
        %   means. Both are legitimate; which happened must be answerable.
            epoched = testCase.fixture();                       % 4 trials
            outEpoched = Rectify(epoched, testCase.opts({'Fz'}, 'Full wave (|x|)'));
            testCase.verifyTrue(outEpoched.etc.alz.rectifiedBeforeAveraging);

            averaged = testCase.fixture();
            averaged.data = mean(averaged.data, 3);
            averaged.trials = 1;
            outAveraged = Rectify(averaged, testCase.opts({'Fz'}, 'Full wave (|x|)'));
            testCase.verifyFalse(outAveraged.etc.alz.rectifiedBeforeAveraging);
        end

        function aStoredSelectionThatMatchesNothingIsANoOp(testCase)
        %ASTOREDSELECTIONTHATMATCHESNOTHINGISANOOP  So a template can cross
        %   a montage without stopping the branch -- the same choice
        %   Interpolate makes.
            EEG = testCase.fixture();
            out = Rectify(EEG, testCase.opts({'NoSuchChannel'}, 'Full wave (|x|)'));

            testCase.verifyEqual(out.data, EEG.data);
        end
    end

    methods (Access = private)
        function EEG = fixture(~)
            EEG = makeTestEEG('nbchan', 3, 'labels', {'Fz', 'Pz', 'Oz'});
            % makeTestEEG's signal sits on a +5 offset, so shift it to
            % straddle zero -- otherwise "rectify" has nothing to flip.
            EEG.data = EEG.data - 5;
        end

        function o = opts(~, channels, mode)
            o = struct('Channels', {channels}, 'Mode', mode);
        end

        function r = rowOf(~, EEG, label)
            r = find(strcmpi({EEG.chanlocs.labels}, label), 1);
        end
    end
end
