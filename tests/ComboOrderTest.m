classdef ComboOrderTest < matlab.unittest.TestCase
%COMBOORDERTEST  TransTools.ComboOrder: the one resolver Average,
%   ComputeErsp and Unfold.fitBins share for combination (difference) bins.
%
%   THE CASES THAT MATTER are the ones a plain "compute the combinations in
%   the order listed" would get wrong: a combination listed before the one it
%   depends on, bin numbers that are not positions, and a reference that
%   can never resolve. The last case runs Average end to end on a nested
%   combination, since the order only matters through what a caller computes
%   with it.
%
%   Run with: runtests('tests/ComboOrderTest.m').
%
%   See also TRANSTOOLS.COMBOORDER, AVERAGE, COMPUTEERSP, UNFOLD.FITBINS.

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            for p = {fullfile(root, 'src'), fullfile(root, 'src', 'Transformations'), ...
                     fullfile(root, 'src', 'Transformations', 'Average')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
        end
    end

    methods (Test)
        function withoutCombinationsThereIsNothingToDo(testCase)
            [steps, unresolved] = TransTools.ComboOrder(ComboOrderTest.bins({[], []}));

            testCase.verifyEmpty(steps);
            testCase.verifyEmpty(unresolved);
            testCase.verifyEmpty(TransTools.ComboOrder(struct('index', {1, 2}, 'label', {'A', 'B'})), ...
                'A bindesc without a combo field at all has none either.');
        end

        function aDifferenceNamesItsPartsAndCoefficients(testCase)
            steps = TransTools.ComboOrder(ComboOrderTest.bins({[], [], ComboOrderTest.combo([1 2], [1 -1])}));

            testCase.verifyEqual([steps.target], 3);
            testCase.verifyEqual(steps.parts, [1 2]);
            testCase.verifyEqual(steps.coeffs, [1 -1]);
        end

        function aCombinationWaitsForTheOneItUses(testCase)
        %ACOMBINATIONWAITSFORTHEONEITUSES  Bin 3 is listed first but uses bin
        %   4, itself a combination, so 4 has to be computed before it.
            steps = TransTools.ComboOrder(ComboOrderTest.bins({[], [], ...
                ComboOrderTest.combo([4 1], [1 -1]), ComboOrderTest.combo([1 2], [1 -1])}));

            testCase.verifyEqual([steps.target], [4 3]);
        end

        function referencesAreBinNumbersNotPositions(testCase)
            bindesc = ComboOrderTest.bins({[], [], ComboOrderTest.combo([20 10], [0.5 -0.5])});
            [bindesc.index] = deal(10, 20, 30);

            steps = TransTools.ComboOrder(bindesc);

            testCase.verifyEqual(steps.parts, [2 1]);
            testCase.verifyEqual(steps.coeffs, [0.5 -0.5]);
        end

        function anUnknownBinOrACycleIsUnresolved(testCase)
            [steps, unresolved] = TransTools.ComboOrder(ComboOrderTest.bins({[], [], ...
                ComboOrderTest.combo([1 9], [1 -1]), ...          % bin 9 does not exist
                ComboOrderTest.combo([5 1], [1 -1]), ...          % 4 uses 5 ...
                ComboOrderTest.combo([4 2], [1 -1]), ...          % ... and 5 uses 4
                ComboOrderTest.combo([1 2], [1 1])}));

            testCase.verifyEqual([steps.target], 6);
            testCase.verifyEqual(unresolved, [3 4 5]);
        end

        function averageComputesANestedCombination(testCase)
        %AVERAGECOMPUTESANESTEDCOMBINATION  C = A - B, then D = C - A, with D
        %   listed first: D must come out as -B, and say which counts it is
        %   made of.
            EEG = struct('data', reshape(1:16, 2, 2, 4), 'trials', 4, 'pnts', 2, 'nbchan', 2, ...
                'srate', 100, 'times', [0 10], 'DataFormat', 'EPOCHED');
            EEG.bindesc = ComboOrderTest.bins({[], [], ComboOrderTest.combo([4 1], [1 -1]), ...
                ComboOrderTest.combo([1 2], [1 -1])});
            [EEG.bindesc.trials] = deal([1 2], [3 4], [], []);

            averaged = Average(EEG);

            testCase.verifyEqual(averaged.data(:, :, 4), averaged.data(:, :, 1) - averaged.data(:, :, 2));
            testCase.verifyEqual(averaged.data(:, :, 3), -averaged.data(:, :, 2), 'AbsTol', 1e-12);
            testCase.verifyEqual(averaged.bindesc(4).n, '2-2');
            testCase.verifyEqual(averaged.bindesc(3).n, '2-2-2');
        end
    end

    methods (Static)
        function bindesc = bins(combos)
        %BINS  One bin per entry, numbered 1..N, with that entry as .combo.
            n = numel(combos);
            bindesc = struct('index', num2cell(1:n), ...
                'label', arrayfun(@(k) sprintf('bin %d', k), 1:n, 'UniformOutput', false), ...
                'combo', combos);
        end

        function c = combo(binNumbers, coeffs)
            c = struct('bin', num2cell(binNumbers), 'coeff', num2cell(coeffs));
        end
    end
end
