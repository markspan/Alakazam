classdef CoherenceTopographyTest < matlab.unittest.TestCase
%COHERENCETOPOGRAPHYTEST Unit tests for
%   src/Transformations/CoherenceTopography/ComputeCoherenceTopography.m.
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
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'Transformations', 'CoherenceTopography')));   % ComputeCoherenceTopography lives there
        end
    end

    methods (Test)
        function autoDetectsTheReferencesPeakFrequency(testCase)
            EEG = coherenceFixture();
            opts = defaultOpts();
            [~, detFreq, ~, ~] = ComputeCoherenceTopography(EEG, opts);
            testCase.verifyEqual(detFreq(1), 20, 'AbsTol', opts.FreqStep);
        end

        function coherenceIsOneForAScalarMultipleAtTheDetectedFrequency(testCase)
            EEG = coherenceFixture();
            opts = defaultOpts();
            [coh, ~, ~, ~] = ComputeCoherenceTopography(EEG, opts);
            testCase.verifyEqual(coh(2, 1), 1, 'AbsTol', 1e-6);
        end

        function fixedFrequencyOverridesAutoDetection(testCase)
            EEG = coherenceFixture();
            opts = defaultOpts();
            opts.Frequency = 15; % deliberately not the true 20 Hz peak
            [~, detFreq, refAmp, ~] = ComputeCoherenceTopography(EEG, opts);
            testCase.verifyEqual(detFreq(1), 15);
            testCase.verifyTrue(all(isnan(refAmp(:, 1)))); % search grid not used when Frequency is fixed
        end

        function referenceChannelRowIsNaN(testCase)
            EEG = coherenceFixture();
            opts = defaultOpts();
            [coh, ~, ~, ~] = ComputeCoherenceTopography(EEG, opts);
            testCase.verifyTrue(all(isnan(coh(opts.RefIndex, :))));
        end

        function binWithNoTrialsIsNaN(testCase)
            EEG = coherenceFixture();
            EEG.bindesc(2) = struct('index', 2, 'label', 'Empty', 'trials', [], 'combo', []);
            opts = defaultOpts();
            [coh, detFreq, ~, ~] = ComputeCoherenceTopography(EEG, opts);
            testCase.verifyTrue(all(isnan(coh(:, 2))));
            testCase.verifyTrue(isnan(detFreq(2)));
        end

        function theFrequencySearchEqualsTheMeanOfEveryTrialsOwnTransform(testCase)
        %THEFREQUENCYSEARCHEQUALSTHEMEANOFEVERYTRIALSOWNTRANSFORM  The evoked
        %   amplitude at each search frequency is |mean over trials of the tapered
        %   DFT|. It is computed from the trial mean (one column per frequency),
        %   which is the same number by linearity and about a hundred times less
        %   arithmetic; here it is compared with the per-trial form written out
        %   directly, on noisy data with a tone at a fixed phase.
            rng(3);
            srate = 250; nT = 250; nTrials = 6;
            times = (0:nT - 1) / srate * 1000;
            t = times / 1000;
            data = randn(3, nT, nTrials);
            for tr = 1:nTrials
                data(1, :, tr) = data(1, :, tr) + 3 * sin(2 * pi * 20 * t);
            end
            EEG = struct('DataFormat', 'EPOCHED', 'times', times, 'srate', srate, 'data', data, ...
                'bindesc', struct('index', 1, 'label', 'Bin1', 'trials', 1:nTrials, 'combo', []));
            opts = defaultOpts();

            [~, ~, refAmp, ampFreqs] = ComputeCoherenceTopography(EEG, opts);

            Vref = reshape(data(1, :, :), nT, []);
            taper = hann(nT);
            expected = zeros(numel(ampFreqs), 1);
            for k = 1:numel(ampFreqs)
                expected(k) = abs(mean(TransTools.Tdft(Vref, ampFreqs(k), t, taper)));
            end
            testCase.verifyEqual(refAmp(:, 1), expected, 'AbsTol', 1e-9 * max(expected));
        end

        function theFrameMethodIsTheFrameCoherenceOfEachChannel(testCase)
            EEG = noisyFixture();
            opts = defaultOpts();
            opts.Method = 'frames';
            opts.Frequency = 20;
            opts.WindowMs = 200;
            opts.TimeStart = 100;
            opts.TimeStop = 900;

            [coh, detFreq] = ComputeCoherenceTopography(EEG, opts);

            R = squeeze(EEG.data(1, :, :));
            want = TransTools.FrameCoherence(squeeze(EEG.data(2, :, :)), R, EEG.srate, 20, ...
                struct('WinSize', 50, 'Times', EEG.times, 'TimeStart', 100, 'TimeStop', 900));
            testCase.verifyEqual(coh(2, 1), want, 'AbsTol', 1e-12);
            testCase.verifyTrue(isnan(coh(1, 1)), 'The reference row is left NaN.');
            testCase.verifyEqual(detFreq, 20);
            testCase.verifyGreaterThan(want, 0.2, 'The comparison must not be between near-zero numbers.');
        end

        function optionsWithNoMethodOrTagSourceKeepTheirOldMeaning(testCase)
        %OPTIONSWITHNOMETHODORTAGSOURCEKEEPTHEIROLDMEANING  A stored node has neither
        %   field. It must give the single-window coherence and the band search it
        %   always gave, so recalculating it reproduces its numbers.
            EEG = noisyFixture();
            legacy = defaultOpts();
            explicit = legacy;
            explicit.Method = 'window';
            explicit.TagSource = 'band';

            [c1, f1] = ComputeCoherenceTopography(EEG, legacy);
            [c2, f2] = ComputeCoherenceTopography(EEG, explicit);

            testCase.verifyEqual(c1, c2);
            testCase.verifyEqual(f1, f2);
        end

        function theFrameEstimatorReadsLowerThanTheSingleWindowOnTheSameData(testCase)
            EEG = noisyFixture();
            opts = defaultOpts();
            opts.Frequency = 20;
            window = ComputeCoherenceTopography(EEG, opts);
            opts.Method = 'frames';
            opts.WindowMs = 200;

            frames = ComputeCoherenceTopography(EEG, opts);

            testCase.verifyLessThan(frames(2, 1), window(2, 1));
        end

        function aTagOutsideTheSearchBandIsFoundFromTheReferenceAndMissedByTheBand(testCase)
        %ATAGOUTSIDETHESEARCHBANDISFOUNDFROMTHEREFERENCEANDMISSEDBYTHEBAND  The
        %   reference flickers at 20 Hz and the band searched is 40 to 60 Hz, as a
        %   30 Hz SSVEP condition was against a 52 to 68 Hz band: the band search
        %   reports the strongest thing inside the band, the reference source
        %   reports the tag.
            EEG = coherenceFixture();
            opts = defaultOpts();
            opts.MinFreq = 40;
            opts.MaxFreq = 60;

            [~, byBand] = ComputeCoherenceTopography(EEG, opts);
            opts.TagSource = 'reference';
            [~, byReference] = ComputeCoherenceTopography(EEG, opts);

            testCase.verifyGreaterThanOrEqual(byBand(1), 40, 'The band search stays inside its band.');
            testCase.verifyEqual(byReference(1), 20, 'AbsTol', 1.0);
        end

        function aFixedFrequencyBeatsTheTagSource(testCase)
            EEG = coherenceFixture();
            opts = defaultOpts();
            opts.TagSource = 'reference';
            opts.Frequency = 33;

            [~, detFreq] = ComputeCoherenceTopography(EEG, opts);

            testCase.verifyEqual(detFreq(1), 33);
        end

        function anUnknownMethodOrTagSourceIsRefused(testCase)
            EEG = coherenceFixture();
            opts = defaultOpts();
            opts.Method = 'wavelet';
            testCase.verifyError(@() ComputeCoherenceTopography(EEG, opts), ...
                'Alakazam:ComputeCoherenceTopography');
            opts = defaultOpts();
            opts.TagSource = 'guess';
            testCase.verifyError(@() ComputeCoherenceTopography(EEG, opts), ...
                'Alakazam:ComputeCoherenceTopography');
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

            [coh, ~, ~, ~] = ComputeCoherenceTopography(EEG, opts);

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

function EEG = noisyFixture()
%NOISYFIXTURE  Reference (Ch1) and a channel (Ch2) sharing a 20 Hz tone with a random
%   phase on every one of 10 trials, each with its own noise: real, not perfect,
%   coherence over a 1 s epoch at 250 Hz, with a time axis that starts before 0.
    rng(17);
    srate = 250; nT = 250; nTrials = 10;
    times = (0:nT - 1) / srate * 1000 - 100;
    t = (0:nT - 1) / srate;
    data = zeros(2, nT, nTrials);
    for tr = 1:nTrials
        tone = cos(2 * pi * 20 * t + 2 * pi * rand());
        data(1, :, tr) = tone + 0.6 * randn(1, nT);
        data(2, :, tr) = tone + 0.6 * randn(1, nT);
    end
    EEG = struct('DataFormat', 'EPOCHED', 'times', times, 'srate', srate, 'data', data, ...
        'bindesc', struct('index', 1, 'label', 'Bin1', 'trials', 1:nTrials, 'combo', []));
end

