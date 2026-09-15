classdef CoherenceMapChainingTest < matlab.unittest.TestCase
%COHERENCEMAPCHAININGTEST  CrossCorrelation and Covariance must not carry
%   forward CoherenceMap's own EEG.coherence (and its cohFreqs/cohTimes/
%   cohRef/cohMethod siblings) when run on a CoherenceMap result.
%
%   THE BUG THIS PINS, the same class CoherenceChainingTest.m first caught
%   between CoherenceMap and CoherenceTopography. CrossCorrelation.m and
%   Covariance.m have no DataFormat gate of their own (only "has .data"),
%   so chaining either onto a CoherenceMap result is reachable, and neither
%   used to clear the inherited .coherence family. AlakazamPlotter.
%   plotEpoched checks CoherenceMap's id-or-.coherence branch before either
%   of theirs, so a stale, non-empty .coherence left in place would route a
%   fresh CrossCorrelation/Covariance result to CoherenceView instead of its
%   own view.
%
%   Run with: runtests('tests/CoherenceMapChainingTest.m').
%
%   See also COHERENCECHAININGTEST, TIMEFREQUENCYCHAININGTEST,
%   ALAKAZAMPLOTTER, TRANSTOOLS.CLEARFOREIGNRESULTFIELDS.

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            for p = {fullfile(root, 'src', 'Transformations', 'CoherenceMap'), ...
                     fullfile(root, 'src', 'Transformations', 'CrossCorrelation'), ...
                     fullfile(root, 'src', 'Transformations', 'Covariance'), ...
                     fullfile(root, 'src', 'Transformations'), ...
                     fullfile(root, 'tests', 'fixtures')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
        end
    end

    methods (Test)
        function crossCorrelationClearsAnInheritedCoherenceMap(testCase)
            mapResult = testCase.coherenceMapResult();

            out = CrossCorrelation(mapResult, xcorrOpts());

            testCase.verifyFalse(isfield(out, 'coherence'));
            testCase.verifyFalse(isfield(out, 'cohFreqs'));
            testCase.verifyFalse(isfield(out, 'cohTimes'));
            testCase.verifyFalse(isfield(out, 'cohRef'));
            testCase.verifyFalse(isfield(out, 'cohMethod'));
            testCase.verifyTrue(isfield(out, 'xcorr'));
        end

        function covarianceClearsAnInheritedCoherenceMap(testCase)
            mapResult = testCase.coherenceMapResult();

            out = Covariance(mapResult, covOpts());

            testCase.verifyFalse(isfield(out, 'coherence'));
            testCase.verifyFalse(isfield(out, 'cohFreqs'));
            testCase.verifyFalse(isfield(out, 'cohTimes'));
            testCase.verifyFalse(isfield(out, 'cohRef'));
            testCase.verifyFalse(isfield(out, 'cohMethod'));
            testCase.verifyTrue(isfield(out, 'covariance'));
        end
    end

    methods (Access = private)
        function mapResult = coherenceMapResult(testCase)
            EEG = coherenceFixture();
            mapResult = CoherenceMap(EEG, mapOpts());
            testCase.assertTrue(isfield(mapResult, 'coherence'), ...
                'test setup: CoherenceMap should have produced .coherence.');
        end
    end
end

function EEG = coherenceFixture()
%COHERENCEFIXTURE  3-channel (real 10-5 labels), 250 Hz, EPOCHED, one bin.
    EEG = makeTestEEG('nbchan', 3, 'trials', 4, 'labels', {'Fz', 'Cz', 'Pz'}, ...
        'DataFormat', 'EPOCHED');
    EEG.bindesc = struct('index', 1, 'label', 'Bin1', 'trials', 1:EEG.trials, 'combo', []);
end

function opts = mapOpts()
    opts = struct('RefChannel', 'Fz', 'Method', 'Wavelet', 'MinFreq', 5, 'MaxFreq', 20, ...
        'NumFreqs', 5, 'MinCycles', 3, 'MaxCycles', 5, 'WindowMs', 200, 'PadRatio', 2);
end

function opts = xcorrOpts()
    opts = struct('RefChannel', 'Fz', 'Channels', {{}}, 'MaxLagMs', 40, ...
        'MinPairs', 20, 'Start', 0, 'Stop', 0);
end

function opts = covOpts()
    opts = struct('Channels', {{}}, 'Statistic', 'Covariance', 'Shrinkage', 'None', ...
        'Start', 0, 'Stop', 0);
end
