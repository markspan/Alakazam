classdef TimeFrequencyChainingTest < matlab.unittest.TestCase
%TIMEFREQUENCYCHAININGTEST  Every other EPOCHED "id-or-field" transformation
%   (SpectralMeasure, CoherenceMap, CoherenceTopography, CrossCorrelation,
%   Covariance) must not carry forward TimeFrequency's own EEG.ersp/.freqs
%   when run on a TimeFrequency result.
%
%   THE BUG THIS PINS, generalised from CoherenceChainingTest.m's own header
%   comment. TimeFrequency.m does EEG = input, then adds .ersp/.freqs and
%   nothing else touches them; none of the five transformations above used
%   to clear them either, so chaining any one of them onto a TimeFrequency
%   result (reachable for all five: TimeFrequency needs only EPOCHED data
%   with bins, no reference channel, which is the same or a subset of what
%   each of the five itself needs) left the final struct carrying BOTH
%   TimeFrequency's fields and its own.
%
%   AlakazamPlotter.plotEpoched checks TimeFrequency's id-or-.ersp branch
%   SECOND, right after the Quarto-report check and before every one of
%   these five's own branch -- so a fresh result from any of them, left
%   carrying a stale, non-empty .ersp, would route to TimeFrequencyView
%   instead of its own view.
%
%   Run with: runtests('tests/TimeFrequencyChainingTest.m').
%
%   See also COHERENCECHAININGTEST, COHERENCEMAPCHAININGTEST,
%   COHERENCETOPOGRAPHYCHAININGTEST, ALAKAZAMPLOTTER,
%   TRANSTOOLS.CLEARFOREIGNRESULTFIELDS.

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            for p = {fullfile(root, 'src', 'Transformations', 'TimeFrequency'), ...
                     fullfile(root, 'src', 'Transformations', 'SpectralMeasure'), ...
                     fullfile(root, 'src', 'Transformations', 'CoherenceMap'), ...
                     fullfile(root, 'src', 'Transformations', 'CoherenceTopography'), ...
                     fullfile(root, 'src', 'Transformations', 'CrossCorrelation'), ...
                     fullfile(root, 'src', 'Transformations', 'Covariance'), ...
                     fullfile(root, 'src', 'Transformations'), ...
                     fullfile(root, 'tests', 'fixtures')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
        end
    end

    methods (Test)
        function spectralMeasureClearsAnInheritedTimeFrequency(testCase)
            tf = testCase.timeFrequencyResult();

            out = SpectralMeasure(tf, spectralOpts());

            testCase.verifyFalse(isfield(out, 'ersp'));
            testCase.verifyFalse(isfield(out, 'freqs'));
            testCase.verifyTrue(isfield(out, 'spectralMeasures'));
        end

        function coherenceMapClearsAnInheritedTimeFrequency(testCase)
            tf = testCase.timeFrequencyResult();

            out = CoherenceMap(tf, mapOpts());

            testCase.verifyFalse(isfield(out, 'ersp'));
            testCase.verifyFalse(isfield(out, 'freqs'));
            testCase.verifyTrue(isfield(out, 'coherence'));
        end

        function coherenceTopographyClearsAnInheritedTimeFrequency(testCase)
            tf = testCase.timeFrequencyResult();

            out = CoherenceTopography(tf, topoOpts());

            testCase.verifyFalse(isfield(out, 'ersp'));
            testCase.verifyFalse(isfield(out, 'freqs'));
            testCase.verifyTrue(isfield(out, 'CohTopoValues'));
        end

        function crossCorrelationClearsAnInheritedTimeFrequency(testCase)
            tf = testCase.timeFrequencyResult();

            out = CrossCorrelation(tf, xcorrOpts());

            testCase.verifyFalse(isfield(out, 'ersp'));
            testCase.verifyFalse(isfield(out, 'freqs'));
            testCase.verifyTrue(isfield(out, 'xcorr'));
        end

        function covarianceClearsAnInheritedTimeFrequency(testCase)
            tf = testCase.timeFrequencyResult();

            out = Covariance(tf, covOpts());

            testCase.verifyFalse(isfield(out, 'ersp'));
            testCase.verifyFalse(isfield(out, 'freqs'));
            testCase.verifyTrue(isfield(out, 'covariance'));
        end
    end

    methods (Access = private)
        function tf = timeFrequencyResult(testCase)
            EEG = chainFixture();
            tf = TimeFrequency(EEG, tfOpts());
            testCase.assertTrue(isfield(tf, 'ersp'), ...
                'test setup: TimeFrequency should have produced .ersp.');
        end
    end
end

function EEG = chainFixture()
%CHAINFIXTURE  3-channel (real 10-5 labels, for CoherenceTopography's own
%   scalp-position lookup), 250 Hz, EPOCHED, one bin -- shared by every
%   transformation exercised here.
    EEG = makeTestEEG('nbchan', 3, 'trials', 4, 'labels', {'Fz', 'Cz', 'Pz'}, ...
        'DataFormat', 'EPOCHED');
    EEG.bindesc = struct('index', 1, 'label', 'Bin1', 'trials', 1:EEG.trials, 'combo', []);
end

function opts = tfOpts()
    opts = struct('MinFreq', 5, 'MaxFreq', 20, 'NumFreqs', 5, ...
        'MinCycles', 3, 'MaxCycles', 5, 'BaselineStart', -200, 'BaselineStop', 0);
end

function opts = mapOpts()
    opts = struct('RefChannel', 'Fz', 'Method', 'Wavelet', 'MinFreq', 5, 'MaxFreq', 20, ...
        'NumFreqs', 5, 'MinCycles', 3, 'MaxCycles', 5, 'WindowMs', 200, 'PadRatio', 2);
end

function opts = topoOpts()
    opts = struct('RefChannel', 'Fz', 'MinFreq', 5, 'MaxFreq', 20, 'Frequency', 0, ...
        'TimeStart', 0, 'TimeStop', 0);
end

function opts = xcorrOpts()
    opts = struct('RefChannel', 'Fz', 'Channels', {{}}, 'MaxLagMs', 40, ...
        'MinPairs', 20, 'Start', 0, 'Stop', 0);
end

function opts = covOpts()
    opts = struct('Channels', {{}}, 'Statistic', 'Covariance', 'Shrinkage', 'None', ...
        'Start', 0, 'Stop', 0);
end

function opts = spectralOpts()
    rows = {struct('label', 'R', 'freq', '10', 'channels', 'Fz')};
    opts = struct('rows', {rows}, 'fundamentals', '', 'refChannel', '', ...
        'method', 'Hann', 'tapers', 3, 'snrNeighbours', 10, 'snrGuard', 1);
end
