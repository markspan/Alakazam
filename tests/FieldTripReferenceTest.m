classdef FieldTripReferenceTest < matlab.unittest.TestCase
%FIELDTRIPREFERENCETEST  Alakazam's own spectral computations against
%   FieldTrip's, on the same data with the same settings: the wavelet ERSP
%   (ComputeErsp) against ft_freqanalysis('wavelet') and
%   ft_freqbaseline('db'), the wavelet coherence (ComputeCoherenceMap)
%   against ft_connectivityanalysis('coh'), Fourier's PSD against
%   ft_freqanalysis('mtmfft') with a Hann taper, and SpectralMeasure: its
%   amplitude, phase, ITC and SNR against the same quantities taken from
%   ft_freqanalysis('mtmfft'), and its frame coherence against
%   ft_freqanalysis('mtmconvol') with ft_connectivityanalysis('coh').
%
%   WHY. Each of these is a hand-written computation with a toolbox that
%   does the same (Docs/toolbox-audit.md). Their own tests check properties
%   that hold by construction, which a convention differing from the
%   field's passes untouched. M26 was one: power computed over the
%   wavelet's edges and a mean-of-dB baseline, which put +1.4 dB of
%   "event-related" power on stationary noise and agreed with no toolbox.
%   A comparison like this is what catches that.
%
%   WHAT DIFFERS, AND THE TOLERANCES.
%     Scale. FieldTrip's wavelet power is twice ours and its mtmfft power
%       is per frequency bin, not per hertz. Both cancel in a dB baseline
%       and in a coherence; the PSD is compared after converting FieldTrip's
%       to a density (times the padded length over the sample rate), and
%       then agrees to 1e-15 at every bin, 0 Hz and Nyquist included.
%     Coherence. FieldTrip's 'coh' is the magnitude of the coherency, ours
%       its square, so FieldTrip's is squared here.
%     The wavelet. Both run the Gaussian to three sigma with sigma =
%       cycles / (2 pi f), but FieldTrip cuts it to a whole number of
%       samples counted from -3 sigma, so its length is odd or even, and
%       its peak off the sample grid, by however 3 sigma falls between two
%       samples. With 3 to 6 cycles at 4, 8 and 16 Hz the ERSPs differed by
%       up to 0.13 dB, more than the 0.04 to 0.08 dB a mean-of-dB baseline
%       (M26) adds, which would then pass. The cycles below are chosen
%       instead so that 3 sigma lies a twentieth of a sample past a whole
%       number of samples at every frequency; the ERSPs then agree to 0.027
%       dB (tolerance 0.04) and their mean per channel and frequency to
%       0.002 dB (tolerance 0.01), and the coherences to 0.006 (tolerance
%       0.015). The mean-of-dB baseline moves four of the six means by 0.04
%       to 0.08 dB and fails.
%     The edges. Both leave half a wavelet blank at each end; the rounding
%       above can move the first and last computed sample by one. Computing
%       over the edges, the other half of M26, moves them by the whole
%       half-wavelet and fails.
%     SpectralMeasure reads exact frequencies, FieldTrip its grid, so the
%       comparison is at frequencies on the grid, where the two transforms
%       are the same DFT; everything then agrees to rounding (1e-13), the
%       rejected trials included. The frame coherence is compared with an
%       odd frame length: with an even one FieldTrip centres each frame one
%       sample earlier than TransTools.FrameStarts, which moves the average
%       by about 0.002, and with the frames lined up the two agree frame by
%       frame to 1e-15.
%
%   Skipped when FieldTrip is not installed; never downloads it (see
%   FieldTripFixtures).
%
%   Run with: runtests('tests/FieldTripReferenceTest.m').
%
%   See also COMPUTEERSP, COMPUTECOHERENCEMAP, FOURIER, FIELDTRIPFIXTURES.

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            transformations = fullfile(root, 'src', 'Transformations');
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(root, 'src')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(transformations));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(transformations, 'TimeFrequency')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(transformations, 'CoherenceMap')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(transformations, 'Fourier')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(transformations, 'SpectralMeasure')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(transformations, 'Measure')));   % measureChannelSpecs
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(root, 'src', 'Support')));     % spectralFreqSpecs
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(transformations, 'Baseline')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(transformations, 'DCDetrend')));
        end

        function requireFieldTrip(testCase)
            FieldTripFixtures.require(testCase);
        end
    end

    methods (Test)
        function theErspMatchesFieldTrip(testCase)
        %THEERSPMATCHESFIELDTRIP  An 8 Hz burst at a random phase on every
        %   trial, in noise, analysed at 4, 8 and 16 Hz and a -200 to 0 ms
        %   dB baseline, by both. The cycles, 3.0846 to 6.1726, put 3 sigma
        %   at 92.05, 69.06 and 46.05 samples (see the class header).
            EEG = burstFixture();
            opts = struct('MinFreq', 4, 'MaxFreq', 16, 'NumFreqs', 3, 'MinCycles', 3.0846, ...
                'MaxCycles', 6.1726, 'BaselineStart', -200, 'BaselineStop', 0);
            [ersp, freqs] = ComputeErsp(EEG, opts);

            cfg = struct('method', 'wavelet', 'output', 'pow', 'foi', freqs, ...
                'width', linspace(opts.MinCycles, opts.MaxCycles, opts.NumFreqs), 'gwidth', 3, ...
                'toi', EEG.times / 1000, 'polyremoval', -1, 'keeptrials', 'no');
            freq = FieldTripFixtures.quietly(@() ft_freqanalysis(cfg, toFieldTrip(EEG)));
            base = FieldTripFixtures.quietly(@() ft_freqbaseline( ...
                struct('baseline', [-0.2 0], 'baselinetype', 'db'), freq));
            testCase.assertEqual(freq.freq, freqs, 'AbsTol', 1e-9, 'FieldTrip analysed other frequencies.');

            ours = ersp(:, :, :, 1);
            theirs = base.powspctrm;
            both = isfinite(ours) & isfinite(theirs);
            testCase.verifyEqual(ours(both), theirs(both), 'AbsTol', 0.04, ...
                'The ERSP differs from FieldTrip''s (dB).');
            testCase.verifyEqual(mean(ours - theirs, 3, 'omitnan'), zeros(2, 3), 'AbsTol', 0.01, ...
                'The ERSP is offset from FieldTrip''s, as a different baseline would put it (dB).');
            verifyBlankEdgesAgree(testCase, ours, theirs);
        end

        function theWaveletCoherenceMatchesFieldTrip(testCase)
        %THEWAVELETCOHERENCEMATCHESFIELDTRIP  A 20 Hz tone at a random phase
        %   on every trial, in the reference and in channel A, and noise in
        %   channel B, analysed at 10, 20 and 40 Hz. The cycles, 3.02 to
        %   7.0538, put 3 sigma at 36.05, 30.06 and 21.05 samples.
            EEG = toneFixture();
            opts = struct('Method', 'Wavelet', 'RefIndex', 3, 'MinFreq', 10, 'MaxFreq', 40, ...
                'NumFreqs', 3, 'MinCycles', 3.02, 'MaxCycles', 7.0538);
            [coh, freqs] = ComputeCoherenceMap(EEG, opts);

            cfg = struct('method', 'wavelet', 'output', 'fourier', 'foi', freqs, ...
                'width', linspace(opts.MinCycles, opts.MaxCycles, opts.NumFreqs), 'gwidth', 3, ...
                'toi', EEG.times / 1000, 'polyremoval', -1, 'keeptrials', 'yes');
            freq = FieldTripFixtures.quietly(@() ft_freqanalysis(cfg, toFieldTrip(EEG)));
            conn = FieldTripFixtures.quietly(@() ft_connectivityanalysis( ...
                struct('method', 'coh', 'channelcmb', {{'R', 'all'}}), freq));
            testCase.assertEqual(conn.freq, freqs, 'AbsTol', 1e-9, 'FieldTrip analysed other frequencies.');

            for ch = 1:2
                label = EEG.chanlocs(ch).labels;
                row = pairRow(conn.labelcmb, label, 'R');
                testCase.assertNumElements(row, 1, sprintf('FieldTrip has no %s-R pair.', label));
                theirs = reshape(conn.cohspctrm(row, :, :), numel(freqs), []) .^ 2;
                ours = squeeze(coh(ch, :, :, 1));
                both = isfinite(ours) & isfinite(theirs);
                testCase.verifyEqual(ours(both), theirs(both), 'AbsTol', 0.015, ...
                    sprintf('Coherence of %s to the reference.', label));
                verifyBlankEdgesAgree(testCase, ours, theirs);
            end
        end

        function thePsdMatchesFieldTrip(testCase)
        %THEPSDMATCHESFIELDTRIP  Four 500-sample segments at 250 Hz, a 10 Hz
        %   and a 37.3 Hz sine in noise, Hann-tapered and padded to 512 by
        %   both.
            EEG = segmentFixture();
            opts = struct('Output', 'PSD', 'FullSpectrum', false, 'Window', 'Hanning', ...
                'Window_Length', 100, 'Resolution', 'Max', 'ResVal', 0.333);
            out = Fourier(EEG, opts);

            cfg = struct('method', 'mtmfft', 'output', 'pow', 'taper', 'hanning', ...
                'foilim', [0, EEG.srate / 2], 'pad', 'nextpow2', 'polyremoval', -1, 'keeptrials', 'no');
            freq = FieldTripFixtures.quietly(@() ft_freqanalysis(cfg, toFieldTrip(EEG)));
            testCase.assertEqual(freq.freq, out.freqs, 'AbsTol', 1e-9, 'The frequency grids differ.');

            nfft = 2 ^ nextpow2(size(EEG.data, 2));
            theirs = freq.powspctrm * nfft / EEG.srate;   % per bin -> per hertz
            testCase.verifyEqual(mean(out.data, 3), theirs, 'RelTol', 1e-10);
        end

        function theSpectralMeasuresMatchFieldTrip(testCase)
        %THESPECTRALMEASURESMATCHFIELDTRIP  SpectralMeasure at 12 and 20 Hz on
        %   A and at 20 Hz on B, against the same quantities taken from
        %   ft_freqanalysis('mtmfft') with a Hann taper: the evoked
        %   coefficient's amplitude and phase (FieldTrip measures phase from
        %   time zero), the length of the mean unit phasor (ITC), and the
        %   evoked power over the mean of the ten bins either side past a
        %   one-bin guard (SNR). Trial 4 is rejected on A only and trial 9 on
        %   every channel; FieldTrip's coefficients for them are NaN and are
        %   left out of every mean, as SpectralMeasure leaves them out.
            EEG = spectralFixture();
            rows = {spectralRow('A', 12), spectralRow('A', 20), spectralRow('B', 20)};
            opts = struct('rows', {rows}, 'fundamentals', '', 'refChannel', '', 'method', 'Hann', ...
                'tapers', 3, 'snrNeighbours', 10, 'snrGuard', 1);
            out = SpectralMeasure(EEG, opts);

            cfg = struct('method', 'mtmfft', 'output', 'fourier', 'taper', 'hann', ...
                'foilim', [0, EEG.srate / 2], 'keeptrials', 'yes', 'polyremoval', -1, 'pad', 'maxperlen');
            freq = FieldTripFixtures.quietly(@() ft_freqanalysis(cfg, toFieldTrip(EEG)));
            nsamp = size(EEG.data, 2);
            taper = hann(nsamp);
            % FieldTrip scales each coefficient by sqrt(2 / N) / norm(taper);
            % SpectralMeasure's amplitude is 2 |X| / sum(taper).
            toAmplitude = (2 / sum(taper)) / (sqrt(2 / nsamp) / norm(taper));

            for r = 1:numel(rows)
                m = out.spectralMeasures{r};
                ch = find(strcmp({EEG.chanlocs.labels}, rows{r}.channels));
                fi = find(abs(freq.freq - str2double(rows{r}.freq)) < 1e-9);
                testCase.assertNumElements(fi, 1, 'The frequency is not on FieldTrip''s grid.');
                coefficients = squeeze(freq.fourierspctrm(:, ch, :));        % trials x freqs
                evoked = mean(coefficients, 1, 'omitnan');
                power = abs(evoked) .^ 2;
                what = sprintf('%s at %s Hz', rows{r}.channels, rows{r}.freq);

                testCase.verifyEqual(m.amplitude, abs(evoked(fi)) * toAmplitude, 'RelTol', 1e-9, what);
                testCase.verifyEqual(angle(exp(1i * (m.phase - angle(evoked(fi))))), 0, 'AbsTol', 1e-9, what);
                unit = coefficients(:, fi) ./ abs(coefficients(:, fi));
                testCase.verifyEqual(m.itc, abs(mean(unit, 'omitnan')), 'AbsTol', 1e-12, what);
                neighbours = fi + [-(2:11), 2:11];
                testCase.verifyEqual(m.snr, power(fi) / mean(power(neighbours)), 'RelTol', 1e-9, what);
            end
        end

        function theFrameCoherenceIsFieldTripsSlidingWindowCoherence(testCase)
        %THEFRAMECOHERENCEISFIELDTRIPSSLIDINGWINDOWCOHERENCE  SpectralMeasure's
        %   frame coherence at 20 Hz, of A and of B to R, against
        %   ft_freqanalysis('mtmconvol') with a Hann taper on the same 101-sample
        %   frames, ft_connectivityanalysis('coh') per frame, and the mean of the
        %   squared coherence over the frames; the phase lag against the
        %   circular mean of the coherency's angle. Trial 3 is rejected on every
        %   channel.
            EEG = toneFixture();
            EEG.data(:, :, 3) = NaN;
            win = 101;
            rows = {spectralRow('A', 20), spectralRow('B', 20)};
            opts = struct('rows', {rows}, 'fundamentals', '', 'refChannel', 'R', 'method', 'Hann', ...
                'tapers', 3, 'snrNeighbours', 10, 'snrGuard', 1, 'coherenceMethod', 'frames', ...
                'crossf', struct('WinSize', win));
            out = SpectralMeasure(EEG, opts);

            [~, centres] = TransTools.FrameStarts(size(EEG.data, 2), win);
            cfg = struct('method', 'mtmconvol', 'output', 'fourier', 'taper', 'hann', 'foi', 20, ...
                't_ftimwin', win / EEG.srate, 'toi', EEG.times(centres) / 1000, 'keeptrials', 'yes', ...
                'polyremoval', -1, 'pad', 'maxperlen');
            freq = FieldTripFixtures.quietly(@() ft_freqanalysis(cfg, toFieldTrip(EEG)));
            conn = FieldTripFixtures.quietly(@() ft_connectivityanalysis(struct('method', 'coh', ...
                'complex', 'complex', 'channelcmb', {{'R', 'all'}}), freq));

            for r = 1:numel(rows)
                label = rows{r}.channels;
                row = pairRow(conn.labelcmb, label, 'R');
                coherency = reshape(conn.cohspctrm(row, 1, :), 1, []);
                testCase.assertTrue(all(isfinite(coherency)), 'FieldTrip should compute every frame.');
                if strcmp(conn.labelcmb{row, 1}, 'R')
                    coherency = conj(coherency);   % FieldTrip's R x conj(A); ours is A x conj(R)
                end
                testCase.verifyEqual(out.spectralMeasures{r}.coherence, mean(abs(coherency) .^ 2), ...
                    'AbsTol', 1e-10, label);
                testCase.verifyEqual(out.spectralMeasures{r}.phaselag, ...
                    angle(mean(coherency ./ abs(coherency))), 'AbsTol', 1e-9, label);
            end
        end

        function theBaselineIsFieldTripsDemean(testCase)
        %THEBASELINEISFIELDTRIPSDEMEAN  Baseline against ft_preprocessing with
        %   demean on the same window, for a window whose ends fall between
        %   samples (-149 to -51 ms), one reaching past the epoch (-500 to 0
        %   ms) and one on samples (-100 to 0 ms), with a rejected sample in
        %   one channel's window. Exact ties are left to BaselineTest: in
        %   seconds, as FieldTrip has them, a tie is at the mercy of rounding.
            EEG = timeDomainFixture();
            EEG.data(1, 30, 2) = NaN;
            for window = {[-149 -51], [-500 0], [-100 0]}
                w = window{1};
                ours = Baseline(EEG, struct('Start', w(1), 'Stop', w(2)));
                cfg = struct('demean', 'yes', 'baselinewindow', w / 1000);
                ft = FieldTripFixtures.quietly(@() ft_preprocessing(cfg, toFieldTrip(EEG)));
                testCase.verifyEqual(double(ours.data), cat(3, ft.trial{:}), 'AbsTol', 1e-10, ...
                    sprintf('Window %g to %g ms.', w(1), w(2)));
            end
        end

        function theDetrendIsFieldTripsPolyremoval(testCase)
        %THEDETRENDISFIELDTRIPSPOLYREMOVAL  DC-Detrend's least-squares fit,
        %   orders 0 to 2, with a rejected sample. Fitted over the whole epoch
        %   it is ft_preprocessing's polyremoval. The tolerance is FieldTrip's
        %   own: it fits the raw sample index, which costs it about 2e-9 uV at
        %   order 2 on 200 samples (and the whole trend on a long record,
        %   which is why DC-Detrend uses polyfit). ft_preprocessing has no
        %   fitting window, so the fit on -199 to 1 ms is held to
        %   ft_preproc_polyremoval on the samples FieldTrip's nearest rule
        %   gives (-200 and 0 ms), subtracted from the whole epoch.
            EEG = timeDomainFixture();
            t = EEG.times / 1000;
            EEG.data = EEG.data + 3 * t + 2 * t .^ 2;
            EEG.data(2, 40, 3) = NaN;
            for order = 0:2
                whole = DCDetrend(EEG, detrendOpts(order, 0, 0));
                cfg = struct('polyremoval', 'yes', 'polyorder', order);
                ft = FieldTripFixtures.quietly(@() ft_preprocessing(cfg, toFieldTrip(EEG)));
                testCase.verifyEqual(double(whole.data), cat(3, ft.trial{:}), 'AbsTol', 1e-7, ...
                    sprintf('Order %d over the whole epoch.', order));

                windowed = DCDetrend(EEG, detrendOpts(order, -199, 1));
                first = 1;                                  % -199 ms is nearest -200
                last = find(EEG.times == 0);                % 1 ms is nearest 0
                expected = zeros(size(EEG.data));
                for tr = 1:size(EEG.data, 3)
                    expected(:, :, tr) = ft_preproc_polyremoval(double(EEG.data(:, :, tr)), order, first, last);
                end
                testCase.verifyEqual(double(windowed.data), expected, 'AbsTol', 1e-7, ...
                    sprintf('Order %d fitted on -200 to 0 ms.', order));
            end
        end
    end
