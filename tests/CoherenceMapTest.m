classdef CoherenceMapTest < matlab.unittest.TestCase
%COHERENCEMAPTEST Unit tests for
%   src/Transformations/CoherenceMap/ComputeCoherenceMap.m (both its Wavelet
%   and STFT methods).
%
%   Leans on the same exact algebraic identity as SpectralMeasureTest's
%   own coherence tests: magnitude-squared coherence between a channel
%   and a reference that is a POSITIVE REAL SCALAR multiple of it is
%   EXACTLY 1 at every time/frequency point, since the formula's cross
%   term and denominator reduce algebraically to the same value -- this
%   holds regardless of the wavelet/STFT machinery in between, so it does
%   not require re-deriving that machinery's own numerics.
%
%   The wavelet leaves the samples within half a wavelet of either end of
%   the epoch blank (see ComputeCoherenceMap), so the wavelet cases compare
%   the interior, which INFO's half-wavelets mark, and the edge cases pin
%   the blank zone against arithmetic done here.
%
%   Run with: runtests('tests/CoherenceMapTest.m').

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'Transformations')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'Transformations', 'CoherenceMap')));   % ComputeCoherenceMap lives there
        end
    end

    methods (Test)
        function coherenceIsOneForAScalarMultipleWavelet(testCase)
            EEG = coherenceFixture();
            opts = waveletOpts();
            [coh, ~, ~, ~, info] = ComputeCoherenceMap(EEG, opts);
            inside = clearOfEdges(info, EEG);
            c = squeeze(coh(2, :, :, 1));
            testCase.verifyEqual(c(inside), ones(nnz(inside), 1), 'AbsTol', 1e-6);
        end

        % ---- the wavelet's edges ------------------------------------------
        function theWaveletEdgesAreBlank(testCase)
        %THEWAVELETEDGESAREBLANK  At 10 Hz with 3 cycles the wavelet's sigma
        %   is 3 / (2 pi 10) s and it runs to three sigma, ceil(35.8) = 36
        %   samples at 250 Hz: the first and last 36 samples are blank and
        %   every sample between them is computed.
            EEG = coherenceFixture();
            opts = waveletOpts();
            [coh, freqs, ~, ~, info] = ComputeCoherenceMap(EEG, opts);
            testCase.assertEqual(freqs(1), 10, 'AbsTol', 1e-9);

            testCase.verifyEqual(info.halfWaveletMs(1), 36 / 250 * 1000, 'AbsTol', 1e-9);
            row = squeeze(coh(2, 1, :, 1))';
            nT = numel(EEG.times);
            testCase.verifyTrue(all(isnan(row([1:36, nT - 35:nT]))), 'The edges are blank.');
            testCase.verifyTrue(all(isfinite(row(37:nT - 36))), 'Everything between them is computed.');
        end

        function theReferencePowerIsBlankAtTheEdgesToo(testCase)
            EEG = coherenceFixture();
            [~, ~, ~, refPower, info] = ComputeCoherenceMap(EEG, waveletOpts());
            inside = clearOfEdges(info, EEG);
            power = refPower(:, :, 1);
            testCase.verifyTrue(all(isnan(power(~inside))));
            testCase.verifyTrue(all(isfinite(power(inside))));
        end

        function aWaveletLongerThanTheEpochLeavesItsFrequencyBlank(testCase)
        %AWAVELETLONGERTHANTHEEPOCHLEAVESITSFREQUENCYBLANK  A 200 ms epoch:
        %   at 2 Hz with 3 cycles half the wavelet is 179 samples, longer
        %   than the epoch, so the row is blank and recorded as blank; at
        %   30 Hz with 5 cycles it is 20 samples, and the row has values.
            EEG = coherenceFixture();
            EEG.data = EEG.data(:, 1:50, :);
            EEG.times = EEG.times(1:50);
            opts = waveletOpts();
            opts.MinFreq = 2;

            [coh, ~, ~, ~, info] = ComputeCoherenceMap(EEG, opts);

            testCase.verifyTrue(info.blankFrequencies(1));
            testCase.verifyFalse(info.blankFrequencies(end));
            testCase.verifyTrue(all(isnan(coh(2, 1, :, 1)), 'all'));
            testCase.verifyTrue(any(isfinite(coh(2, end, :, 1)), 'all'));
        end

        function theStftAndFilterHilbertHaveNoEdgeZone(testCase)
            EEG = coherenceFixture();
            [coh, ~, ~, ~, info] = ComputeCoherenceMap(EEG, stftOpts());
            testCase.verifyEmpty(info.halfWaveletMs);
            testCase.verifyFalse(any(info.blankFrequencies));
            testCase.verifyFalse(any(isnan(coh(2, :, :, 1)), 'all'));
            [~, ~, ~, ~, info] = ComputeCoherenceMap(EEG, filterHilbertOpts());
            testCase.verifyEmpty(info.halfWaveletMs);
        end

        function coherenceIsOneForAScalarMultipleStft(testCase)
            EEG = coherenceFixture();
            opts = stftOpts();
            [coh, freqs, cohTimes] = ComputeCoherenceMap(EEG, opts);
            testCase.verifyEqual(coh(2, :, :, 1), ones(1, numel(freqs), numel(cohTimes)), 'AbsTol', 1e-6);
        end

        function aRejectedTrialIsLeftOut(testCase)
        %AREJECTEDTRIALISLEFTOUT  Rejection writes NaN and leaves the trial
        %   in its bin; one such trial used to make every channel's
        %   coherence NaN. Left out, the two intact trials still give a
        %   scalar multiple of the reference a coherence of 1.
            EEG = coherenceFixture();
            EEG.data(:, :, 3) = NaN;
            EEG.bindesc.trials = 1:3;
            opts = waveletOpts();

            [coh, ~, ~, ~, info] = ComputeCoherenceMap(EEG, opts);

            inside = clearOfEdges(info, EEG);
            c2 = squeeze(coh(2, :, :, 1));
            c3 = squeeze(coh(3, :, :, 1));
            testCase.verifyEqual(c2(inside), ones(nnz(inside), 1), 'AbsTol', 1e-6);
            testCase.verifyFalse(any(isnan(c3(inside))));
        end

        function aChannelRejectedInOneTrialKeepsItsOtherTrials(testCase)
        %ACHANNELREJECTEDINONETRIALKEEPSITSOTHERTRIALS  "This channel only"
        %   rejection blanks one channel of one trial. That channel is
        %   estimated from its other trials, with the reference power in its
        %   denominator taken over the same trials, and the other channels
        %   keep every trial.
            EEG = coherenceFixture();
            EEG.data(:, :, 3) = EEG.data(:, :, 1);
            EEG.data(2, :, 3) = NaN;
            EEG.bindesc.trials = 1:3;
            opts = waveletOpts();

            [coh, ~, ~, ~, info] = ComputeCoherenceMap(EEG, opts);

            inside = clearOfEdges(info, EEG);
            c2 = squeeze(coh(2, :, :, 1));
            c3 = squeeze(coh(3, :, :, 1));
            testCase.verifyEqual(c2(inside), ones(nnz(inside), 1), 'AbsTol', 1e-6, ...
                'With the reference power over the same two trials, this is still exactly 1.');
            testCase.verifyFalse(any(isnan(c3(inside))));
        end

        function referenceChannelRowIsNaN(testCase)
            EEG = coherenceFixture();
            opts = waveletOpts();
            [coh, ~, ~] = ComputeCoherenceMap(EEG, opts);
            testCase.verifyTrue(all(isnan(coh(opts.RefIndex, :, :, :)), 'all'));
        end

        function refPowerPeaksAtTheReferencesOwnFrequency(testCase)
        %REFPOWERPEAKSATTHEREFERENCESOWNFREQUENCY  refPower has to answer
        %   "which frequency was the reference itself doing the most at"
        %   using nothing but the reference's own signal -- exactly the
        %   read-out self-coherence (always NaN, see
        %   referenceChannelRowIsNaN above) cannot supply. coherenceFixture
        %   makes channel 1 (the reference) a clean 20 Hz tone. MaxFreq is
        %   set to exactly 20: logspace always includes its own endpoints
        %   exactly, so this is one of the analysed frequencies on the
        %   nose rather than whichever grid point happens to sit closest,
        %   and the test cannot pass merely by returning a constant or the
        %   grid's own first bin.
            EEG = coherenceFixture();
            opts = waveletOpts();
            opts.MaxFreq = 20;
            [~, freqs, ~, refPower] = ComputeCoherenceMap(EEG, opts);

            perFreq = mean(refPower(:, :, 1), 2, 'omitnan');   % the edges are blank
            [~, fIdx] = max(perFreq);
            testCase.verifyEqual(freqs(fIdx), 20, 'AbsTol', 1e-6);
        end

        function refPowerIsNaNForACombinationBinOrEmptyBin(testCase)
        %REFPOWERISNANFORACOMBINATIONBINOREMPTYBIN  Mirrors
        %   combinationBinIsNaN/binWithNoTrialsIsNaN for coh itself: a bin
        %   nothing was accumulated for must not silently carry over
        %   whatever refPower happened to hold from a previous bin, or
        %   zero-initialised values that would misreport as "the reference
        %   was flat at every frequency" rather than "not computed".
            EEG = coherenceFixture();
            EEG.bindesc(2) = struct('index', 2, 'label', 'Combo', 'trials', [], ...
                'combo', struct('bin', 1, 'coeff', 1));
            opts = waveletOpts();
            [~, ~, ~, refPower] = ComputeCoherenceMap(EEG, opts);
            testCase.verifyTrue(all(isnan(refPower(:, :, 2)), 'all'));
        end

        function aBinWithASingleTrialHasNoCoherenceButKeepsItsReferencePower(testCase)
        %ABINWITHASINGLETRIALHASNOCOHERENCEBUTKEEPSITSREFERENCEPOWER  With
        %   one trial the numerator and the denominator are the same number,
        %   so coherence is exactly 1 at every point and channel: a value
        %   that looks like a perfect response and is nothing at all. It must
        %   be missing, not 1. The reference's own power is still meaningful
        %   (it is one trial's spectrum) and is what names the tag.
            EEG = coherenceFixture();
            EEG.bindesc(1).trials = 1;
            [coh, ~, ~, refPower, info] = ComputeCoherenceMap(EEG, waveletOpts());
            testCase.verifyTrue(all(isnan(coh(:, :, :, 1)), 'all'));
            power = refPower(:, :, 1);
            testCase.verifyTrue(all(isfinite(power(clearOfEdges(info, EEG)))));
        end

        function boxcarTaperStillGivesUnitCoherenceForAScalarMultiple(testCase)
            EEG = coherenceFixture();
            opts = stftOpts();
            opts.Taper = 'Boxcar';
            [coh, freqs, cohTimes] = ComputeCoherenceMap(EEG, opts);
            testCase.verifyEqual(coh(2, :, :, 1), ones(1, numel(freqs), numel(cohTimes)), 'AbsTol', 1e-6);
        end

        function theTaperActuallyChangesTheEstimate(testCase)
        %THETAPERACTUALLYCHANGESTHEESTIMATE  A taper option that is silently
        %   ignored would pass every other test. A boxcar leaks far more of
        %   the 20 Hz reference tone into frequencies well away from it than
        %   a Hann does (side lobes fall off as 1/f against 1/f^3), so the
        %   reference power at 36 Hz and above must be larger with a boxcar.
            EEG = coherenceFixture();
            hann = stftOpts();
            hann.Taper = 'Hann';
            hann.MaxFreq = 60;
            boxcar = hann;
            boxcar.Taper = 'Boxcar';

            [~, freqs, ~, powerHann] = ComputeCoherenceMap(EEG, hann);
            [~, ~, ~, powerBox] = ComputeCoherenceMap(EEG, boxcar);

            far = freqs >= 36;
            testCase.assertTrue(any(far), 'test setup: the grid should reach 36 Hz.');
            testCase.verifyGreaterThan(mean(powerBox(far, :, 1), 'all'), ...
                10 * mean(powerHann(far, :, 1), 'all'));
        end

        function anUnknownTaperIsRefused(testCase)
            EEG = coherenceFixture();
            opts = stftOpts();
            opts.Taper = 'Blackman';
            testCase.verifyError(@() ComputeCoherenceMap(EEG, opts), ...
                'Alakazam:ComputeCoherenceMap');
        end

        function filterHilbertCoherenceIsOneForAScalarMultiple(testCase)
            EEG = coherenceFixture();
            [coh, freqs, cohTimes] = ComputeCoherenceMap(EEG, filterHilbertOpts());
            testCase.verifyEqual(coh(2, :, :, 1), ones(1, numel(freqs), numel(cohTimes)), 'AbsTol', 1e-6);
        end

        function filterHilbertReferencePowerPeaksAtTheReferencesOwnFrequency(testCase)
        %   linspace includes its endpoints exactly, so MaxFreq = 20 puts
        %   the 20 Hz tone on the analysed grid.
            EEG = coherenceFixture();
            opts = filterHilbertOpts();
            opts.MaxFreq = 20;
            [~, freqs, ~, refPower] = ComputeCoherenceMap(EEG, opts);
            [~, fIdx] = max(mean(refPower(:, :, 1), 2));
            testCase.verifyEqual(freqs(fIdx), 20, 'AbsTol', 1e-9);
        end

        function filterHilbertOutputsOnePointPerStep(testCase)
            EEG = coherenceFixture();
            opts = filterHilbertOpts();
            opts.StepMs = 20;
            [~, ~, cohTimes] = ComputeCoherenceMap(EEG, opts);
            testCase.verifyGreaterThan(numel(cohTimes), 2);
            testCase.verifyEqual(diff(cohTimes), 20 * ones(1, numel(cohTimes) - 1), 'AbsTol', 1e-9);
        end

        function filterHilbertRefusesANonPositiveBandwidthOrStep(testCase)
            EEG = coherenceFixture();
            badBand = filterHilbertOpts();
            badBand.BandwidthHz = 0;
            badStep = filterHilbertOpts();
            badStep.StepMs = -5;
            testCase.verifyError(@() ComputeCoherenceMap(EEG, badBand), ...
                'Alakazam:ComputeCoherenceMap');
            testCase.verifyError(@() ComputeCoherenceMap(EEG, badStep), ...
                'Alakazam:ComputeCoherenceMap');
        end

        function combinationBinIsNaN(testCase)
            EEG = coherenceFixture();
            EEG.bindesc(2) = struct('index', 2, 'label', 'Combo', 'trials', [], ...
                'combo', struct('bin', 1, 'coeff', 1));
            opts = waveletOpts();
            [coh, ~, ~] = ComputeCoherenceMap(EEG, opts);
            testCase.verifyTrue(all(isnan(coh(:, :, :, 2)), 'all'));
        end

        function binWithNoTrialsIsNaN(testCase)
            EEG = coherenceFixture();
            EEG.bindesc(2) = struct('index', 2, 'label', 'Empty', 'trials', [], 'combo', []);
            opts = waveletOpts();
            [coh, ~, ~] = ComputeCoherenceMap(EEG, opts);
            testCase.verifyTrue(all(isnan(coh(:, :, :, 2)), 'all'));
        end

        function coherenceIsLowWithIndependentTrialPhase(testCase)
        %COHERENCEISLOWWITHINDEPENDENTTRIALPHASE  Coherence measures
        %   trial-to-trial CONSISTENCY of the phase relationship between
        %   two channels, not whether they share a frequency -- with
        %   noiseless, exactly-repeated trials (as the 2-trial
        %   coherenceFixture() above uses), coherence between ANY two
        %   nonzero channels is exactly 1 regardless of content, since
        %   there is no trial-to-trial variability for the cross-spectrum
        %   to average away (confirmed the hard way: an earlier version
        %   of this test used a different-frequency-but-still-identical-
        %   every-trial channel 3 and got exactly 1, not "low"). A
        %   genuinely low-coherence case needs real trial-to-trial phase
        %   variability: channel 2 has an INDEPENDENT random phase each
        %   trial relative to the reference. A fixed seed keeps the exact
        %   draw reproducible; enough trials that the expected coherence
        %   (~1/nTrials, a random-walk-of-unit-phasors argument) sits
        %   comfortably under the 0.5 threshold.
            rng(7);
            nTrials = 40; srate = 250; nT = 250;
            times = (0:nT - 1) / srate * 1000;
            t = times / 1000;
            refPhase = 2 * pi * rand(1, nTrials);
            data = zeros(2, nT, nTrials);
            for tr = 1:nTrials
                data(1, :, tr) = 3 * sin(2 * pi * 20 * t);                    % reference: phase-locked
                data(2, :, tr) = 3 * sin(2 * pi * 20 * t + refPhase(tr));     % independent phase per trial
            end
            EEG = struct('DataFormat', 'EPOCHED', 'times', times, 'nbchan', 2, ...
                'srate', srate, 'data', data, ...
                'bindesc', struct('index', 1, 'label', 'Bin1', 'trials', 1:nTrials, 'combo', []));
            opts = waveletOpts();
            opts.RefIndex = 1;

            [coh, ~, ~] = ComputeCoherenceMap(EEG, opts);

            testCase.verifyLessThan(mean(coh(2, :, :, 1), 'all', 'omitnan'), 0.5);
        end
    end
end

function EEG = coherenceFixture()
%COHERENCEFIXTURE  3-channel, 250 Hz, 2-trial EPOCHED EEG: Ch1 (the
%   reference) is a 20 Hz tone; Ch2 is exactly 2x Ch1 (same phase and
%   shape, a positive real scalar multiple); Ch3 is an unrelated 40 Hz
%   tone. All trials in one bin.
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
    EEG.nbchan = 3;
    EEG.srate  = srate;
    EEG.data   = data;
    EEG.bindesc = struct('index', 1, 'label', 'Bin1', 'trials', 1:nTrials, 'combo', []);
end

function inside = clearOfEdges(info, EEG)
%CLEAROFEDGES  nFreqs x nTime: the samples more than half a wavelet from
%   either end of the epoch, from INFO's half-wavelets.
    nT = numel(EEG.times);
    halfLen = round(info.halfWaveletMs * EEG.srate / 1000);
    inside = false(numel(halfLen), nT);
    for f = 1:numel(halfLen)
        inside(f, halfLen(f) + 1:nT - halfLen(f)) = true;
    end
end

function opts = waveletOpts()
    opts = struct('Method', 'Wavelet', 'RefIndex', 1, 'MinFreq', 10, 'MaxFreq', 30, ...
        'NumFreqs', 5, 'MinCycles', 3, 'MaxCycles', 5);
end

function opts = stftOpts()
    opts = struct('Method', 'STFT', 'RefIndex', 1, 'MinFreq', 10, 'MaxFreq', 30, ...
        'WindowMs', 200, 'PadRatio', 2);
end

function opts = filterHilbertOpts()
    opts = struct('Method', 'FilterHilbert', 'RefIndex', 1, 'MinFreq', 10, 'MaxFreq', 30, ...
        'NumFreqs', 5, 'BandwidthHz', 4, 'StepMs', 8);
end
