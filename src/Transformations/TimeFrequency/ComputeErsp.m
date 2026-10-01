function [ersp, freqs, info] = ComputeErsp(input, opts)
%COMPUTEERSP  nChan x nFreqs x nTime x nBins dB-baseline-corrected power,
%   via complex Morlet wavelet convolution -- the event-related spectral
%   perturbation (ERSP) computation TimeFrequency.m's per-bin heatmaps
%   are built from. Pulled out of TimeFrequency.m into +TransTools (the
%   package this project already uses for shared, independently-testable
%   transformation helpers -- see WindowByName.m) so this
%   can be called and verified directly, without going through
%   TimeFrequency.m's own blocking TransformOptionsDialog options dialog.
%
%   Algorithm: variable wavelet cycles growing linearly with frequency
%   (the same time/frequency-resolution tradeoff EEGLAB's newtimef uses
%   -- few cycles at low frequencies for temporal precision, more cycles
%   at high frequencies for spectral precision), single-trial power
%   averaged across trials per bin, then baseline-corrected in dB
%   relative to a user-set pre-stimulus window -- the standard EEG
%   time-frequency (ERSP) convention.
%
%   INPUT is an EEGLAB-style epoched EEG struct (DataFormat = 'EPOCHED',
%   EEG.bindesc(b).trials indexing EEG.data's 3rd dimension per bin --
%   see DefineBins.m). OPTS is a struct with fields MinFreq, MaxFreq,
%   NumFreqs (Hz range and count, log-spaced), MinCycles, MaxCycles
%   (wavelet cycles at the frequency extremes, linearly interpolated in
%   between), BaselineStart, BaselineStop (ms, for the dB correction).
%
%   THE EDGES ARE LEFT OUT, as FieldTrip leaves them out. A sample closer
%   to either end of the epoch than half its frequency's wavelet has part of
%   the wavelet over no data, so its power is too low, and by more the lower
%   the frequency. Those samples are NaN (drawn blank), and so is a whole
%   frequency whose baseline window lies entirely in that zone, since no
%   baseline can be taken for it. Computed over them, as this did until
%   30 September, the pre-stimulus baseline of an ordinary -200 to 800 ms
%   epoch was too low at every frequency below about 20 Hz, and stationary
%   noise came out as +1.3 dB of "event-related" power at 4 to 6 Hz. The
%   remedy for a blank low frequency is a longer epoch, which is the usual
%   advice for time-frequency analysis in any toolkit.
%
%   THE BASELINE IS THE dB OF THE MEAN POWER, 10*log10(P ./ mean(P_base)),
%   as in EEGLAB's newtimef and FieldTrip's ft_freqbaseline('db'). It used
%   to be the mean of the dB values, which is lower (Jensen's inequality)
%   by an amount that grows with how much the power varies over the
%   baseline, and so disagreed with both.
%
%   INFO describes what could be computed: .halfWaveletMs (1 x nFreqs), how
%   far from each end of the epoch a frequency's first and last computed
%   sample lie, and .noBaseline (1 x nFreqs logical), the frequencies left
%   blank for want of a baseline sample clear of the edge.
%
%   Every channel and every bin is computed in one pass, reporting its
%   progress to the app's busy indicator (TransTools.BusyGate) -- the
%   caller (TimeFrequency.m) then
%   only has to re-slice this already-computed array per channel step,
%   an instant operation, rather than re-running the wavelet convolution
%   live on every channel step.
%
%   TOOLBOX OR OWN CODE. EEGLAB's newtimef and FieldTrip's ft_freqanalysis
%   ('wavelet') compute the same ERSP, and the conventions here are theirs:
%   sigma_t = cycles / (2 pi f), the wavelet cut at three sigma, the edges
%   left blank, the baseline the dB of the mean power. The convolution stays
%   Alakazam's because neither fits the job as it stands: newtimef takes one
%   channel at a time, and ft_freqanalysis rounds each log-spaced frequency to
%   the epoch's own frequency grid, while this pass computes every channel and
%   bin at once, leaves rejected trials out per channel, builds a combination
%   bin from its bins' maps and records which frequencies had no baseline.
%   FieldTripReferenceTest holds it to ft_freqanalysis and ft_freqbaseline, to
%   0.027 dB.
    times   = input.times;
    nT      = numel(times);
    nChan   = input.nbchan;
    nBins   = numel(input.bindesc);
    srate   = input.srate;
    % The samples INSIDE the baseline window, as ft_freqbaseline and
    % newtimef take them; FieldTrip's nearest-sample rule (Baseline,
    % TransTools.WindowSamples) is for a latency range, and is not what its
    % time-frequency baseline does.
    baseIdx = times >= opts.BaselineStart & times <= opts.BaselineStop;
    if ~any(baseIdx)
        throw(MException('Alakazam:TimeFrequency', sprintf([ ...
            'I''m afraid the baseline window (%.4g to %.4g ms) does not overlap this ' ...
            'epoch''s own time range (%.4g to %.4g ms).'], ...
            opts.BaselineStart, opts.BaselineStop, times(1), times(end))));
    end

    freqs  = logspace(log10(opts.MinFreq), log10(opts.MaxFreq), opts.NumFreqs);
    cycles = linspace(opts.MinCycles, opts.MaxCycles, opts.NumFreqs);

    % One shared nfft for every frequency (sized for the widest wavelet,
    % at the lowest frequency): lets each trial's FFT be computed once and
    % reused across every frequency's wavelet multiplication, instead of
    % recomputing it per (frequency, trial) pair.
    sigmaTMin     = opts.MinCycles / (2 * pi * opts.MinFreq);
    maxWaveletLen = 2 * ceil(3 * sigmaTMin * srate) + 1;
    nfft          = 2 ^ nextpow2(nT + maxWaveletLen - 1);

    waveletFFTs = cell(1, opts.NumFreqs);
    halfLens    = zeros(1, opts.NumFreqs);
    valid       = false(opts.NumFreqs, nT);   % clear of the edges, per frequency
    for fi = 1:opts.NumFreqs
        f = freqs(fi);
        sigmaT = cycles(fi) / (2 * pi * f);
        halfLen = ceil(3 * sigmaT * srate);
        tw = (-halfLen:halfLen) / srate;
        wavelet = exp(2i * pi * f * tw) .* exp(-tw.^2 / (2 * sigmaT^2));
        wavelet = wavelet / sqrt(sum(abs(wavelet).^2)); % unit energy
        waveletFFTs{fi} = fft(wavelet, nfft);
        halfLens(fi) = halfLen;
        valid(fi, halfLen + 1 : nT - halfLen) = true;
    end
    baseValid = valid & baseIdx(:)';
    noBaseline = ~any(baseValid, 2)';
    info = struct('halfWaveletMs', halfLens / srate * 1000, 'noBaseline', noBaseline);

    % Combination (difference) bins defined in DefineBins ("bin N = bin A
    % - bin B") have no trials of their own (DefineBins.m leaves
    % bindesc(b).trials = [] for them) -- their ERSP cannot be computed by
    % wavelet convolution at all, only derived from the bins they
    % reference, in a second pass below (mirrors Average.m's own
    % dependency-resolution scheme for the exact same kind of bin).
    isCombo = false(1, nBins);
    if isfield(input.bindesc, 'combo')
        isCombo = ~cellfun(@isempty, {input.bindesc.combo});
    end

    ersp = nan(nChan, opts.NumFreqs, nT, nBins);
    total = max(1, sum(~isCombo) * nChan); % avoid a 0/0 if every bin is a combo bin
    done = 0;
    TransTools.BusyGate('progress', 0);
    for b = find(~isCombo)
        trials = input.bindesc(b).trials;
        if isempty(trials)
            % No matched events for this (ordinary, non-combo) bin: leave
            % its ersp(:,:,:,b) as NaN (imagesc will just show it blank)
            % rather than erroring. Its channels count as done, so the bar
            % stays in step with the work that is left.
            done = done + nChan;
            TransTools.BusyGate('progress', done / total);
            continue;
        end
        for ch = 1:nChan
            chanData = squeeze(input.data(ch, :, trials)); % nT x nTrialsInBin
            if size(chanData, 2) ~= numel(trials)
                chanData = chanData'; % squeeze can transpose a single-trial slice
            end
            power = zeros(opts.NumFreqs, nT);
            % REJECTED TRIALS ARE LEFT OUT, per channel. Rejection writes NaN
            % and leaves the trial in its bin (ArtefactDetect, ManualReject),
            % and one NaN sample turns a trial's whole convolution into NaN:
            % summed in, it made every map of that channel and bin NaN, so
            % TimeFrequency after artefact rejection drew nothing at all.
            kept = find(all(isfinite(chanData), 1));
            for tr = kept
                trialFFT = fft(chanData(:, tr)', nfft);
                for fi = 1:opts.NumFreqs
                    convResult = ifft(trialFFT .* waveletFFTs{fi});
                    hl = halfLens(fi);
                    analytic = convResult(hl + 1 : hl + nT);
                    power(fi, :) = power(fi, :) + abs(analytic).^2;
                end
            end
            if isempty(kept)
                done = done + 1;                 % every trial rejected: stays NaN
                TransTools.BusyGate('progress', done / total);
                continue;
            end
            power = power / numel(kept);
            power(~valid) = NaN;   % within half a wavelet of an edge: see the header
            baseline = nan(opts.NumFreqs, 1);
            for fi = find(~noBaseline)
                baseline(fi) = mean(power(fi, baseValid(fi, :)));
            end
            ersp(ch, :, :, b) = 10 * log10(power ./ baseline);

            done = done + 1;
            TransTools.BusyGate('progress', done / total);
        end
    end
    % Done with the slow pass, even when it had no bins to compute (every bin
    % a combination bin): the indicator goes back to its spinner.
    TransTools.BusyGate('progress', 1);

    % Second pass: combo bins. A combo bin's ERSP is the coefficient-weighted
    % sum of the referenced bins' own (already dB-baseline-corrected) ERSP,
    % a legitimate operation in dB/log-power space: dB is already a ratio
    % quantity, so a signed sum across bins is exactly the standard ERSP
    % contrast/difference map (Average.m sums voltage averages on the same
    % reasoning, where the quantity is linear to begin with). A combo bin may
    % itself reference another (a difference-of-differences), so they are
    % computed in the dependency order TransTools.ComboOrder works out, the
    % one resolver Average.m and Unfold.fitBins share with this.
    [steps, unresolved] = TransTools.ComboOrder(input.bindesc);
    for s = steps
        acc = zeros(nChan, opts.NumFreqs, nT);
        for t = 1:numel(s.parts)
            acc = acc + s.coeffs(t) * ersp(:, :, :, s.parts(t));
        end
        ersp(:, :, :, s.target) = acc;
    end
    % Any bin left unresolved here references one that does not exist, or is
    % part of a cycle; DefineBins already rejects both at parse time, so this
    % only bites a hand-built/edited .bins struct.
    for b = unresolved
        warning('Alakazam:TimeFrequency', ...
            '"%s": could not resolve its combination (unknown or circular bin reference); left as NaN.', ...
            input.bindesc(b).label);
    end
end
