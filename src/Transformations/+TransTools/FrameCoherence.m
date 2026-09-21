function [coh, lag, nFrames] = FrameCoherence(X, R, srate, freqs, opts)
%FRAMECOHERENCE  Magnitude-squared coherence to a reference at exact
%   frequencies, averaged over sliding frames: the estimator of record for the
%   coherence Alakazam reports.
%
%   [COH, LAG, NFRAMES] = TransTools.FrameCoherence(X, R, SRATE, FREQS, OPTS)
%   takes X and R (nsamp x nTrials: one channel and the reference, for the
%   trials of one bin), the sampling rate, and a vector of frequencies in Hz,
%   and returns COH and LAG (1 x numel(FREQS)) and the number of frames used.
%
%   WHAT IT COMPUTES. The signals are cut into frames of OPTS.WinSize samples
%   slid with 75% overlap (TransTools.FrameStarts), each frame tapered and
%   transformed at the requested frequency. In each frame the coherence is taken
%   across trials,
%
%       coh_k = |sum_trials X_k conj(R_k)|^2 / ( sum_trials |X_k|^2  sum_trials |R_k|^2 )
%
%   and the result is the mean of coh_k over the frames whose centre lies in the
%   analysis window (the same "square each frame, then average" as the RIFT
%   paper's own script). LAG is the circular mean of the cross-spectrum's phase
%   over the same frames.
%
%   WHY THIS ONE. Measured on ten RIFT recordings (60 cells inside newcrossf's
%   band, Oz), this agrees with EEGLAB's newcrossf, which the paper used, to a
%   mean absolute difference of 0.001 in coherence (at most 0.004, r = 1.000), and
%   with CoherenceMap's STFT to 0.003, the difference there being that the map can
%   only be read on its FFT grid. The numbers a SpectralMeasure row reports, a
%   CoherenceMap draws and a CoherenceTopography shows are therefore one
%   quantity. Group means on the tag were 0.283 and 0.238 against the paper's
%   0.280 and 0.241. The single-window DFT it replaces as the default reads 2.4 to
%   2.9 times higher on the same data: one coefficient per trial over the whole
%   epoch has far fewer independent samples behind it, and coherence is biased
%   upwards by exactly that.
%
%   WHY EXACT FREQUENCIES. CoherenceMap reads an FFT grid, so a 64 Hz row could
%   only be read at 64.22 Hz. A direct transform at the requested frequency
%   has no grid, and zero-padding (which only refines the grid) does not enter.
%
%   A trial with a NaN in a frame (a rejected epoch is blanked to NaN) is left
%   out of that frame's sums, for X and R alike. A frame with fewer than two
%   usable trials has no coherence (with one trial it is 1 by construction) and
%   is left out of the mean; the result is NaN if no frame has one.
%
%   OPTS (all optional):
%     WinSize     frame length in samples                        (default 510)
%     Taper       'Hann' or 'Boxcar'                             (default 'Hann')
%     Times       1 x nsamp time axis, ms, for TimeStart/TimeStop
%     TimeStart, TimeStop   keep frames centred in [TimeStart, TimeStop] ms
%                 (NaN or empty = every frame)
%
%   See also TRANSTOOLS.FRAMESTARTS, TRANSTOOLS.COMPUTECOHERENCEMAP,
%   SPECTRALMEASURE, TRANSTOOLS.COMPUTECOHERENCETOPOGRAPHY.
    if nargin < 5 || isempty(opts)
        opts = struct();
    end
    nSamp = size(X, 1);
    freqs = double(freqs(:)).';
    nF = numel(freqs);
    win = min(max(4, round(double(TransTools.FieldOr(opts, 'WinSize', 510)))), nSamp);
    [starts, centres] = TransTools.FrameStarts(nSamp, win);

    times = TransTools.FieldOr(opts, 'Times', []);
    t0 = TransTools.FieldOr(opts, 'TimeStart', NaN);
    t1 = TransTools.FieldOr(opts, 'TimeStop', NaN);
    if ~isempty(times) && ~isempty(t0) && ~isempty(t1) && ~isnan(t0) && ~isnan(t1)
        centreMs = double(times(min(centres, numel(times))));
        keep = centreMs >= t0 & centreMs <= t1;
        starts = starts(keep);
    end
    nFrames = numel(starts);
    coh = nan(1, nF);
    lag = nan(1, nF);
    if nFrames == 0
        return;
    end

    taper = frameTaper(TransTools.FieldOr(opts, 'Taper', 'Hann'), win).';      % win x 1
    kernel = exp(-2i * pi * ((0:win - 1).' * freqs) / srate) .* taper;         % win x nF
    index = starts(:) + (0:win - 1);                                           % nFrames x win

    nTrials = size(X, 2);
    Cx = zeros(nFrames, nF, nTrials);
    Cr = zeros(nFrames, nF, nTrials);
    for tr = 1:nTrials
        % Rows, as ComputeCoherenceMap's own: when only one frame fits, INDEX is
        % a row vector, and a vector indexed by a vector keeps its own shape, so
        % a column here gave a win x 1 segment and the product below failed.
        % That was every epoch less than a quarter window longer than the
        % window, including any shorter than it (510 samples by default).
        x = double(X(:, tr)).';
        r = double(R(:, tr)).';
        Cx(:, :, tr) = x(index) * kernel;
        Cr(:, :, tr) = r(index) * kernel;
    end

    usable = ~isnan(Cx) & ~isnan(Cr);
    Cx(~usable) = 0;
    Cr(~usable) = 0;
    Sxy = sum(Cx .* conj(Cr), 3);                       % nFrames x nF
    Sxx = sum(abs(Cx) .^ 2, 3);
    Syy = sum(abs(Cr) .^ 2, 3);
    frameCoh = abs(Sxy) .^ 2 ./ (Sxx .* Syy);
    frameCoh(sum(usable, 3) < 2 | Sxx .* Syy == 0) = NaN;

    coh = mean(frameCoh, 1, 'omitnan');
    coh(all(isnan(frameCoh), 1)) = NaN;
    unit = Sxy ./ abs(Sxy);
    unit(isnan(frameCoh)) = NaN;
    lag = angle(mean(unit, 1, 'omitnan'));
    lag(all(isnan(frameCoh), 1)) = NaN;
end

function w = frameTaper(kind, n)
%FRAMETAPER  Hann or boxcar, as ComputeCoherenceMap's STFT window.
    switch lower(char(string(kind)))
        case 'hann'
            w = 0.5 - 0.5 * cos(2 * pi * (0:n - 1) / (n - 1));
        case {'boxcar', 'rectangular'}
            w = ones(1, n);
        otherwise
            throw(MException('Alakazam:FrameCoherence', ...
                'I''m afraid "%s" is not a window taper I know. Please use Hann or Boxcar.', char(string(kind))));
    end
end
