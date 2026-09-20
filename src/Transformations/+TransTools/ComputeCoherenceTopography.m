function [coh, detFreq, refAmp, ampFreqs] = ComputeCoherenceTopography(input, opts)
%COMPUTECOHERENCETOPOGRAPHY  Per-bin scalp coherence to a reference channel at
%   the reference's own tagging frequency, the RIFT / frequency-tagging topography.
%
%   For each bin, the target frequency is OPTS.Frequency (when > 0, a manual
%   override applied to every bin) or found from the reference itself (see
%   TAGSOURCE below). At that frequency, every channel's magnitude-squared
%   coherence to the reference is estimated across the bin's trials, by one of
%   two estimators (see METHOD below).
%
%   INPUT is an EEGLAB-style epoched EEG struct (DataFormat 'EPOCHED', data
%   channels x samples x trials, with EEG.bindesc(b).trials indexing the trial
%   dimension per bin). OPTS fields:
%     RefIndex             row of the reference channel in EEG.data
%     Frequency            fixed frequency (Hz); 0 = find it from the reference
%     TimeStart, TimeStop  analysis window (ms); TimeStop <= TimeStart = whole epoch
%     Method               'frames' or 'window' (default 'window', see below)
%     TagSource            'reference' or 'band' (default 'band', see below)
%     MinFreq, MaxFreq     search band (Hz), used when TagSource is 'band'
%     FreqStep             search-grid step (Hz) for that search (default 0.1)
%     WindowMs, Taper      frame length in ms (default 510) and taper, 'frames' only
%
%   METHOD. 'frames' is the estimator of record (TransTools.FrameCoherence): the
%   coherence is taken in sliding frames and averaged, which is what CoherenceMap
%   draws and what a SpectralMeasure row reports, so this topography and those
%   are on one scale. 'window' is the earlier estimator: ONE Hann-tapered DFT
%   bin per trial over the whole analysis window. It is biased upwards (on ten RIFT
%   recordings it read 2.4 to 2.9 times the frame-averaged value, with a topography
%   scale of 0.6 to 0.9 against a map's 0.13 to 0.3), and is kept for
%   comparison. Stored options from before the method existed have neither field,
%   and so keep the values they were made with.
%
%   TAGSOURCE. 'reference' takes each bin's frequency from the reference's own
%   spectrum, the strongest component at 5 Hz or above over the whole epoch
%   (TransTools.ReferenceSpectrum, the same peak CoherenceMap stores), with no
%   band. 'band' searches the reference's evoked (phase-locked) amplitude within
%   [MinFreq, MaxFreq]: a condition tagged outside the band is then reported at
%   whatever is strongest inside it. On real RIFT data the 30 Hz SSVEP condition
%   was drawn at its 60 Hz harmonic for that reason.
%
%   Returns COH (nChan x nBins; the reference row and combination/difference
%   bins are left NaN), DETFREQ (1 x nBins, the frequency used per bin),
%   REFAMP (numel(AMPFREQS) x nBins, the reference's evoked amplitude over the
%   search grid, NaN columns where the band was not searched) and AMPFREQS
%   (the search-grid frequency vector).
    srate = input.srate;
    [nChan, nSamp, ~] = size(input.data);
    refIdx = opts.RefIndex;

    method    = lower(char(string(TransTools.FieldOr(opts, 'Method', 'window'))));
    tagSource = lower(char(string(TransTools.FieldOr(opts, 'TagSource', 'band'))));
    if ~any(strcmp(method, {'frames', 'window'}))
        throw(MException('Alakazam:ComputeCoherenceTopography', ...
            'I''m afraid the coherence method must be "frames" or "window", not "%s".', method));
    end
    if ~any(strcmp(tagSource, {'reference', 'band'}))
        throw(MException('Alakazam:ComputeCoherenceTopography', ...
            'I''m afraid the tag source must be "reference" or "band", not "%s".', tagSource));
    end

    startMs = TransTools.FieldOr(opts, 'TimeStart', 0);
    stopMs  = TransTools.FieldOr(opts, 'TimeStop', 0);
    [lo, hi] = windowRange(input, startMs, stopMs, nSamp);
    win  = lo:hi;
    nwin = numel(win);
    t     = (0:nwin - 1) / srate;
    taper = hann(nwin);

    frameOpts = struct('WinSize', max(4, round(TransTools.FieldOr(opts, 'WindowMs', 510) / 1000 * srate)), ...
        'Taper', TransTools.FieldOr(opts, 'Taper', 'Hann'), ...
        'Times', TransTools.FieldOr(input, 'times', []), 'TimeStart', NaN, 'TimeStop', NaN);
    if stopMs > startMs
        frameOpts.TimeStart = startMs;
        frameOpts.TimeStop = stopMs;
    end

    fixedF = TransTools.FieldOr(opts, 'Frequency', 0);
    step   = TransTools.FieldOr(opts, 'FreqStep', 0.1);
    if step <= 0; step = 0.1; end
    ampFreqs = (opts.MinFreq:step:opts.MaxFreq).';
    if numel(ampFreqs) < 2; ampFreqs = [opts.MinFreq; opts.MaxFreq]; end

    nBins   = numel(input.bindesc);
    coh     = nan(nChan, nBins);
    detFreq = nan(1, nBins);
    refAmp  = nan(numel(ampFreqs), nBins);

    refPeak = nan(1, nBins);
    if fixedF <= 0 && strcmp(tagSource, 'reference')
        [~, ~, refPeak] = TransTools.ReferenceSpectrum(input, refIdx);
    end

    for b = 1:nBins
        tr = input.bindesc(b).trials;
        if ~isnumeric(tr) || isempty(tr)
            continue;   % combination/difference bin: coherence is not linear across bins
        end

        if fixedF > 0
            fUse = fixedF;
        elseif strcmp(tagSource, 'reference')
            fUse = refPeak(b);
            if ~isfinite(fUse)
                continue;   % the reference has no component to take as the tag
            end
        else
            V    = input.data(:, win, tr);              % nChan x nwin x nTr
            Vref = reshape(V(refIdx, :, :), nwin, []);  % nwin x nTr
            % The evoked (phase-locked) magnitude is |mean over trials of the
            % tapered DFT|. The DFT is linear, so that equals the DFT of the
            % trial MEAN, so the trials are averaged once and each search
            % frequency transforms one column instead of every trial: 161
            % frequencies over about a hundred trials was some 16,000 column
            % transforms per bin, and is now 161. A NaN in any trial still
            % makes the result NaN, as it did through the mean of the transforms.
            evoked = mean(Vref, 2);                    % nwin x 1
            amp = zeros(numel(ampFreqs), 1);
            for k = 1:numel(ampFreqs)
                amp(k) = abs(TransTools.Tdft(evoked, ampFreqs(k), t, taper));
            end
            refAmp(:, b) = amp;
            [~, ix] = max(amp);
            fUse = ampFreqs(ix);
        end
        detFreq(b) = fUse;

        if strcmp(method, 'frames')
            all3 = input.data(:, :, tr);                          % nChan x nSamp x nTr
            R = reshape(all3(refIdx, :, :), nSamp, []);           % nSamp x nTr
            for c = 1:nChan
                if c == refIdx; continue; end        % self-coherence is trivially 1
                coh(c, b) = TransTools.FrameCoherence( ...
                    reshape(all3(c, :, :), nSamp, []), R, srate, fUse, frameOpts);
            end
            continue;
        end

        V    = input.data(:, win, tr);                            % nChan x nwin x nTr
        Vref = reshape(V(refIdx, :, :), nwin, []);                % nwin x nTr
        Xref = TransTools.Tdft(Vref, fUse, t, taper);             % 1 x nTr
        refAuto = sum(abs(Xref).^2);
        if refAuto == 0; continue; end
        for c = 1:nChan
            if c == refIdx; continue; end            % self-coherence is trivially 1
            Xc = TransTools.Tdft(reshape(V(c, :, :), nwin, []), fUse, t, taper);
            den = sum(abs(Xc).^2) * refAuto;
            if den > 0
                coh(c, b) = abs(sum(Xc .* conj(Xref)))^2 / den;
            end
        end
    end
end

% ======================================================================= %
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
