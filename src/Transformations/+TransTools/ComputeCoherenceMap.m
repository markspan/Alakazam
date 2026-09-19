function [coh, freqs, cohTimes, refPower] = ComputeCoherenceMap(input, opts)
%COMPUTECOHERENCEMAP  Time-resolved magnitude-squared coherence between every
%   channel and a reference channel (e.g. a photodiode), as an
%   nChan x nFreqs x nTime x nBins array -- the RIFT / frequency-tagging
%   read-out drawn by CoherenceView, the coherence counterpart of ComputeErsp.
%
%   For each frequency and time point, the coherence is estimated across the
%   bin's trials from the complex time-frequency coefficients of the channel
%   (X) and the reference (R):
%       coh = |sum_trials X .* conj(R)|^2 / ( sum_trials|X|^2 .* sum_trials|R|^2 )
%   i.e. the trial-wise cross-spectra are averaged, then normalised by the
%   trial-averaged autospectra and squared -- the same magnitude-squared
%   coherence SpectralMeasure.m computes (and the RIFT paper's Eq. 1), but
%   resolved at every time point rather than averaged over the epoch.
%
%   INPUT is an EEGLAB-style epoched EEG struct (DataFormat 'EPOCHED',
%   EEG.bindesc(b).trials indexing the 3rd dimension per bin). OPTS fields:
%     Method     'Wavelet', 'STFT' or 'FilterHilbert'
%     RefIndex   row of the reference channel in EEG.data
%     MinFreq, MaxFreq, NumFreqs   frequency range (Hz)
%     MinCycles, MaxCycles         Morlet cycles at the extremes (Wavelet)
%     WindowMs, PadRatio           STFT window (ms) and zero-padding ratio
%     Taper      STFT window taper, 'Hann' (default) or 'Boxcar'. A boxcar has
%                the narrowest main lobe, which Arora et al. (2026) found
%                captures a tagging response better than a Hann, at the price
%                of more spectral leakage.
%     BandwidthHz, StepMs          FilterHilbert only: the full width at half
%                maximum of each band (default 2 Hz) and the spacing of the
%                output time points (default 50 ms)
%
%   FILTERHILBERT band-passes each trial around every analysed frequency and
%   takes the analytic signal, which is the filter-Hilbert approach Arora et
%   al. (2026) describe. Each band is a Gaussian gain in the frequency domain
%   (zero-phase, no ringing), applied to the positive frequencies only, so one
%   inverse FFT gives the band-passed analytic signal directly. The epoch is
%   zero-padded by three time-constants on each side so the filter does not
%   wrap round the epoch ends. Its time resolution is set by BANDWIDTHHZ
%   (about 1 / (2 pi sigma_f) seconds), which is finer than a 500 ms STFT for
%   a 2 Hz band only when the response changes more slowly than that.
%
%   Combination (difference) bins are left NaN: coherence is a normalised
%   ratio, not linear across bins, so (unlike ComputeErsp's ERSP) it cannot be
%   derived from the referenced bins. A bin with fewer than two trials is left
%   NaN as well: with a single trial the numerator and denominator are the
%   same number, so coherence is exactly 1 everywhere and says nothing. The
%   reference channel's own row is left NaN (self-coherence is trivially 1).
%   COHTIMES is EEG.times for Wavelet, the STFT frame centres for STFT, or
%   every STEPMS-th sample of EEG.times for FilterHilbert; FREQS is the
%   analysed frequency vector.
%
%   REFPOWER, an nFreqs x nTime x nBins array, is the reference channel's
%   OWN summed power (sum_trials|R|^2, the same Syy the coherence
%   denominator uses) -- exactly the quantity self-coherence cannot supply
%   (see above), and the one that answers "which frequency was the
%   reference itself doing the most at", independent of how strongly any
%   EEG channel happened to track it. exportCoherenceCSVs.m uses this,
%   not an average of every channel's own coherence, to read off the
%   tagged frequency: a physical flicker signal (a photodiode) shows one
%   clean peak, where an EEG channel's coherence to it is small, noisy, and
%   can spuriously peak at a neighbouring or unrelated frequency band
%   dominated by something else (line noise, a harmonic, another
%   simultaneously-tagged condition). Reported directly: with several
%   RIFT/SSVEP conditions tagged at different true frequencies, averaging
%   coherence over every EEG channel picked the same wrong frequency for
%   two different conditions.
    switch lower(char(string(opts.Method)))
        case 'stft'
            [coh, freqs, cohTimes, refPower] = stftCoherence(input, opts);
        case 'filterhilbert'
            [coh, freqs, cohTimes, refPower] = filterHilbertCoherence(input, opts);
        otherwise
            [coh, freqs, cohTimes, refPower] = waveletCoherence(input, opts);
    end
end

% ======================================================================= %
function [coh, freqs, cohTimes, refPower] = waveletCoherence(input, opts)
%WAVELETCOHERENCE  Morlet-wavelet time-frequency coherence, reusing the same
%   variable-cycle wavelet-FFT precompute as TransTools.ComputeErsp.
    times = input.times;
    nT    = numel(times);
    nChan = input.nbchan;
    nBins = numel(input.bindesc);
    srate = input.srate;
    refIdx = opts.RefIndex;

    freqs  = logspace(log10(opts.MinFreq), log10(opts.MaxFreq), opts.NumFreqs);
    cycles = linspace(opts.MinCycles, opts.MaxCycles, opts.NumFreqs);
    nF     = opts.NumFreqs;

    sigmaTMin     = opts.MinCycles / (2 * pi * opts.MinFreq);
    maxWaveletLen = 2 * ceil(3 * sigmaTMin * srate) + 1;
    nfft          = 2 ^ nextpow2(nT + maxWaveletLen - 1);

    waveletFFTs = cell(1, nF);
    halfLens    = zeros(1, nF);
    for fi = 1:nF
        sigmaT  = cycles(fi) / (2 * pi * freqs(fi));
        halfLen = ceil(3 * sigmaT * srate);
        tw = (-halfLen:halfLen) / srate;
        wavelet = exp(2i * pi * freqs(fi) * tw) .* exp(-tw.^2 / (2 * sigmaT^2));
        wavelet = wavelet / sqrt(sum(abs(wavelet).^2));
        waveletFFTs{fi} = fft(wavelet, nfft);
        halfLens(fi) = halfLen;
    end

    analytic = @(sig) waveletTransform(sig, waveletFFTs, halfLens, nfft, nT, nF);
    [coh, refPower] = coherenceOverBins(input, nChan, nF, nT, nBins, refIdx, analytic);
    cohTimes = times;
end

function A = waveletTransform(sig, waveletFFTs, halfLens, nfft, nT, nF)
%WAVELETTRANSFORM  nF x nT complex coefficients for one trial's signal.
    sigFFT = fft(sig(:).', nfft);
    A = zeros(nF, nT);
    for fi = 1:nF
        conv = ifft(sigFFT .* waveletFFTs{fi});
        hl = halfLens(fi);
        A(fi, :) = conv(hl + 1 : hl + nT);
    end
end

% ======================================================================= %
function [coh, freqs, cohTimes, refPower] = stftCoherence(input, opts)
%STFTCOHERENCE  Fixed-window short-time Fourier coherence (the RIFT paper's
%   newcrossf approach): a tapered window slid across the epoch,
%   zero-padded, giving complex coefficients per frame and frequency.
    times = input.times;
    nT    = numel(times);
    nChan = input.nbchan;
    nBins = numel(input.bindesc);
    srate = input.srate;
    refIdx = opts.RefIndex;

    win = max(4, round(opts.WindowMs / 1000 * srate));   % window length (samples)
    win = min(win, nT);
    step = max(1, round(win / 4));                        % 75% overlap
    pad  = max(1, round(opts.PadRatio));
    nfft = 2 ^ nextpow2(win * pad);
    taper = makeTaper(TransTools.FieldOr(opts, 'Taper', 'Hann'), win);

    fullFreqs = (0:nfft - 1) * srate / nfft;
    fsel = find(fullFreqs >= opts.MinFreq & fullFreqs <= opts.MaxFreq);
    freqs = fullFreqs(fsel);
    nF = numel(freqs);

    starts = 1:step:(nT - win + 1);
    if isempty(starts); starts = 1; end
    centres = starts + floor(win / 2);
    cohTimes = times(min(centres, nT));
    nFrame = numel(starts);

    analytic = @(sig) stftTransform(sig, taper, starts, win, nfft, fsel, nF, nFrame);
    [coh, refPower] = coherenceOverBins(input, nChan, nF, nFrame, nBins, refIdx, analytic);
end

function A = stftTransform(sig, taper, starts, win, nfft, fsel, nF, nFrame)
%STFTTRANSFORM  nF x nFrame complex coefficients for one trial's signal.
    sig = sig(:).';
    A = zeros(nF, nFrame);
    for k = 1:nFrame
        seg = sig(starts(k) : starts(k) + win - 1) .* taper;
        F = fft(seg, nfft);
        A(:, k) = F(fsel).';
    end
end

function w = makeTaper(kind, n)
%MAKETAPER  The STFT window: Hann (low side lobes) or boxcar (narrow main lobe).
    switch lower(char(string(kind)))
        case 'hann'
            w = 0.5 - 0.5 * cos(2 * pi * (0:n - 1) / (n - 1));
        case {'boxcar', 'rectangular'}
            w = ones(1, n);
        otherwise
            throw(MException('Alakazam:ComputeCoherenceMap', ...
                ['Problem in ComputeCoherenceMap: I''m afraid "%s" is not a window ' ...
                 'taper I know. Please use Hann or Boxcar.'], char(string(kind))));
    end
end

% ======================================================================= %
function [coh, freqs, cohTimes, refPower] = filterHilbertCoherence(input, opts)
%FILTERHILBERTCOHERENCE  Band-pass around each frequency, then the analytic
%   signal. See the header of ComputeCoherenceMap for the design.
    times = input.times;
    nT    = numel(times);
    nChan = input.nbchan;
    nBins = numel(input.bindesc);
    srate = input.srate;
    refIdx = opts.RefIndex;

    bandwidth = double(TransTools.FieldOr(opts, 'BandwidthHz', 2));
    stepMs    = double(TransTools.FieldOr(opts, 'StepMs', 50));
    if ~isscalar(bandwidth) || ~(bandwidth > 0)
        throw(MException('Alakazam:ComputeCoherenceMap', ...
            'Problem in ComputeCoherenceMap: I''m afraid the filter-Hilbert bandwidth must be greater than 0 Hz.'));
    end
    if ~isscalar(stepMs) || ~(stepMs > 0)
        throw(MException('Alakazam:ComputeCoherenceMap', ...
            'Problem in ComputeCoherenceMap: I''m afraid the filter-Hilbert time step must be greater than 0 ms.'));
    end

    nF    = opts.NumFreqs;
    freqs = linspace(opts.MinFreq, opts.MaxFreq, nF);

    sigmaF = bandwidth / (2 * sqrt(2 * log(2)));     % FWHM = bandwidth
    sigmaT = 1 / (2 * pi * sigmaF);                  % seconds
    pad    = ceil(3 * sigmaT * srate);
    nfft   = 2 ^ nextpow2(nT + 2 * pad);

    fAxis = (0:nfft - 1) * srate / nfft;
    half  = nfft / 2;
    gain  = zeros(1, nfft);                          % analytic-signal gain
    gain(2:half) = 2;
    gain(1) = 1;
    gain(half + 1) = 1;
    masks = zeros(nF, nfft);
    for fi = 1:nF
        masks(fi, :) = gain .* exp(-0.5 * ((fAxis - freqs(fi)) / sigmaF) .^ 2);
    end

    stepSamples = max(1, round(stepMs / 1000 * srate));
    keep = 1:stepSamples:nT;
    cohTimes = times(keep);

    analytic = @(sig) hilbertBands(sig, masks, pad, nT, keep, nfft);
    [coh, refPower] = coherenceOverBins(input, nChan, nF, numel(keep), nBins, refIdx, analytic);
end

function A = hilbertBands(sig, masks, pad, nT, keep, nfft)
%HILBERTBANDS  nF x numel(keep) complex band-passed analytic signal.
    sig = double(sig(:).');
    x = zeros(1, nfft);
    x(pad + 1 : pad + nT) = sig - mean(sig);
    Y = ifft(masks .* fft(x, nfft), [], 2);
    A = Y(:, pad + keep);
end

% ======================================================================= %
function [coh, refPower] = coherenceOverBins(input, nChan, nF, nTime, nBins, refIdx, analytic)
%COHERENCEOVERBINS  Accumulate trial-wise cross/auto spectra per bin and form
%   the magnitude-squared coherence to the reference. ANALYTIC(sig) returns an
%   nF x nTime complex time-frequency matrix for one trial's signal.
%
%   REFPOWER (nF x nTime x nBins) is the reference's own trial-averaged
%   power, |R|^2. See this file's own ComputeCoherenceMap header for why
%   it is returned at all (self-coherence cannot supply it, and it is a
%   cleaner read-out of the tagged frequency than any channel's coherence
%   to the reference). It is returned for a bin with a single trial too,
%   where the coherence itself is not (see the same header).
    coh = nan(nChan, nF, nTime, nBins);
    refPower = nan(nF, nTime, nBins);
    isCombo = false(1, nBins);
    if isfield(input.bindesc, 'combo')
        isCombo = ~cellfun(@isempty, {input.bindesc.combo});
    end

    TransTools.progressbar;
    binsToDo = find(~isCombo);
    total = max(1, numel(binsToDo));
    for bi = 1:numel(binsToDo)
        b = binsToDo(bi);
        trials = input.bindesc(b).trials;
        if isempty(trials)
            TransTools.progressbar(bi / total);
            continue;
        end
        estimable = numel(trials) >= 2;
        Sxy = zeros(nChan, nF, nTime);
        Sxx = zeros(nChan, nF, nTime);
        Syy = zeros(nF, nTime);
        for tr = trials(:)'
            R = analytic(input.data(refIdx, :, tr));
            Syy = Syy + abs(R).^2;
            if ~estimable
                continue;
            end
            for ch = 1:nChan
                if ch == refIdx; continue; end
                X = analytic(input.data(ch, :, tr));
                Sxy(ch, :, :) = squeeze(Sxy(ch, :, :)) + X .* conj(R);
                Sxx(ch, :, :) = squeeze(Sxx(ch, :, :)) + abs(X).^2;
            end
        end
        if estimable
            for ch = 1:nChan
                if ch == refIdx; continue; end
                num = abs(squeeze(Sxy(ch, :, :))).^2;
                den = squeeze(Sxx(ch, :, :)) .* Syy;
                c = num ./ den;
                c(den == 0) = NaN;
                coh(ch, :, :, b) = c;
            end
        end
        refPower(:, :, b) = Syy / numel(trials);
        TransTools.progressbar(bi / total);
    end
    if isempty(binsToDo)
        TransTools.progressbar(1);
    end
end