end

function opts = detrendOpts(order, startMs, stopMs)
    names = {'0 - mean only', '1 - linear', '2 - quadratic'};
    opts = struct('Channels', {{}}, 'Order', names{order + 1}, 'Method', 'Least squares', ...
        'FitStart', startMs, 'FitStop', stopMs);
end

function EEG = timeDomainFixture()
%TIMEDOMAINFIXTURE  Channels A, B and C, 6 trials of -200 to 596 ms at 250
%   Hz, the times exact integers 4 ms apart: noise around an offset.
    previous = rng(29);
    restore = onCleanup(@() rng(previous));
    times = -200:4:596;
    EEG = epoched(5 + randn(3, numel(times), 6), {'A', 'B', 'C'}, 250, times);
end

function row = spectralRow(channel, hz)
    row = struct('label', sprintf('%s%g', channel, hz), 'freq', num2str(hz), 'channels', channel);
end

function EEG = spectralFixture()
%SPECTRALFIXTURE  Channels A and B, 24 trials of 2 s at 250 Hz, starting at
%   -396 ms, so that time zero is not a whole number of cycles from the first
%   sample at 12 or 20 Hz: noise, and on A a 12 Hz and a 20 Hz component, each
%   with its own trial-to-trial phase scatter. Trial 4 is rejected (NaN) on A,
%   trial 9 on both.
    previous = rng(23);
    restore = onCleanup(@() rng(previous));
    srate = 250;
    times = (-99:400) / srate * 1000;
    t = times / 1000;
    nTrials = 24;
    data = randn(2, numel(t), nTrials);
    for tr = 1:nTrials
        data(1, :, tr) = data(1, :, tr) + 0.8 * cos(2 * pi * 20 * t + 0.5 * randn) ...
            + 0.5 * cos(2 * pi * 12 * t + 0.4 + 0.3 * randn);
    end
    data(1, :, 4) = NaN;
    data(:, :, 9) = NaN;
    EEG = epoched(data, {'A', 'B'}, srate, times);
