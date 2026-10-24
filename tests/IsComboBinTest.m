classdef IsComboBinTest < matlab.unittest.TestCase
%ISCOMBOBINTEST  TransTools.IsComboBin: the one definition of a combination
%   bin that DefineBins, every consumer of bins and the Deconvolve plugin
%   share.
%
%   THE CASES THAT MATTER are the shapes a dataset can arrive in: bins from
%   DefineBins, a bindesc with no .combo field (an ERPset import), no bins at
%   all, and a single bin, since callers ask both of the whole bindesc and of
%   EEG.bindesc(b). The mask must always be a row of one entry per bin, so
%   that find() and logical indexing work without reshaping.
%
%   Run with: runtests('tests/IsComboBinTest.m').
%
%   See also TRANSTOOLS.ISCOMBOBIN, TRANSTOOLS.COMBOORDER.

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            for p = {fullfile(root, 'src', 'Transformations'), ...
                     fullfile(root, 'src', 'Transformations', 'DefineBins')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
        end
    end

    methods (Test)
        function marksExactlyTheCombinations(testCase)
            bindesc = IsComboBinTest.bins({[], IsComboBinTest.difference(), []});

            testCase.verifyEqual(TransTools.IsComboBin(bindesc), [false true false]);
        end

        function isARowWhateverTheShapeOfTheBins(testCase)
            bindesc = reshape(IsComboBinTest.bins({IsComboBinTest.difference(), []}), [], 1);

            testCase.verifyEqual(TransTools.IsComboBin(bindesc), [true false], ...
                'A column bindesc still gives a row, as every caller indexes with it.');
        end

        function aSingleBinGivesAScalar(testCase)
            bindesc = IsComboBinTest.bins({[], IsComboBinTest.difference()});

            testCase.verifyFalse(TransTools.IsComboBin(bindesc(1)));
            testCase.verifyTrue(TransTools.IsComboBin(bindesc(2)));
        end

        function binsWithoutAComboFieldAreAllOrdinary(testCase)
            imported = struct('index', {1, 2}, 'label', {'A', 'B'});

            testCase.verifyEqual(TransTools.IsComboBin(imported), [false false]);
        end

        function noBinsGiveAnEmptyMask(testCase)
            testCase.verifyEqual(TransTools.IsComboBin([]), false(1, 0));
            testCase.verifyEqual(TransTools.IsComboBin(IsComboBinTest.bins({})), false(1, 0));
        end

        function readsADefineBinsSpecAsWellAsABindesc(testCase)
            spec = DefineBinsEngine.parseSpec(sprintf([ ...
                'bin 1 "Frequent" 11\n' ...
                'bin 2 "Rare" 12\n' ...
                'bin 3 "Rare_minus_Frequent" = bin 2 - bin 1']));

            testCase.verifyEqual(TransTools.IsComboBin(spec.bins), [false false true]);
        end
    end

    methods (Static, Access = private)
        function bindesc = bins(combos)
            n = numel(combos);
            % A row of combinations: {} alone is 0 x 0, which struct() will not
            % pair with the 1 x 0 index and label lists of no bins.
            bindesc = struct('index', num2cell(1:n), ...
                'label', arrayfun(@(k) sprintf('Bin %d', k), 1:n, 'UniformOutput', false), ...
                'combo', reshape(combos, 1, n));
        end

        function c = difference()
            c = struct('bin', {1, 3}, 'coeff', {1, -1});
        end
    end
end
