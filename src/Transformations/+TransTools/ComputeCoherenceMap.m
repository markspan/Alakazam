function [coh, freqs, cohTimes] = ComputeCoherenceMap(input, opts)
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
%     Method     'Wavelet' or 'STFT'
%     RefIndex   row of the reference channel in EEG.data
%     MinFreq, MaxFreq, NumFreqs   frequency range (Hz)
%     MinCycles, MaxCycles         Morlet cycles at the extremes (Wavelet)
%     WindowMs, PadRatio           STFT window (ms) and zero-padding ratio
%
%   Combination (difference) bins are left NaN: coherence is a normalised
%   ratio, not linear across bins, so (unlike ComputeErsp's ERSP) it cannot be
%   derived from the referenced bins. The reference channel's own row is left
%   NaN (self-coherence is trivially 1). COHTIMES is EEG.times for Wavelet, or
%   the STFT frame centres for STFT; FREQS is the analysed frequency vector.
    if strcmpi(opts.Method, 'STFT')
        [coh, freqs, cohTimes] = stftCoherence(input, opts);
    else
        [coh, freqs, cohTimes] = waveletCoherence(input, opts);
    end
end

% ======================================================================= %
function [coh, freqs, cohTimes] = waveletCoherence(input, opts)
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
    coh = coherenceOverBins(input, nChan, nF, nT, nBins, refIdx, analytic);
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
function [coh, freqs, cohTimes] = stftCoherence(input, opts)
%STFTCOHERENCE  Fixed-window short-time Fourier coherence (the RIFT paper's
%   newcrossf approach): a Hann-tapered window slid across the epoch,
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
    taper = hannWindow(win);

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
    coh = coherenceOverBins(input, nChan, nF, nFrame, nBins, refIdx, analytic);
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

function w = hannWindow(n)
    w = 0.5 - 0.5 * cos(2 * pi * (0:n - 1) / (n - 1));
end

% ======================================================================= %
function coh = coherenceOverBins(input, nChan, nF, nTime, nBins, refIdx, analytic)
%COHERENCEOVERBINS  Accumulate trial-wise cross/auto spectra per bin and form
%   the magnitude-squared coherence to the reference. ANALYTIC(sig) returns an
%   nF x nTime complex time-frequency matrix for one trial's signal.
    coh = nan(nChan, nF, nTime, nBins);
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
        Sxy = zeros(nChan, nF, nTime);
        Sxx = zeros(nChan, nF, nTime);
        Syy = zeros(nF, nTime);
        for tr = trials(:)'
            R = analytic(input.data(refIdx, :, tr));
            Syy = Syy + abs(R).^2;
            for ch = 1:nChan
                if ch == refIdx; continue; end
                X = analytic(input.data(ch, :, tr));
                Sxy(ch, :, :) = squeeze(Sxy(ch, :, :)) + X .* conj(R);
                Sxx(ch, :, :) = squeeze(Sxx(ch, :, :)) + abs(X).^2;
            end
        end
        for ch = 1:nChan
            if ch == refIdx; continue; end
            num = abs(squeeze(Sxy(ch, :, :))).^2;
            den = squeeze(Sxx(ch, :, :)) .* Syy;
            c = num ./ den;
            c(den == 0) = NaN;
            coh(ch, :, :, b) = c;
        end
        TransTools.progressbar(bi / total);
    end
    if isempty(binsToDo)
        TransTools.progressbar(1);
    end
end