end

% ======================================================================= %
function verifyBlankEdgesAgree(testCase, ours, theirs)
%VERIFYBLANKEDGESAGREE  Per channel and frequency, the first and last
%   computed samples lie within one sample of FieldTrip's.
    sz = size(ours);
    ours = reshape(ours, [], sz(end));
    theirs = reshape(theirs, [], sz(end));
    for k = 1:size(ours, 1)
        o = find(isfinite(ours(k, :)));
        f = find(isfinite(theirs(k, :)));
        testCase.assertNotEmpty(o);
        testCase.assertNotEmpty(f);
        testCase.verifyLessThanOrEqual(abs([o(1) - f(1), o(end) - f(end)]), 1, ...
            'The blank edges should agree with FieldTrip''s to a sample.');
    end
end

function row = pairRow(labelcmb, a, b)
    row = find((strcmp(labelcmb(:, 1), a) & strcmp(labelcmb(:, 2), b)) | ...
        (strcmp(labelcmb(:, 1), b) & strcmp(labelcmb(:, 2), a)));
end

function data = toFieldTrip(EEG)
%TOFIELDTRIP  EEG as a FieldTrip raw data structure, one trial per epoch,
%   with time in seconds.
    nTrials = size(EEG.data, 3);
    data = struct('label', {reshape({EEG.chanlocs.labels}, [], 1)}, 'fsample', EEG.srate);
    data.trial = arrayfun(@(k) EEG.data(:, :, k), 1:nTrials, 'UniformOutput', false);
    data.time = repmat({EEG.times / 1000}, 1, nTrials);
