classdef CoherenceMapOptionsTest < matlab.unittest.TestCase
%COHERENCEMAPOPTIONSTEST  What CoherenceMap.m stores and accepts: the
%   reference channel's own spectrum, the synthetic sine reference, the
%   filter-Hilbert method, and the replay of options saved before any of
%   those existed.
%
%   Calls CoherenceMap with an options struct, which is the no-dialog replay
%   path the app itself uses to recalculate a node.
%
%   Run with: runtests('tests/CoherenceMapOptionsTest.m').
%
%   See also COHERENCEMAP, COHERENCEMAPTEST, REFERENCESPECTRUMTEST.

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            for p = {fullfile(root, 'src', 'Transformations', 'CoherenceMap'), ...
                     fullfile(root, 'src', 'Transformations'), ...
                     fullfile(root, 'tests', 'fixtures')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
        end
    end

    methods (Test)
        function theReferencesOwnSpectrumAndPeakAreStored(testCase)
        %   makeTestEEG channel 1 is sin(2 pi 10 t + trial) + 5, so the
        %   reference (Fz) is a 10 Hz tone; 200 samples at 250 Hz put 10 Hz
        %   exactly on an FFT bin.
            out = CoherenceMap(baseEEG(), baseOpts());

            testCase.verifyTrue(isfield(out, 'cohRefPower'));
            testCase.verifyTrue(isfield(out, 'cohRefSpectrum'));
            testCase.verifyTrue(isfield(out, 'cohRefSpecFreqs'));
            testCase.verifyTrue(isfield(out, 'cohRefPeakHz'));
            testCase.verifyEqual(size(out.cohRefSpectrum, 1), numel(out.cohRefSpecFreqs));
            testCase.verifyEqual(size(out.cohRefSpectrum, 2), 1);
            testCase.verifyEqual(out.cohRefPeakHz(1), 10, 'AbsTol', 1e-9);
        end

        function theSpectrumCoversMoreThanTheAnalysedBand(testCase)
        %   The whole point: the coherence band here is 5 to 20 Hz, and the
        %   stored spectrum must reach well past it.
            out = CoherenceMap(baseEEG(), baseOpts());
            testCase.verifyGreaterThan(max(out.cohRefSpecFreqs), 2 * max(out.cohFreqs));
        end

        function optionsSavedBeforeTheNewOnesExistedStillReplay(testCase)
        %   baseOpts has no Taper, SineHz, BandwidthHz or StepMs, exactly
        %   like a node recalculated from options stored a version ago.
            out = CoherenceMap(baseEEG(), baseOpts());
            testCase.verifyEqual(out.cohMethod, 'Wavelet');
            testCase.verifyEqual(out.cohRef, 'Fz');
        end

        function aSyntheticSineActsAsTheReference(testCase)
        %   Channel 1 is a 20 Hz tone locked to the epoch's time zero plus a
        %   little independent noise; channel 2 is noise with no tone. A
        %   sine of 20 Hz that starts at time zero on every trial is then
        %   coherent with channel 1 and not with channel 2.
            EEG = sineEEG();
            opts = baseOpts();
            opts.RefChannel = '(synthetic sine)';
            opts.SineHz = 20;
            opts.MinFreq = 10;
            opts.MaxFreq = 20;      % logspace includes 20 exactly
            opts.NumFreqs = 3;

            out = CoherenceMap(EEG, opts);

            testCase.verifyEqual(size(out.coherence, 1), 2, ...
                'The appended sine row must be dropped again, leaving the recorded channels.');
            testCase.verifyEqual(out.cohRef, 'sine 20 Hz');
            atTag = numel(out.cohFreqs);
            testCase.verifyEqual(out.cohFreqs(atTag), 20, 'AbsTol', 1e-9);
            tone  = median(squeeze(out.coherence(1, atTag, :, 1)), 'omitnan');
            noise = median(squeeze(out.coherence(2, atTag, :, 1)), 'omitnan');
            testCase.verifyGreaterThan(tone, 0.9);
            testCase.verifyLessThan(noise, 0.6);
            testCase.verifyEqual(out.cohRefPeakHz(1), 20, 'AbsTol', 1e-9);
        end

        function aSyntheticSineAtOrAboveNyquistIsRefused(testCase)
            opts = baseOpts();
            opts.RefChannel = '(synthetic sine)';
            opts.SineHz = 125;      % Nyquist for 250 Hz
            testCase.verifyError(@() CoherenceMap(baseEEG(), opts), 'Alakazam:CoherenceMap');
        end

        function aSyntheticSineNeedsAFrequency(testCase)
            opts = baseOpts();
            opts.RefChannel = '(synthetic sine)';
            testCase.verifyError(@() CoherenceMap(baseEEG(), opts), 'Alakazam:CoherenceMap');
        end

        function filterHilbertRunsThroughTheTransformation(testCase)
            opts = baseOpts();
            opts.Method = 'FilterHilbert';
            opts.BandwidthHz = 4;
            opts.StepMs = 20;
            out = CoherenceMap(baseEEG(), opts);

            testCase.verifyEqual(out.cohMethod, 'FilterHilbert');
            testCase.verifyEqual(diff(out.cohTimes), 20 * ones(1, numel(out.cohTimes) - 1), 'AbsTol', 1e-9);
            testCase.verifyEqual(size(out.coherence, 2), numel(out.cohFreqs));
        end

        function theBoxcarTaperIsPassedThroughToTheStft(testCase)
            opts = baseOpts();
            opts.Method = 'STFT';
            opts.WindowMs = 200;
            opts.PadRatio = 2;
            opts.MaxFreq = 60;
            hann = CoherenceMap(baseEEG(), opts);
            opts.Taper = 'Boxcar';
            boxcar = CoherenceMap(baseEEG(), opts);
            testCase.verifyNotEqual(hann.cohRefPower, boxcar.cohRefPower);
        end
    end
end

function EEG = baseEEG()
%BASEEEG  3 channels (Fz is the 10 Hz reference), 250 Hz, 4 trials, one bin.
    EEG = makeTestEEG('nbchan', 3, 'trials', 4, 'labels', {'Fz', 'Cz', 'Pz'}, ...
        'DataFormat', 'EPOCHED');
    EEG.bindesc = struct('index', 1, 'label', 'Bin1', 'trials', 1:EEG.trials, 'combo', []);
end

function opts = baseOpts()
    opts = struct('RefChannel', 'Fz', 'Method', 'Wavelet', 'MinFreq', 5, 'MaxFreq', 20, ...
        'NumFreqs', 5, 'MinCycles', 3, 'MaxCycles', 5, 'WindowMs', 200, 'PadRatio', 2);
end

function EEG = sineEEG()
%SINEEEG  Channel 1: a 20 Hz tone locked to time zero on every trial plus
%   small independent noise. Channel 2: independent noise only.
    rng(3);
    srate = 250;
    nT = 250;
    nTrials = 30;
    times = (0:nT - 1) / srate * 1000;
    t = times / 1000;
    data = zeros(2, nT, nTrials);
    for tr = 1:nTrials
        data(1, :, tr) = sin(2 * pi * 20 * t) + 0.05 * randn(1, nT);
        data(2, :, tr) = randn(1, nT);
    end
    EEG = struct('DataFormat', 'EPOCHED', 'srate', srate, 'nbchan', 2, ...
        'times', times, 'data', data, 'trials', nTrials, 'pnts', nT, ...
        'chanlocs', struct('labels', {'Tone', 'Noise'}), ...
        'bindesc', struct('index', 1, 'label', 'Bin1', 'trials', 1:nTrials, 'combo', []));
end
