classdef CoherenceChainingTest < matlab.unittest.TestCase
%COHERENCECHAININGTEST  CoherenceMap and CoherenceTopography must not carry
%   forward each other's result-specific fields when one is run on the
%   other's output.
%
%   THE BUG THIS PINS. Both transformations start with EEG = input, then
%   add their own fields -- CoherenceMap.m never touches EEG.CohTopoValues
%   and CoherenceTopography.m never touches EEG.coherence, so chaining one
%   onto the other's result (an entirely normal thing to do: both accept
%   any EPOCHED dataset with a reference channel, and the other's result is
%   exactly that) used to leave BOTH sets of fields on the final struct.
%   AlakazamPlotter.plotEpoched picks a view by "eeg.id matches, OR this
%   field is present" (the field fallback exists so a grand average, whose
%   id gets renamed to the grand average's own name, still routes
%   correctly) -- and the CoherenceMap check is evaluated first, so a
%   CoherenceTopography node that still carried a stale, non-empty
%   EEG.coherence from its CoherenceMap ancestor rendered as a CoherenceView
%   heatmap instead of a CoherenceTopographyView head-map. Reported
%   directly: "coherence map and coherence topography look to give the
%   same plots."
%
%   Run with: runtests('tests/CoherenceChainingTest.m').
%
%   See also COHERENCEMAPTEST, COHERENCETOPOGRAPHYTEST, ALAKAZAMPLOTTER.

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            for p = {fullfile(root, 'src', 'Transformations', 'CoherenceMap'), ...
                     fullfile(root, 'src', 'Transformations', 'CoherenceTopography'), ...
                     fullfile(root, 'src', 'Transformations'), ...
                     fullfile(root, 'tests', 'fixtures')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
        end
    end

    methods (Test)
        function topographyClearsAnInheritedCoherenceMap(testCase)
        %TOPOGRAPHYCLEARSANINHERITEDCOHERENCEMAP  CoherenceTopography run on
        %   a CoherenceMap result must drop the inherited .coherence (and
        %   its cohFreqs/cohTimes/cohRef/cohMethod siblings), leaving only
        %   its own CohTopoValues -- so AlakazamPlotter routes this node to
        %   CoherenceTopographyView, not CoherenceView.
            EEG = coherenceFixture();
            mapResult = CoherenceMap(EEG, mapOpts());
            testCase.assertTrue(isfield(mapResult, 'coherence'), ...
                'test setup: CoherenceMap should have produced .coherence.');

            topoResult = CoherenceTopography(mapResult, topoOpts());

            testCase.verifyFalse(isfield(topoResult, 'coherence'));
            testCase.verifyFalse(isfield(topoResult, 'cohFreqs'));
            testCase.verifyFalse(isfield(topoResult, 'cohTimes'));
            testCase.verifyFalse(isfield(topoResult, 'cohRef'));
            testCase.verifyFalse(isfield(topoResult, 'cohMethod'));
            for stale = {'cohRefPower', 'cohRefSpectrum', 'cohRefSpecFreqs', 'cohRefPeakHz'}
                testCase.verifyFalse(isfield(topoResult, stale{1}), ...
                    ['A stale ' stale{1} ' was carried into the chained result.']);
            end
            testCase.verifyTrue(isfield(topoResult, 'CohTopoValues'));
        end

        function coherenceMapClearsAnInheritedTopography(testCase)
        %COHERENCEMAPCLEARSANINHERITEDTOPOGRAPHY  The symmetric case:
        %   CoherenceMap run on a CoherenceTopography result must drop the
        %   inherited CohTopo* fields, leaving only its own .coherence.
            EEG = coherenceFixture();
            topoResult = CoherenceTopography(EEG, topoOpts());
            testCase.assertTrue(isfield(topoResult, 'CohTopoValues'), ...
                'test setup: CoherenceTopography should have produced .CohTopoValues.');

            mapResult = CoherenceMap(topoResult, mapOpts());

            testCase.verifyFalse(isfield(mapResult, 'CohTopoValues'));
            testCase.verifyFalse(isfield(mapResult, 'CohTopoChanlocs'));
            testCase.verifyFalse(isfield(mapResult, 'CohTopoDrawn'));
            testCase.verifyFalse(isfield(mapResult, 'CohTopoFreqs'));
            testCase.verifyFalse(isfield(mapResult, 'CohTopoRef'));
            testCase.verifyFalse(isfield(mapResult, 'CohTopoLimit'));
            testCase.verifyFalse(isfield(mapResult, 'CohTopoRefAmp'));
            testCase.verifyFalse(isfield(mapResult, 'CohTopoAmpFreqs'));
            testCase.verifyFalse(isfield(mapResult, 'CohTopoBins'));
            testCase.verifyFalse(isfield(mapResult, 'CohTopoBinLabels'));
            testCase.verifyTrue(isfield(mapResult, 'coherence'));
        end
    end
end

function EEG = coherenceFixture()
%COHERENCEFIXTURE  3-channel (real 10-5 labels, for CoherenceTopography's
%   own scalp-position lookup), 250 Hz, EPOCHED, one bin.
    EEG = makeTestEEG('nbchan', 3, 'trials', 4, 'labels', {'Fz', 'Cz', 'Pz'}, ...
        'DataFormat', 'EPOCHED');
    EEG.bindesc = struct('index', 1, 'label', 'Bin1', 'trials', 1:EEG.trials, 'combo', []);
end

function opts = mapOpts()
    opts = struct('RefChannel', 'Fz', 'Method', 'Wavelet', 'MinFreq', 5, 'MaxFreq', 20, ...
        'NumFreqs', 5, 'MinCycles', 3, 'MaxCycles', 5, 'WindowMs', 200, 'PadRatio', 2);
end

function opts = topoOpts()
    opts = struct('RefChannel', 'Fz', 'MinFreq', 5, 'MaxFreq', 20, 'Frequency', 0, ...
        'TimeStart', 0, 'TimeStop', 0);
end