end

function EEG = epoched(data, labels, srate, times)
    EEG = struct('DataFormat', 'EPOCHED', 'times', times, 'nbchan', size(data, 1), ...
        'srate', srate, 'data', data, 'pnts', size(data, 2), 'trials', size(data, 3));
    EEG.chanlocs = struct('labels', labels);
    EEG.bindesc = struct('index', 1, 'label', 'Bin1', 'trials', 1:size(data, 3), 'combo', []);
end

function EEG = burstFixture()
%BURSTFIXTURE  Channels A and B, 10 trials of -1000 to 996 ms at 250 Hz:
%   noise, and on A an 8 Hz burst around 400 ms at a random phase on
%   every trial. Two seconds, so 4, 8 and 16 Hz are exact FFT bins.
    previous = rng(7);
    restore = onCleanup(@() rng(previous));
    srate = 250;
    times = (-250:249) / srate * 1000;
    t = times / 1000;
    nTrials = 10;
    envelope = exp(-((t - 0.4) / 0.1) .^ 2);
    data = randn(2, numel(t), nTrials);
    for tr = 1:nTrials
        data(1, :, tr) = data(1, :, tr) + 2 * envelope .* cos(2 * pi * 8 * t + 2 * pi * rand);
    end
    EEG = epoched(data, {'A', 'B'}, srate, times);
