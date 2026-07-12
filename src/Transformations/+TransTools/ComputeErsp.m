function [ersp, freqs] = ComputeErsp(input, opts)
%COMPUTEERSP  nChan x nFreqs x nTime x nBins dB-baseline-corrected power,
%   via complex Morlet wavelet convolution -- the event-related spectral
%   perturbation (ERSP) computation TimeFrequency.m's per-bin heatmaps
%   are built from. Pulled out of TimeFrequency.m into +TransTools (the
%   package this project already uses for shared, independently-testable
%   transformation helpers -- see CreateFilter.m/WindowByName.m) so this
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
%   Every channel and every bin is computed in one pass, with a progress
%   bar (TransTools.progressbar) -- the caller (TimeFrequency.m) then
%   only has to re-slice this already-computed array per channel step,
%   an instant operation, rather than re-running the wavelet convolution
%   live on every channel step.
    times   = input.times;
    nT      = numel(times);
    nChan   = input.nbchan;
    nBins   = numel(input.bindesc);
    srate   = input.srate;
    baseIdx = times >= opts.BaselineStart & times <= opts.BaselineStop;
    if ~any(baseIdx)
        throw(MException('Alakazam:TimeFrequency', sprintf([ ...
            'The baseline window (%.4g to %.4g ms) does not overlap this ' ...
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
    for fi = 1:opts.NumFreqs
        f = freqs(fi);
        sigmaT = cycles(fi) / (2 * pi * f);
        halfLen = ceil(3 * sigmaT * srate);
        tw = (-halfLen:halfLen) / srate;
        wavelet = exp(2i * pi * f * tw) .* exp(-tw.^2 / (2 * sigmaT^2));
        wavelet = wavelet / sqrt(sum(abs(wavelet).^2)); % unit energy
        waveletFFTs{fi} = fft(wavelet, nfft);
        halfLens(fi) = halfLen;
    end

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
    TransTools.progressbar; % init/reset (no output, a self-contained
                             % singleton popup; fractiondone==1 on the
                             % final update below closes it automatically)
    for b = find(~isCombo)
        trials = input.bindesc(b).trials;
        if isempty(trials)
            % No matched events for this (ordinary, non-combo) bin: leave
            % its ersp(:,:,:,b) as NaN (imagesc will just show it blank)
            % rather than erroring. Still has to advance/call progressbar
            % here (not just bump done and rely on the next real update),
            % or a dataset whose LAST processed bin happens to be empty
            % would never send the fractiondone==1 call that closes the
            % popup.
            done = done + nChan;
            TransTools.progressbar(done / total);
            continue;
        end
        for ch = 1:nChan
            chanData = squeeze(input.data(ch, :, trials)); % nT x nTrialsInBin
            if size(chanData, 2) ~= numel(trials)
                chanData = chanData'; % squeeze can transpose a single-trial slice
            end
            power = zeros(opts.NumFreqs, nT);
            for tr = 1:numel(trials)
                trialFFT = fft(chanData(:, tr)', nfft);
                for fi = 1:opts.NumFreqs
                    convResult = ifft(trialFFT .* waveletFFTs{fi});
                    hl = halfLens(fi);
                    analytic = convResult(hl + 1 : hl + nT);
                    power(fi, :) = power(fi, :) + abs(analytic).^2;
                end
            end
            power = power / numel(trials);
            logPower = 10 * log10(power);
            baseline = mean(logPower(:, baseIdx), 2);
            ersp(ch, :, :, b) = logPower - baseline;

            done = done + 1;
            TransTools.progressbar(done / total);
        end
    end

    if sum(~isCombo) == 0
        TransTools.progressbar(1); % nothing above ever reached fractiondone==1
    end

    % Second pass: resolve combo bins in dependency order. A combo bin's
    % ERSP is the coefficient-weighted sum of the referenced bins' own
    % (already dB-baseline-corrected) ERSP -- a legitimate operation in
    % dB/log-power space (dB is already a ratio quantity, so a signed sum
    % across bins is exactly the standard ERSP contrast/difference map --
    % the same reasoning Average.m applies to sum voltage averages, except
    % there it is summing raw voltage, which is linear to begin with). A
    % combo bin may itself reference another combo bin (a
    % difference-of-differences), so this resolves in dependency order,
    % repeating passes until every one is computed or a pass makes no
    % further progress, exactly like Average.m's own combo resolution.
    if any(isCombo)
        pos = containers.Map('KeyType', 'double', 'ValueType', 'double');
        for b = 1:nBins; pos(input.bindesc(b).index) = b; end

        resolved = ~isCombo;
        progress = true;
        while progress && ~all(resolved)
            progress = false;
            for b = find(~resolved)
                combo = input.bindesc(b).combo;
                if ~all(isKey(pos, num2cell([combo.bin])))
                    continue; % references a bin that does not exist; never resolves
                end
                refPos = arrayfun(@(t) pos(t.bin), combo);
                if ~all(resolved(refPos))
                    continue; % a dependency (possibly itself a combo bin) isn't ready yet
                end

                acc = zeros(nChan, opts.NumFreqs, nT);
                for t = 1:numel(combo)
                    acc = acc + combo(t).coeff * ersp(:, :, :, refPos(t));
                end
                ersp(:, :, :, b) = acc;
                resolved(b) = true;
                progress = true;
            end
        end
        % Any bin left unresolved here references one that does not exist,
        % or is part of a cycle; DefineBins already rejects both at parse
        % time, so this only bites a hand-built/edited .bins struct.
        for b = find(~resolved)
            warning('Alakazam:TimeFrequency', ...
                '"%s": could not resolve its combination (unknown or circular bin reference); left as NaN.', ...
                input.bindesc(b).label);
        end
    end
end
