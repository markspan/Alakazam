classdef CrossCorrelationChainingTest < matlab.unittest.TestCase
%CROSSCORRELATIONCHAININGTEST  Covariance must not carry forward
%   CrossCorrelation's own EEG.xcorr (and its xcorrSE/xcorrLags/xcorrRef/
%   xcorrLabels/xcorrBinLabels/xcorrTrials/xcorrPeakR/xcorrPeakLagMs/
%   xcorrWindowMs siblings) when run on a CrossCorrelation result.
%
%   THE BUG THIS PINS, the same class CoherenceChainingTest.m first caught
%   between CoherenceMap and CoherenceTopography. Covariance.m has no
%   DataFormat gate of its own (only "has .data" and ">=2 channels"), so
%   chaining it onto a CrossCorrelation result is reachable, and it used not
%   to clear the inherited .xcorr family. AlakazamPlotter.plotEpoched checks
%   CrossCorrelation's id-or-.xcorr branch before Covariance's own, so a
%   stale, non-empty .xcorr left in place would route a fresh Covariance
%   result to CrossCorrelationView instead of CovarianceView.
%
%   Run with: runtests('tests/CrossCorrelationChainingTest.m').
%
%   See also COHERENCECHAININGTEST, TIMEFREQUENCYCHAININGTEST,
%   ALAKAZAMPLOTTER, TRANSTOOLS.CLEARFOREIGNRESULTFIELDS.

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            for p = {fullfile(root, 'src', 'Transformations', 'CrossCorrelation'), ...
                     fullfile(root, 'src', 'Transformations', 'Covariance'), ...
                     fullfile(root, 'src', 'Transformations'), ...
                     fullfile(root, 'tests', 'fixtures')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
        end
    end

    methods (Test)
        function covarianceClearsAnInheritedCrossCorrelation(testCase)
            xcorrResult = testCase.crossCorrelationResult();

            out = Covariance(xcorrResult, covOpts());

            for f = {'xcorr', 'xcorrSE', 'xcorrLags', 'xcorrRef', 'xcorrLabels', ...
                    'xcorrBinLabels', 'xcorrTrials', 'xcorrPeakR', 'xcorrPeakLagMs', 'xcorrWindowMs'}
                testCase.verifyFalse(isfield(out, f{1}), sprintf('%s should have been cleared', f{1}));
            end
            testCase.verifyTrue(isfield(out, 'covariance'));
        end
    end

    methods (Access = private)
        function xcorrResult = crossCorrelationResult(testCase)
            EEG = fixture();
            xcorrResult = CrossCorrelation(EEG, xcorrOpts());
            testCase.assertTrue(isfield(xcorrResult, 'xcorr'), ...
                'test setup: CrossCorrelation should have produced .xcorr.');
        end
    end
end

function EEG = fixture()
%FIXTURE  3-channel, 250 Hz, EPOCHED, one bin.
    EEG = makeTestEEG('nbchan', 3, 'trials', 4, 'labels', {'Fz', 'Cz', 'Pz'}, ...
        'DataFormat', 'EPOCHED');
    EEG.bindesc = struct('index', 1, 'label', 'Bin1', 'trials', 1:EEG.trials, 'combo', []);
end

function opts = xcorrOpts()
    opts = struct('RefChannel', 'Fz', 'Channels', {{}}, 'MaxLagMs', 40, ...
        'MinPairs', 20, 'Start', 0, 'Stop', 0);
end

function opts = covOpts()
    opts = struct('Channels', {{}}, 'Statistic', 'Covariance', 'Shrinkage', 'None', ...
        'Start', 0, 'Stop', 0);
end