end

function EEG = toneFixture()
%TONEFIXTURE  Channels A, B and the reference R, 10 trials of -1000 to
%   996 ms at 250 Hz: a 20 Hz tone at a random phase on every trial in R
%   and A, each with its own noise, and only noise in B.
    previous = rng(11);
    restore = onCleanup(@() rng(previous));
    srate = 250;
    times = (-250:249) / srate * 1000;
    t = times / 1000;
    nTrials = 10;
    data = randn(3, numel(t), nTrials);
    for tr = 1:nTrials
        tone = cos(2 * pi * 20 * t + 2 * pi * rand);
        data(3, :, tr) = 0.5 * data(3, :, tr) + tone;
        data(1, :, tr) = data(1, :, tr) + 0.8 * tone;
    end
    EEG = epoched(data, {'A', 'B', 'R'}, srate, times);
end

function EEG = segmentFixture()
%SEGMENTFIXTURE  Channels A and B, four 500-sample segments at 250 Hz: a
%   10 Hz and a 37.3 Hz sine in noise on A, noise on B.
    previous = rng(5);
    restore = onCleanup(@() rng(previous));
    srate = 250;
    t = (0:499) / srate;
    data = randn(2, numel(t), 4);
    for s = 1:4
        data(1, :, s) = data(1, :, s) + 3 * sin(2 * pi * 10 * t + s) + sin(2 * pi * 37.3 * t);
    end
    EEG = epoched(data, {'A', 'B'}, srate, t * 1000);
end
