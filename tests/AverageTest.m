classdef AverageTest < matlab.unittest.TestCase
%AVERAGETEST  Unit tests for src/Transformations/Average/Average.m.
%
%   Average has no real options (unlike Baseline, it never checks
%   InitGuard's own INTERACTIVE output at all), so every test here calls it
%   with just the dataset -- Average(EEG) -- no opts struct needed.
%
%   Every expected value is RECOMPUTED here with the same primitive
%   MATLAB operations (mean/std) Average.m itself wraps, rather than a
%   hand-derived magic number: this checks that Average.m calls them
%   correctly (right dimension, right trial subset, right 'omitnan'), not
%   that some number I calculated by hand happens to match.
%
%   Run with: runtests('tests/AverageTest.m').
%
%   See also MAKETESTEEG, BASELINETEST.

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'Transformations', 'Average')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'Transformations')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'tests', 'fixtures')));
        end
    end

    methods (Test)
        function averagesAcrossAllTrialsWhenNoBins(testCase)
        %AVERAGESACROSSALLTRIALSWHENNOBINS  With no .bindesc at all, one
        %   average over every trial, plus the matching stErr/aSME and the
        %   DataFormat/trials/ntrials bookkeeping.
            EEG = makeTestEEG('nbchan', 2, 'trials', 5);

            [result, opts] = Average(EEG);

            testCase.verifyEqual(result.data, mean(EEG.data, 3, 'omitnan'), 'AbsTol', 1e-10);
            testCase.verifyEqual(result.stErr, std(EEG.data, 0, 3, 'omitnan') / sqrt(5), 'AbsTol', 1e-10);
            testCase.verifyEqual(result.DataFormat, "Averaged");
            testCase.verifyEqual(result.trials, 1);
            testCase.verifyEqual(result.ntrials, 5);
            testCase.verifyEqual(opts, 'Init', ...
                'Average has no real options; called with no opts it should report the Init sentinel back.');
        end

        function computesPerBinAverageOverOnlyItsOwnTrials(testCase)
        %COMPUTESPERBINAVERAGEOVERONLYITSOWNTRIALS  Two ordinary bins,
        %   trials [1 2] and [3 4] out of 4 -- each bin's average/stErr must
        %   come from only its own trial subset, not all four.
            EEG = makeTestEEG('nbchan', 2, 'trials', 4);
            EEG.bindesc(1) = struct('index', 1, 'label', 'A', 'trials', [1 2], 'combo', []);
            EEG.bindesc(2) = struct('index', 2, 'label', 'B', 'trials', [3 4], 'combo', []);

            [result, ~] = Average(EEG);

            testCase.verifyEqual(result.data(:, :, 1), mean(EEG.data(:, :, [1 2]), 3, 'omitnan'), 'AbsTol', 1e-10);
            testCase.verifyEqual(result.data(:, :, 2), mean(EEG.data(:, :, [3 4]), 3, 'omitnan'), 'AbsTol', 1e-10);
            testCase.verifyEqual(result.stErr(:, :, 1), ...
                std(EEG.data(:, :, [1 2]), 0, 3, 'omitnan') / sqrt(2), 'AbsTol', 1e-10);
            testCase.verifyEqual(result.bindesc(1).n, 2);
            testCase.verifyEqual(result.bindesc(2).n, 2);
        end

        function computesCombinationBinAsWeightedSum(testCase)
        %COMPUTESCOMBINATIONBINASWEIGHTEDSUM  bin3 = bin1 - bin2: its
        %   average/stErr are derived from bins 1 and 2's own already-
        %   computed averages, not from any trials of its own (it has
        %   none), and its .n is a signed-count string, not 0.
            EEG = makeTestEEG('nbchan', 2, 'trials', 4);
            EEG.bindesc(1) = struct('index', 1, 'label', 'A', 'trials', [1 2], 'combo', []);
            EEG.bindesc(2) = struct('index', 2, 'label', 'B', 'trials', [3 4], 'combo', []);
            EEG.bindesc(3) = struct('index', 3, 'label', 'A-B', 'trials', [], ...
                'combo', struct('bin', {1, 2}, 'coeff', {1, -1}));

            [result, ~] = Average(EEG);

            expectedAvg1 = mean(EEG.data(:, :, [1 2]), 3, 'omitnan');
            expectedAvg2 = mean(EEG.data(:, :, [3 4]), 3, 'omitnan');
            expectedStErr1 = std(EEG.data(:, :, [1 2]), 0, 3, 'omitnan') / sqrt(2);
            expectedStErr2 = std(EEG.data(:, :, [3 4]), 0, 3, 'omitnan') / sqrt(2);

            testCase.verifyEqual(result.data(:, :, 3), expectedAvg1 - expectedAvg2, 'AbsTol', 1e-10);
            testCase.verifyEqual(result.stErr(:, :, 3), ...
                sqrt(expectedStErr1 .^ 2 + expectedStErr2 .^ 2), 'AbsTol', 1e-10);
            testCase.verifyEqual(result.bindesc(3).n, '2-2');
        end

        function rejectsContinuousData(testCase)
            EEG = makeTestEEG('DataFormat', 'CONTINUOUS');
            testCase.verifyError(@() Average(EEG), 'Alakazam:Average');
        end

        function rejectsDataWithNoTrialsField(testCase)
            EEG = makeTestEEG();
            EEG = rmfield(EEG, 'trials');
            testCase.verifyError(@() Average(EEG), 'Alakazam:Average');
        end

        function averagesASpectrumPerBin(testCase)
        %AVERAGESASPECTRUMPERBIN  A frequency-domain dataset averages per
        %   bin, over that bin's own trials, like any other.
        %
        %   THERE IS NOTHING HERE TO DISTINGUISH VOLT FROM POWER, and that
        %   is the point. A guard once refused Volt spectra, reasoning that
        %   averaging voltage across trials is a coherent average that
        %   cancels whatever is not phase locked. Fourier.m stores
        %   abs(fft(...)), so phase is gone before Average ever sees the
        %   data and there is nothing left to cancel with: mean(|X|) is an
        %   ordinary incoherent mean amplitude spectrum that KEEPS induced
        %   activity. The coherent average is the other order entirely --
        %   Fourier of an already-averaged dataset -- which is a different
        %   and equally valid thing to compute. Average cannot tell the
        %   quantities apart, and does not need to.
            EEG = spectrumEEG();
            result = Average(EEG);

            testCase.verifyEqual(size(result.data, 3), 2, ...
                'One spectrum per bin.');
            testCase.verifyEqual(result.data(:, :, 1), ...
                mean(EEG.data(:, :, [1 2]), 3, 'omitnan'), 'AbsTol', 1e-10);
            testCase.verifyEqual(result.data(:, :, 2), ...
                mean(EEG.data(:, :, [3 4]), 3, 'omitnan'), 'AbsTol', 1e-10);
            testCase.verifyEqual(result.DataType, 'FrequencyDomain', ...
                'Averaging a spectrum leaves it a spectrum.');
        end
    end
end

function EEG = spectrumEEG()
%SPECTRUMEEG  A frequency-domain dataset, two bins over four trials.
%
%   Built by hand rather than by running Fourier: this file is about what
%   Average does with a spectrum, not about how the spectrum was made.
    EEG = makeTestEEG('nbchan', 2, 'trials', 4);
    EEG.DataType = 'FrequencyDomain';
    EEG.freqs = linspace(0, EEG.srate / 2, size(EEG.data, 2));
    EEG.bindesc = struct( ...
        'label',  {'A', 'B'}, ...
        'index',  {1, 2}, ...
        'trials', {[1 2], [3 4]});
end
