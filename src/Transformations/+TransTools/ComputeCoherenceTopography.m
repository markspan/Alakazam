function [coh, detFreq, refAmp, ampFreqs] = ComputeCoherenceTopography(input, opts)
%COMPUTECOHERENCETOPOGRAPHY  Per-bin scalp coherence to a reference channel at
%   the reference's own peak frequency, the RIFT / frequency-tagging topography.
%
%   For each bin, the target frequency is either OPTS.Frequency (when > 0, a
%   manual override applied to every bin) or auto-detected as the reference
%   channel's strongest evoked (phase-locked) response within
%   [OPTS.MinFreq, OPTS.MaxFreq]. At that frequency, every channel's
%   magnitude-squared coherence to the reference is estimated across the bin's
%   trials using the same formula as SpectralMeasure and ComputeCoherenceMap
%   (the trial-averaged cross-spectrum, normalised by the trial-averaged
%   autospectra):
%       coh = |sum_trials X .* conj(R)|^2 / ( sum_trials|X|^2 .* sum_trials|R|^2 )
%   evaluated by a Hann-tapered single-frequency DFT over an optional
%   steady-state time window.
%
%   INPUT is an EEGLAB-style epoched EEG struct (DataFormat 'EPOCHED', data
%   channels x samples x trials, with EEG.bindesc(b).trials indexing the trial
%   dimension per bin). OPTS fields:
%     RefIndex             row of the reference channel in EEG.data
%     MinFreq, MaxFreq     search band (Hz) for auto frequency detection
%     Frequency            fixed frequency (Hz); 0 = auto-detect per bin
%     TimeStart, TimeStop  analysis window (ms); TimeStop <= TimeStart = whole epoch
%     FreqStep             search-grid step (Hz) for detection (default 0.1)
%
%   Returns COH (nChan x nBins; the reference row and combination/difference
%   bins are left NaN), DETFREQ (1 x nBins, the frequency used per bin),
%   REFAMP (numel(AMPFREQS) x nBins, the reference's evoked amplitude over the
%   search grid, NaN columns where a fixed frequency was used) and AMPFREQS
%   (the search-grid frequency vector).
    srate = input.srate;
    [nChan, nSamp, ~] = size(input.data);
    refIdx = opts.RefIndex;

    [lo, hi] = windowRange(input, getf(opts, 'TimeStart', 0), getf(opts, 'TimeStop', 0), nSamp);
    win  = lo:hi;
    nwin = numel(win);
    t     = (0:nwin - 1) / srate;
    taper = hann(nwin);

    fixedF = getf(opts, 'Frequency', 0);
    step   = getf(opts, 'FreqStep', 0.1);
    if step <= 0; step = 0.1; end
    ampFreqs = (opts.MinFreq:step:opts.MaxFreq).';
    if numel(ampFreqs) < 2; ampFreqs = [opts.MinFreq; opts.MaxFreq]; end

    nBins   = numel(input.bindesc);
    coh     = nan(nChan, nBins);
    detFreq = nan(1, nBins);
    refAmp  = nan(numel(ampFreqs), nBins);

    for b = 1:nBins
        tr = input.bindesc(b).trials;
        if ~isnumeric(tr) || isempty(tr)
            continue;   % combination/difference bin: coherence is not linear across bins
        end
        V    = input.data(:, win, tr);              % nChan x nwin x nTr
        Vref = reshape(V(refIdx, :, :), nwin, []);  % nwin x nTr

        if fixedF > 0
            fUse = fixedF;
        else
            amp = zeros(numel(ampFreqs), 1);
            for k = 1:numel(ampFreqs)
                Xr = tdft(Vref, ampFreqs(k), t, taper);   % 1 x nTr
                amp(k) = abs(mean(Xr));                    % evoked (phase-locked) magnitude
            end
            refAmp(:, b) = amp;
            [~, ix] = max(amp);
            fUse = ampFreqs(ix);
        end
        detFreq(b) = fUse;

        Xref = tdft(Vref, fUse, t, taper);          % 1 x nTr
        refAuto = sum(abs(Xref).^2);
        if refAuto == 0; continue; end
        for c = 1:nChan
            if c == refIdx; continue; end            % self-coherence is trivially 1
            Xc = tdft(reshape(V(c, :, :), nwin, []), fUse, t, taper);
            den = sum(abs(Xc).^2) * refAuto;
            if den > 0
                coh(c, b) = abs(sum(Xc .* conj(Xref)))^2 / den;
            end
        end
    end
end

% ======================================================================= %
function X = tdft(V, f, t, taper)
%TDFT  Hann-tapered single-frequency DFT of V (nwin x nTr) at F (Hz): one
%   complex value per trial, X(n) = sum_t V(:,n) .* taper .* exp(-i2*pi*f*t).
%   The same tapered single-frequency DFT SpectralMeasure.m uses; magnitude-
%   squared coherence is a ratio, so the taper's absolute scale cancels.
    kern = taper(:) .* exp(-1i * 2 * pi * f * t(:));   % nwin x 1
    X = sum(V .* kern, 1);                             % 1 x nTr
end

function [lo, hi] = windowRange(input, startMs, stopMs, nSamp)
%WINDOWRANGE  Sample range for a [startMs, stopMs] window; the whole epoch when
%   the window is unset or degenerate.
    if stopMs <= startMs || ~isfield(input, 'times') || isempty(input.times)
        lo = 1; hi = nSamp; return;
    end
    lo = find(input.times >= startMs, 1, 'first');
    hi = find(input.times <= stopMs,  1, 'last');
    if isempty(lo); lo = 1; end
    if isempty(hi); hi = nSamp; end
    if hi < lo; lo = 1; hi = nSamp; end
end

function v = getf(s, name, default)
    if isstruct(s) && isfield(s, name) && ~isempty(s.(name)); v = s.(name); else; v = default; end
end
