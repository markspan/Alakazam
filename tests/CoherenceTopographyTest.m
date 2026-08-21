classdef CoherenceTopographyTest < matlab.unittest.TestCase
%COHERENCETOPOGRAPHYTEST  Unit tests for
%   src/Transformations/+TransTools/ComputeCoherenceTopography.m.
%
%   Uses the same "coherence against a positive real scalar multiple of
%   the reference is exactly 1" identity as CoherenceMapTest/
%   SpectralMeasureTest, plus a check on the auto-frequency-detection
%   logic (does it actually find the reference's own known peak?) and the
%   fixed-frequency override.
%
%   Run with: runtests('tests/CoherenceTopographyTest.m').

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'Transformations')));
        end
    end

    methods (Test)
        function autoDetectsTheReferencesPeakFrequency(testCase)
            EEG = coherenceFixture();
            opts = defaultOpts();
            [~, detFreq, ~, ~] = TransTools.ComputeCoherenceTopography(EEG, opts);
            testCase.verifyEqual(detFreq(1), 20, 'AbsTol', opts.FreqStep);
        end

        function coherenceIsOneForAScalarMultipleAtTheDetectedFrequency(testCase)
            EEG = coherenceFixture();
            opts = defaultOpts();
            [coh, ~, ~, ~] = TransTools.ComputeCoherenceTopography(EEG, opts);
            testCase.verifyEqual(coh(2, 1), 1, 'AbsTol', 1e-6);
        end

        function fixedFrequencyOverridesAutoDetection(testCase)
            EEG = coherenceFixture();
            opts = defaultOpts();
            opts.Frequency = 15; % deliberately not the true 20 Hz peak
            [~, detFreq, refAmp, ~] = TransTools.ComputeCoherenceTopography(EEG, opts);
            testCase.verifyEqual(detFreq(1), 15);
            testCase.verifyTrue(all(isnan(refAmp(:, 1)))); % search grid not used when Frequency is fixed
        end

        function referenceChannelRowIsNaN(testCase)
            EEG = coherenceFixture();
            opts = defaultOpts();
            [coh, ~, ~, ~] = TransTools.ComputeCoherenceTopography(EEG, opts);
            testCase.verifyTrue(all(isnan(coh(opts.RefIndex, :))));
        end

        function binWithNoTrialsIsNaN(testCase)
            EEG = coherenceFixture();
            EEG.bindesc(2) = struct('index', 2, 'label', 'Empty', 'trials', [], 'combo', []);
            opts = defaultOpts();
            [coh, detFreq, ~, ~] = TransTools.ComputeCoherenceTopography(EEG, opts);
            testCase.verifyTrue(all(isnan(coh(:, 2))));
            testCase.verifyTrue(isnan(detFreq(2)));
        end

        function coherenceIsLowWithIndependentTrialPhase(testCase)
        %COHERENCEISLOWWITHINDEPENDENTTRIALPHASE  Coherence measures
        %   trial-to-trial CONSISTENCY of phase, not shared frequency --
        %   with noiseless, exactly-repeated trials (as coherenceFixture()
        %   above uses), coherence between ANY two nonzero channels is
        %   exactly 1 regardless of content (confirmed the hard way: an
        %   earlier version of this test used a different-frequency-but-
        %   identical-every-trial channel 3 and got exactly 1, not "low").
        %   A genuinely low-coherence case needs real trial-to-trial phase
        %   variability: channel 2 has an INDEPENDENT random phase each
        %   trial relative to the reference. A fixed seed keeps the draw
        %   reproducible; enough trials that the expected coherence
        %   (~1/nTrials) sits comfortably under the 0.5 threshold.
            rng(13);
            nTrials = 40; srate = 250; nT = 250;
            times = (0:nT - 1) / srate * 1000;
            t = times / 1000;
            refPhase = 2 * pi * rand(1, nTrials);
            data = zeros(2, nT, nTrials);
            for tr = 1:nTrials
                data(1, :, tr) = 3 * sin(2 * pi * 20 * t);                % reference: phase-locked
                data(2, :, tr) = 3 * sin(2 * pi * 20 * t + refPhase(tr)); % independent phase per trial
            end
            EEG = struct('DataFormat', 'EPOCHED', 'times', times, 'srate', srate, 'data', data, ...
                'bindesc', struct('index', 1, 'label', 'Bin1', 'trials', 1:nTrials, 'combo', []));
            opts = defaultOpts();
            opts.RefIndex = 1;

            [coh, ~, ~, ~] = TransTools.ComputeCoherenceTopography(EEG, opts);

            testCase.verifyLessThan(coh(2, 1), 0.5);
        end
    end
end

function EEG = coherenceFixture()
%COHERENCEFIXTURE  3-channel, 250 Hz, 2-trial EPOCHED EEG: Ch1 (the
%   reference) is a clean 20 Hz tone; Ch2 is exactly 2x Ch1; Ch3 is an
%   unrelated 40 Hz tone (outside the 10-30 Hz search band used below).
    srate = 250; nT = 250;
    times = (0:nT - 1) / srate * 1000;
    t = times / 1000;
    nTrials = 2;
    ch1 = 3 * sin(2 * pi * 20 * t);
    data = zeros(3, nT, nTrials);
    for tr = 1:nTrials
        data(1, :, tr) = ch1;
        data(2, :, tr) = 2 * ch1;
        data(3, :, tr) = 3 * sin(2 * pi * 40 * t);
    end
    EEG = struct();
    EEG.DataFormat = 'EPOCHED';
    EEG.times  = times;
    EEG.srate  = srate;
    EEG.data   = data;
    EEG.bindesc = struct('index', 1, 'label', 'Bin1', 'trials', 1:nTrials, 'combo', []);
end

function opts = defaultOpts()
    opts = struct('RefIndex', 1, 'MinFreq', 10, 'MaxFreq', 30, 'Frequency', 0, ...
        'TimeStart', 0, 'TimeStop', 0, 'FreqStep', 0.1);
end
