classdef CoherenceTopographyChainingTest < matlab.unittest.TestCase
%COHERENCETOPOGRAPHYCHAININGTEST  CrossCorrelation and Covariance must not
%   carry forward CoherenceTopography's own EEG.CohTopoValues (and its
%   CohTopo* siblings) when run on a CoherenceTopography result.
%
%   THE BUG THIS PINS, the same class CoherenceChainingTest.m first caught
%   between CoherenceMap and CoherenceTopography. CrossCorrelation.m and
%   Covariance.m have no DataFormat gate of their own (only "has .data"),
%   so chaining either onto a CoherenceTopography result is reachable, and
%   neither used to clear the inherited CohTopo* fields. AlakazamPlotter.
%   plotEpoched checks CoherenceTopography's id-or-.CohTopoValues branch
%   before either of theirs, so a stale, non-empty .CohTopoValues left in
%   place would route a fresh CrossCorrelation/Covariance result to
%   CoherenceTopographyView instead of its own view.
%
%   Run with: runtests('tests/CoherenceTopographyChainingTest.m').
%
%   See also COHERENCECHAININGTEST, TIMEFREQUENCYCHAININGTEST,
%   ALAKAZAMPLOTTER, TRANSTOOLS.CLEARFOREIGNRESULTFIELDS.

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            for p = {fullfile(root, 'src', 'Transformations', 'CoherenceTopography'), ...
                     fullfile(root, 'src', 'Transformations', 'CrossCorrelation'), ...
                     fullfile(root, 'src', 'Transformations', 'Covariance'), ...
                     fullfile(root, 'src', 'Transformations'), ...
                     fullfile(root, 'tests', 'fixtures')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
        end
    end

    methods (Test)
        function crossCorrelationClearsAnInheritedCoherenceTopography(testCase)
            topoResult = testCase.coherenceTopographyResult();

            out = CrossCorrelation(topoResult, xcorrOpts());

            testCase.verifyCleared(out);
            testCase.verifyTrue(isfield(out, 'xcorr'));
        end

        function covarianceClearsAnInheritedCoherenceTopography(testCase)
            topoResult = testCase.coherenceTopographyResult();

            out = Covariance(topoResult, covOpts());

            testCase.verifyCleared(out);
            testCase.verifyTrue(isfield(out, 'covariance'));
        end
    end

    methods (Access = private)
        function topoResult = coherenceTopographyResult(testCase)
            EEG = coherenceFixture();
            topoResult = CoherenceTopography(EEG, topoOpts());
            testCase.assertTrue(isfield(topoResult, 'CohTopoValues'), ...
                'test setup: CoherenceTopography should have produced .CohTopoValues.');
        end

        function verifyCleared(testCase, out)
            for f = {'CohTopoValues', 'CohTopoChanlocs', 'CohTopoDrawn', 'CohTopoFreqs', 'CohTopoRef', ...
                    'CohTopoLimit', 'CohTopoRefAmp', 'CohTopoAmpFreqs', 'CohTopoBins', 'CohTopoBinLabels'}
                testCase.verifyFalse(isfield(out, f{1}), sprintf('%s should have been cleared', f{1}));
            end
        end
    end
end

function EEG = coherenceFixture()
%COHERENCEFIXTURE  3-channel (real 10-5 labels), 250 Hz, EPOCHED, one bin.
    EEG = makeTestEEG('nbchan', 3, 'trials', 4, 'labels', {'Fz', 'Cz', 'Pz'}, ...
        'DataFormat', 'EPOCHED');
    EEG.bindesc = struct('index', 1, 'label', 'Bin1', 'trials', 1:EEG.trials, 'combo', []);
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
