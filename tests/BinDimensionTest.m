classdef BinDimensionTest < matlab.unittest.TestCase
%BINDIMENSIONTEST  Telling a bin apart from a trial.
%
%   THE BUG THESE EXIST FOR was silent and user-visible: FourierView asked
%   "does this dataset have bindesc?" to decide whether its third dimension
%   was bins or trials. Both answers are yes. Fourier.m begins with
%   `output = input;`, so bindesc survives it on epoched data too, where it
%   describes which TRIAL belongs to which bin rather than describing the
%   third dimension at all. Single-trial spectra were therefore titled
%   "Bin 37 of 197" -- a wrong label with nothing to mark it as wrong.
%
%   Nothing here builds a UI. The mistake was in deciding a fact about the
%   dataset, not in drawing, so the fact is what is tested.
%
%   Run with: runtests('tests/BinDimensionTest.m').

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            repo = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(repo, 'src', 'Support')));
        end
    end

    methods (Access = private)
        function EEG = binned(~, format, nPages)
        %BINNED  A dataset with two bins, of the given DataFormat.
            EEG = struct();
            EEG.data = zeros(2, 8, nPages);
            EEG.DataFormat = format;
            EEG.bindesc = struct( ...
                'label',  {'Rare', 'Frequent'}, ...
                'index',  {1, 2}, ...
                'trials', {[1 3], [2 4]});
        end
    end

    methods (Test)
        function averagedDataIndexesBins(testCase)
            testCase.verifyTrue(thirdDimIsBins(testCase.binned('Averaged', 2)));
        end

        function epochedDataIndexesTrialsEvenThoughItHasBins(testCase)
        %   THE REGRESSION, stated as plainly as it can be: bins present,
        %   third dimension still trials.
            EEG = testCase.binned('EPOCHED', 4);
            testCase.verifyFalse(thirdDimIsBins(EEG), ...
                ['Epoched data carries bindesc but its 3rd dimension is trials; ' ...
                 'calling it bins is how single-trial spectra got titled "Bin 37 of 197".']);
        end

        function unbinnedDataIndexesTrials(testCase)
            EEG = struct('data', zeros(2, 8, 4), 'DataFormat', 'EPOCHED');
            testCase.verifyFalse(thirdDimIsBins(EEG));
        end

        function withoutDataFormatTheDimensionCountDecides(testCase)
        %   Datasets old enough to predate DataFormat: a guess, but a
        %   checked one.
            EEG = rmfield(testCase.binned('Averaged', 2), 'DataFormat');
            testCase.verifyTrue(thirdDimIsBins(EEG));

            EEG = rmfield(testCase.binned('EPOCHED', 4), 'DataFormat');
            testCase.verifyFalse(thirdDimIsBins(EEG));
        end

        function aTrialReportsTheBinItIsIn(testCase)
            EEG = testCase.binned('EPOCHED', 4);
            testCase.verifyEqual(trialBins(EEG, 1), 1);
            testCase.verifyEqual(trialBins(EEG, 2), 2);
            testCase.verifyEqual(trialBins(EEG, 3), 1);
        end

        function aTrialInTwoBinsReportsBoth(testCase)
        %   A combination bin overlapping a base one. Naming only the first
        %   would be a confident half-truth.
            EEG = testCase.binned('EPOCHED', 4);
            EEG.bindesc(3) = struct('label', 'All rare-ish', 'index', 3, ...
                'trials', [1 2 3]);
            testCase.verifyEqual(trialBins(EEG, 1), [1 3]);
            testCase.verifyEqual(trialBins(EEG, 4), 2);
        end

        function aTrialInNoBinReportsNothing(testCase)
            EEG = testCase.binned('EPOCHED', 5);
            testCase.verifyEmpty(trialBins(EEG, 5));
        end

        function membershipFallsBackToPerEpochBiniTags(testCase)
        %   Datasets whose bins carry no explicit trial list.
            EEG = testCase.binned('EPOCHED', 4);
            [EEG.bindesc.trials] = deal([]);
            EEG.epoch = struct('bini', {1, 2, [1 2], 2});
            testCase.verifyEqual(trialBins(EEG, 1), 1);
            testCase.verifyEqual(trialBins(EEG, 3), [1 2]);
            testCase.verifyEqual(trialBins(EEG, 4), 2);
        end

        function noBinsMeansNoMembership(testCase)
            EEG = struct('data', zeros(2, 8, 4), 'DataFormat', 'EPOCHED');
            testCase.verifyEmpty(trialBins(EEG, 1));
        end
    end
end
