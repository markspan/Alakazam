function [EEG, options] = SpectralMeasure(input, varargin)
%% SpectralMeasure  Quantify frequency-tagging / SSVEP / RIFT responses at
%   named frequencies: power, SNR, inter-trial phase-locking, phase, and
%   (against an optional reference channel) coherence and phase-lag.
%
%   Works on EPOCHED single-trial data (channels x samples x trials, with
%   bins from DefineBins) -- per-trial data is required because the phase-
%   locking and coherence measures pool over trials. For each named
%   frequency row, each selected channel and each bin it reports:
%     * power / amplitude -- of the trial-averaged (evoked) complex, since a
%       tagged response is phase-locked to the flicker.
%     * SNR -- power(f) / mean(power at the neighbouring frequency bins each
%       side, past a guard band): the standard SSVEP signal-to-noise ratio.
%     * itc -- inter-trial coherence / phase-locking value in [0,1],
%       |mean_trials(X/|X|)|; reference-free consistency of the response.
%     * phase -- angle of the evoked complex.
%     * coherence / phaselag -- magnitude-squared coherence and cross phase
%       to the reference channel (e.g. a photodiode), pooled over trials;
%       NaN when no reference is set.
%
%   Frequencies are written as expressions over named fundamentals (see
%   spectralFreqSpecs): a "let f1 = 63" block plus rows like f1, 2*f1 (a
%   harmonic) or f1+f2 / 2*f1-f2 (intermodulation terms). The complex
%   coefficient is computed by a tapered single-frequency DFT evaluated
%   directly at the requested frequency, so harmonic/intermodulation terms
%   off the fs/N grid are still exact. A single Hann taper by default;
%   optional DPSS multitaper (Signal Processing Toolbox) averages over K
%   tapers to cut variance.
%
%   THREE WAYS TO ESTIMATE COHERENCE (options.coherenceMethod). Only the
%   coherence and phase-lag depend on it; power, amplitude, SNR, ITC and phase
%   are single-channel and do not.
%     'frames'     THE ESTIMATOR OF RECORD, and the default for a new run. The
%                  signals are cut into frames (crossf.WinSize samples, slid with
%                  75% overlap), each frame is transformed at the row's EXACT
%                  frequency, the coherence across trials is taken per frame, and
%                  the frames are averaged: TransTools.FrameCoherence. It needs
%                  no EEGLAB, reads a row at the frequency asked for whatever the
%                  band, and agrees with CoherenceMap and newcrossf, so the
%                  number in a report, the map beside it and the topography are
%                  one quantity.
%     'window'     ONE Hann-tapered DFT bin per trial, the whole selected epoch as
%                  a single window, pooled over trials. Cheap, but biased upwards:
%                  far fewer independent samples go into the average, and on ten
%                  RIFT recordings it read 2.4 to 2.9 times the frame-averaged
%                  value. Kept as an option, and named as such in the report.
%     'newcrossf'  EEGLAB's newcrossf (via pop_newcrossf), which slides a shorter
%                  window across each trial and averages over the frames as well as
%                  the trials. The estimator the RIFT paper used; kept as the
%                  reference implementation. Needs EEGLAB, and can only report a
%                  row inside its band (crossf.MinFreq to crossf.MaxFreq): a row
%                  outside it is NaN with a warning, not the value at the band edge.
%   Options saved before the method existed carry only crossf.enabled, and keep
%   the meaning they had (newcrossf when on, 'window' when off), so replaying or
%   recalculating an old node reproduces its numbers. See crossfCoherence for how
%   crossf maps onto the newcrossf call.
%
%   The epoched data passes through unchanged; the result adds
%   EEG.spectralMeasures (1xN cell of scalar structs, mirroring
%   EEG.measurements: .label, .freq, .channels, .refChannel, and
%   .power/.amplitude/.snr/.itc/.phase/.coherence/.phaselag as nChan x nBins
%   matrices), plus EEG.spectrum / EEG.specFreqs (a per-channel evoked
%   amplitude spectrum, for SpectralMeasureView). Persisted, replayable,
%   Apply-to-All-able and grand-average-able like any transform.
%
%   Signature (Alakazam transformation contract):
%     [EEG, options] = SpectralMeasure(input)       % interactive dialog
%     [EEG, options] = SpectralMeasure(input, opts) % replay a stored struct
%
%   See also: SPECTRALFREQSPECS, SPECTRALMEASUREDIALOG, MEASURECHANNELSPECS,
%   EXPORTSPECTRALCSV, SPECTRALMEASUREVIEW, TIMEFREQUENCY.

%% Guard
[opts, interactive] = TransTools.InitGuard(nargin, 'Alakazam:SpectralMeasure', varargin{:});
EEG = input;
% Clear an inherited EEG.ersp: running SpectralMeasure on a TimeFrequency
% result is reachable (both only need EPOCHED data, no reference channel
% required by either), and TimeFrequency's id-or-field check in
% AlakazamPlotter.plotEpoched runs before SpectralMeasure's own id check, so
% a stale non-empty .ersp left in place would route this node to
% TimeFrequencyView instead of SpectralMeasureView. See
% TransTools.ClearForeignResultFields.
EEG = TransTools.ClearForeignResultFields(EEG, 'TimeFrequency');
if ~isfield(input, 'DataFormat') || ~strcmpi(input.DataFormat, 'EPOCHED')
    throw(MException('Alakazam:SpectralMeasure', sprintf([ ...
        'Problem in SpectralMeasure: this needs single-trial epoched data (DataFormat = ' ...
        '"EPOCHED"), and not this dataset (DataFormat = "%s"). Would you run DefineBins with an ' ...
        '''epoch'' statement first? Phase-locking and coherence are computed across ' ...
        'trials, so they need the individual trials.'], input.DataFormat)));
end
if interactive
    stored = TransformSettings.get('SpectralMeasure');
    [rows, fundamentals, refChannel, method, nTapers, snrN, snrGuard, crossf] = ...
        SpectralMeasureDialog(input.chanlocs, stored);
    if isempty(rows)
        % OPTIONS (the second declared output) must still be assigned:
        % onTransformation.m/recalculateTransformNode.m both request both
        % outputs unconditionally, so leaving it unset throws "Output
        % argument not assigned" instead of the clean cancel this means.
        EEG = [];
        options = [];   % cancelled
        return;
    end
    options = struct('rows', {rows}, 'fundamentals', fundamentals, ...
        'refChannel', refChannel, 'method', method, 'tapers', nTapers, ...
        'snrNeighbours', snrN, 'snrGuard', snrGuard, 'crossf', crossf);
    TransformSettings.set('SpectralMeasure', options);
else
    if ~isstruct(opts) || ~isfield(opts, 'rows')
        throw(MException('Alakazam:SpectralMeasure', ...
            ['SpectralMeasure has been asked to replay a previous run, but I''m afraid the stored settings ' ...
             'do not look like ones it produced (there is no .rows field).']));
    end
    options = opts;
end
rows = options.rows;
if isstruct(rows)
    % Apply Template's jsonencode/jsondecode round trip turns a cell array
    % of same-shaped structs back into a struct array, not a cell array --
    % same gotcha, same fix, as Measure.m's own options.windows (see its
    % header comment for the full explanation). rows{w} below needs the
    % cell array back regardless of which replay path produced OPTIONS.
    rows = num2cell(rows);
    % options.rows must carry this NORMALISED form too, not just the local
    % ROWS variable: options becomes this run's own EEG.params (saved
    % verbatim onto the resulting node), so leaving options.rows as the
    % un-normalised struct array would re-save the same contamination onto
    % this node -- resurfacing the identical "Brace indexing is not
    % supported for variables of type struct" crash the next time this
    % specific node is recalculated, even though THIS run computed fine.
    options.rows = rows;
end
fundamentals = TransTools.FieldOr(options, 'fundamentals', '');
refChannel   = TransTools.FieldOr(options, 'refChannel', '');
method       = TransTools.FieldOr(options, 'method', 'Hann');
nTapers      = TransTools.FieldOr(options, 'tapers', 3);
snrN         = TransTools.FieldOr(options, 'snrNeighbours', 10);
snrGuard     = TransTools.FieldOr(options, 'snrGuard', 1);
crossf       = TransTools.FieldOr(options, 'crossf', struct('enabled', false));
crossf.enabled = logical(TransTools.FieldOr(crossf, 'enabled', false));
cohMethod    = coherenceMethodOf(options, crossf);
crossf.Method  = cohMethod;
crossf.enabled = strcmp(cohMethod, 'newcrossf');   % the older flag, kept true to the method

if isempty(rows)
    throw(MException('Alakazam:SpectralMeasure', ...
        'No frequencies have been defined, so there is nothing for SpectralMeasure to do.'));
end

%% Resolve frequencies (Hz) from the expression rows + fundamentals
freqExprs = cellfun(@(r) r.freq, rows, 'UniformOutput', false);
freqHz = spectralFreqSpecs(freqExprs, fundamentals);

%% Fill in the coherence method's own defaults.
%  The frame and newcrossf estimators share a window (in samples) and the time
%  range the frames are averaged over. newcrossf alone also needs its band:
%  MinFreq/MaxFreq default to the rows' own frequency span padded by 8 Hz
%  either side -- enough room for a coherent bandwidth around each named
%  frequency without the user having to work it out by hand; explicit
%  values (as the RIFT template sets, matching the paper's own 52-68 Hz
%  band exactly) always win. A row outside that band cannot be read from
%  newcrossf's image, and is reported as missing (see crossfCoherence), not
%  as the value at the nearest edge.
%
%  What the user chose and what the estimator ran with are kept apart.
%  CHOICE (saved as options.crossf) keeps a band or window left blank as []
%  ("auto" / "whole epoch"): it used to be overwritten with the resolved
%  values, so a recalculated node reopened its dialog with NaN in the window
%  fields (which an edit field refuses), and an automatic band was frozen at
%  its first value, leaving a row moved outside it missing. An automatic band
%  depends only on the rows, which are saved too, so replaying the choice
%  reproduces the numbers. What was actually used is recorded separately, as
%  options.crossfUsed, for the report's method paragraph.
choice = crossf;
for name = {'MinFreq', 'MaxFreq', 'TimeStart', 'TimeStop'}
    choice.(name{1}) = numOr(TransTools.FieldOr(choice, name{1}, []), []);
end
if any(strcmp(cohMethod, {'frames', 'newcrossf'}))
    crossf.WinSize   = TransTools.FieldOr(crossf, 'WinSize', 510);     % samples, matches newcrossf's own 'winsize'
    crossf.PadRatio  = TransTools.FieldOr(crossf, 'PadRatio', 4);
    crossf.TimeStart = numOr(TransTools.FieldOr(crossf, 'TimeStart', NaN), NaN);
    crossf.TimeStop  = numOr(TransTools.FieldOr(crossf, 'TimeStop', NaN), NaN);
end
if strcmp(cohMethod, 'newcrossf')
    if exist('newcrossf', 'file') ~= 2
        throw(MException('Alakazam:SpectralMeasure', sprintf([ ...
            'Problem in SpectralMeasure: "coherence via newcrossf" is turned on, but EEGLAB''s ' ...
            'own newcrossf function isn''t on the path here. Would you initialise EEGLAB first ' ...
            '(eeglab), or choose the frame-averaged coherence, which needs no EEGLAB?'])));
    end
    crossf.TimesOut  = TransTools.FieldOr(crossf, 'TimesOut', 500);
    crossf.MinFreq   = numOr(TransTools.FieldOr(crossf, 'MinFreq', NaN), min(freqHz) - 8);
    crossf.MaxFreq   = numOr(TransTools.FieldOr(crossf, 'MaxFreq', NaN), max(freqHz) + 8);
end
for name = {'WinSize', 'PadRatio', 'TimesOut'}   % no "auto" meaning, so the default is the choice
    if isfield(crossf, name{1})
        choice.(name{1}) = crossf.(name{1});
    end
end
[~, nsamp, ~] = size(EEG.data);
options.coherenceMethod = cohMethod;
options.crossf = choice;
options.crossfUsed = coherenceUsed(crossf, nsamp);

%% Build tapers (nsamp x K)
srate = EEG.srate;
nyq   = srate / 2;
tapers = buildTapers(method, nsamp, nTapers);

allLabels = string({EEG.chanlocs.labels});
refIdx = [];
if ~isempty(strtrim(char(string(refChannel))))
    refIdx = find(strcmpi(allLabels, strtrim(char(string(refChannel)))), 1);
    if isempty(refIdx)
        throw(MException('Alakazam:SpectralMeasure', ...
            'Reference channel "%s" doesn''t appear to be a channel in this dataset.', refChannel));
    end
end

nBins = numel(EEG.bindesc);
t = (0:nsamp - 1) / srate;
df = srate / nsamp;

%% Per-row computation
% crossfCache: keyed by "<channel members>_<bin>", shared across every row
% in this call, since several rows commonly name the same channel (e.g.
% both a 60Hz and a 64Hz row asking about "Oz") -- newcrossf's own
% time-frequency image for a given channel/bin doesn't depend on which
% row's target frequency is being read out of it afterwards, so computing
% it once and letting every row pick its own frequency bin out of the same
% image is both cheaper and exactly how the source analyses this mirrors
% (e.g. the RIFT paper's own script) reuse one coherence image per
% channel/condition across multiple reported frequencies.
crossfCache = containers.Map('KeyType', 'char', 'ValueType', 'any');
measurements = cell(1, numel(rows));
for w = 1:numel(rows)
    measurements{w} = computeRow(EEG, rows{w}, freqHz(w), allLabels, refIdx, ...
        nBins, t, df, nyq, tapers, snrN, snrGuard, crossf, crossfCache);
end
EEG.spectralMeasures = measurements;

%% Evoked amplitude spectrum per channel x bin, for the view
[EEG.spectrum, EEG.specFreqs] = evokedSpectrum(EEG, tapers(:, 1), df);
end

% ======================================================================= %
function m = computeRow(EEG, row, fHz, allLabels, refIdx, nBins, t, df, nyq, tapers, snrN, snrGuard, crossf, crossfCache)
%COMPUTEROW  All metrics for one frequency row, per channel x bin.
    specs = measureChannelSpecs(row.channels, allLabels, row.label);
    nCh = numel(specs);

    fUse = abs(fHz);
    if fUse <= 0 || fUse >= nyq
        throw(MException('Alakazam:SpectralMeasure', sprintf([ ...
            'Frequency "%s" resolves to %.4g Hz, which falls outside the analysable range ' ...
            '(0, %.4g) Hz for this dataset''s sample rate.'], row.label, fHz, nyq)));
    end
    % Neighbour frequencies for SNR: past a guard band, within (0, nyq).
    offs = (snrGuard + (1:snrN)) * df;
    neigh = [fUse - offs, fUse + offs];
    neigh = neigh(neigh > 0 & neigh < nyq);

    power = nan(nCh, nBins); amplitude = nan(nCh, nBins); snr = nan(nCh, nBins);
    itc = nan(nCh, nBins); phase = nan(nCh, nBins);
    coherence = nan(nCh, nBins); phaselag = nan(nCh, nBins);

    % Taper 0 (the first Slepian / the Hann window) is the one with real
    % coherent gain, so it carries the calibrated amplitude; sum() of the
    % higher DPSS tapers is ~0, so they are used only through magnitude/ratio
    % measures (SNR, ITC, coherence) where the taper scale cancels.
    coh1 = 2 / sum(tapers(:, 1));

    for b = 1:nBins
        trials = TransTools.BinTrials(EEG, b);
        if isempty(trials)
            continue;   % combination bins have no trials of their own
        end
        if ~isempty(refIdx)
            Vref = squeeze(EEG.data(refIdx, :, trials));   % nsamp x nT
            if size(Vref, 1) == 1   % single trial -> keep nsamp x 1
                Vref = Vref(:);
            end
            % Only the single-window coherence uses this transform; the frame and
            % newcrossf estimators take the signals themselves.
            if strcmp(crossf.Method, 'window')
                Xref = TransTools.Tdft(Vref, fUse, t, tapers);        % K x nT (raw)
            end
        end
        for c = 1:nCh
            Vc = poolWave(EEG, specs(c).members, trials);  % nsamp x nT
            X = TransTools.Tdft(Vc, fUse, t, tapers);                 % K x nT (raw)

            % ArtefactDetect rejects a trial by blanking its data to NaN in
            % place, not by removing it from bindesc(b).trials -- so a
            % rejected trial still reaches tdft here as a fully-NaN column
            % of X. Every trial-pooling reduction below is 'omitnan' so one
            % (or many) rejected trials drop out instead of poisoning the
            % whole bin's result to NaN alongside dozens of good trials.
            Ek = mean(X, 2, 'omitnan');                    % K x 1 evoked per taper
            amplitude(c, b) = coh1 * abs(Ek(1));           % calibrated (uV) via taper 0
            power(c, b)     = amplitude(c, b)^2;
            phase(c, b)     = angle(Ek(1));
            itc(c, b)       = mean(abs(mean(X ./ max(abs(X), eps), 2, 'omitnan')));

            if ~isempty(neigh)
                Pf = mean(abs(Ek).^2);                     % raw evoked power (ratio use)
                np = zeros(1, numel(neigh));
                for q = 1:numel(neigh)
                    np(q) = mean(abs(mean(TransTools.Tdft(Vc, neigh(q), t, tapers), 2, 'omitnan')).^2);
                end
                snr(c, b) = Pf / mean(np);
            end

            if ~isempty(refIdx)
                switch crossf.Method
                    case 'frames'
                        % The estimator of record: sliding frames, exact frequency,
                        % see TransTools.FrameCoherence.
                        [coherence(c, b), phaselag(c, b)] = TransTools.FrameCoherence( ...
                            Vc, Vref, EEG.srate, fUse, struct('WinSize', crossf.WinSize, ...
                            'Times', TransTools.FieldOr(EEG, 'times', []), 'TimeStart', crossf.TimeStart, ...
                            'TimeStop', crossf.TimeStop));
                    case 'newcrossf'
                        [coherence(c, b), phaselag(c, b)] = crossfCoherence( ...
                            EEG, specs(c).members, refIdx, b, trials, fUse, crossf, crossfCache);
                    otherwise    % 'window': one DFT bin per trial over the whole epoch
                        cross = sum(X(:) .* conj(Xref(:)), 'omitnan');
                        den = sum(abs(X(:)).^2, 'omitnan') * sum(abs(Xref(:)).^2, 'omitnan');
                        if den > 0
                            coherence(c, b) = abs(cross)^2 / den;
                            phaselag(c, b)  = angle(cross);
                        end
                end
            end
        end
    end

    ref = '';
    if ~isempty(refIdx); ref = char(allLabels(refIdx)); end
    m = struct('label', row.label, 'freq', fHz, 'channels', {{specs.label}}, ...
        'refChannel', ref, 'power', power, 'amplitude', amplitude, 'snr', snr, ...
        'itc', itc, 'phase', phase, 'coherence', coherence, 'phaselag', phaselag);
end

function [coh, phlag] = crossfCoherence(EEG, members, refIdx, b, trials, fUse, crossf, cache)
%CROSSFCOHERENCE  Magnitude-squared coherence and phase-lag at frequency
%   FUSE, for one channel spec and one bin, computed via EEGLAB's newcrossf
%   instead of SpectralMeasure's own single-window DFT (see this file's
%   header comment for why the two differ numerically).
%
%   newcrossf produces a whole time x frequency coherence image per
%   channel/bin, shared across every row that asks about this same
%   channel/bin (CACHE, a containers.Map keyed by "<members>_<bin>",
%   created once per SpectralMeasure call and threaded through every
%   computeRow) -- exactly mirroring how the source analyses this mirrors
%   (e.g. the RIFT paper's own script) compute one newcrossf call per
%   channel/condition and read multiple frequencies back out of it.
    key = sprintf('%s_%d', mat2str(members), b);
    if isKey(cache, key)
        img = cache(key);
    else
        Vc   = poolWave(EEG, members, trials);          % nsamp x nTrials
        Vref = poolWave(EEG, refIdx, trials);            % nsamp x nTrials

        % newcrossf wants each signal flattened to 1 x (frames*nepochs),
        % frame-then-epoch -- exactly what reshape(V, 1, []) gives a
        % nsamp x nTrials matrix (column-major: each trial's samples run
        % together before the next trial's), the same layout pop_newcrossf
        % itself builds from EEG.data(chan,:,:) internally.
        xflat = reshape(Vc, 1, []);
        yflat = reshape(Vref, 1, []);
        nsamp = size(Vc, 1);
        tlimits = [EEG.times(1), EEG.times(end)];   % ms

        % newcrossf's 'coh' output is already a REAL magnitude (coherence),
        % not a complex coherency -- phase lives in the separate 'cohangle'
        % output (its own positional output #6; mcoh/cohboot in between are
        % unused here). See this function's header comment for how each is
        % reduced to a scalar below.
        [cohImg, ~, timesOut, freqsOut, ~, angleImg] = newcrossf(xflat, yflat, nsamp, tlimits, ...
            EEG.srate, 0, 'type', 'coher', 'winsize', crossf.WinSize, 'padratio', crossf.PadRatio, ...
            'freqs', [crossf.MinFreq crossf.MaxFreq], 'timesout', crossf.TimesOut, ...
            'plotamp', 'off', 'plotphase', 'off');

        img = struct('coh', cohImg, 'angle', angleImg, 'times', timesOut, 'freqs', freqsOut);
        cache(key) = img;
    end

    if isnan(crossf.TimeStart) || isnan(crossf.TimeStop)
        tIdx = true(size(img.times));
    else
        tIdx = img.times >= crossf.TimeStart & img.times <= crossf.TimeStop;
    end
    if ~any(tIdx)
        coh = NaN; phlag = NaN;
        return;
    end

    % The nearest frequency in the image is only the answer if the image reaches
    % FUSE. A row outside the band (a 30 Hz row against a 52 to 68 Hz band) used
    % to be read at the band edge and reported as if it were the row's own
    % coherence: 0.065 where the true value was about 0.39, on real data. It is
    % now missing, with a warning, once per frequency.
    [gap, fIdx] = min(abs(img.freqs - fUse));
    if gap > median(diff(img.freqs)) / 2 + 1e-9
        warnKey = sprintf('outside_%.10g', fUse);
        if ~isKey(cache, warnKey)
            cache(warnKey) = true; %#ok<NASGU>  cache is a handle: this records that the warning was given
            warning('Alakazam:SpectralMeasure:outsideCrossfBand', ...
                ['SpectralMeasure: %g Hz is outside the newcrossf band (%g to %g Hz), so I cannot ' ...
                 'read its coherence and have left it missing. Would you widen the band, or use ' ...
                 'the frame-averaged coherence, which has no band?'], ...
                fUse, img.freqs(1), img.freqs(end));
        end
        coh = NaN; phlag = NaN;
        return;
    end
    % Magnitude-squared coherence: square EACH time frame's (already real,
    % already trial-pooled) coherence magnitude, THEN average over the
    % chosen time window -- exactly mean(crosscoh(:, window_ix).^2, 2) in
    % the RIFT paper's own script, not "average then square".
    coh = mean(img.coh(fIdx, tIdx) .^ 2, 2);
    % Phase-lag: newcrossf reports this separately per time frame (in
    % radians); a plain mean here is a reasonable single summary of a
    % narrow, already-selected steady-state window, though note this is an
    % addition beyond what the paper itself reports (its own script never
    % uses cohangle).
    phlag = mean(img.angle(fIdx, tIdx), 2);
end

function V = poolWave(EEG, members, trials)
%POOLWAVE  nsamp x nTrials waveform for a channel spec: the electrode itself
%   or the NaN-tolerant mean of a pool's members.
    if isscalar(members)
        V = squeeze(EEG.data(members, :, trials));
    else
        V = squeeze(mean(EEG.data(members, :, trials), 1, 'omitnan'));
    end
    if size(V, 1) == 1   % single trial -> keep nsamp x 1
        V = V(:);
    end
end

function tapers = buildTapers(method, nsamp, K)
%BUILDTAPERS  nsamp x K taper matrix: a single Hann taper, or K DPSS tapers.
    if strcmpi(char(string(method)), 'Multitaper')
        if exist('dpss', 'file') ~= 2
            throw(MException('Alakazam:SpectralMeasure', ...
                ['Multitaper needs the Signal Processing Toolbox (dpss), which doesn''t appear to be ' ...
                 'available here. Would you choose the Hann taper instead?']));
        end
        K = max(1, round(K));
        NW = (K + 1) / 2;                 % time-bandwidth; K = 2*NW-1
        tapers = dpss(nsamp, NW, K);      % nsamp x K
    else
        n = (0:nsamp - 1)';
        tapers = 0.5 - 0.5 * cos(2 * pi * n / (nsamp - 1));   % Hann, nsamp x 1
    end
end

function m = coherenceMethodOf(options, crossf)
%COHERENCEMETHODOF  Which coherence estimator these options ask for:
%   'frames' (sliding frames at the exact frequency, TransTools.FrameCoherence),
%   'window' (one DFT bin per trial over the whole epoch) or 'newcrossf'
%   (EEGLAB's newcrossf, kept as the reference implementation).
%
%   Options saved before the method existed have only the older crossf.enabled
%   flag, and mean what they always meant: newcrossf when it was on, the
%   single window when it was off. That is what keeps a recalculated or replayed
%   node computing the numbers it was made with; the dialog offers 'frames' by
%   default only to a new run.
    m = lower(char(string(TransTools.FieldOr(options, 'coherenceMethod', ''))));
    if isempty(m)
        m = lower(char(string(TransTools.FieldOr(crossf, 'Method', ''))));
    end
    if isempty(m)
        if crossf.enabled
            m = 'newcrossf';
        else
            m = 'window';
        end
    end
    if ~any(strcmp(m, {'frames', 'window', 'newcrossf'}))
        throw(MException('Alakazam:SpectralMeasure', ...
            ['Problem in SpectralMeasure: I''m afraid "%s" is not a coherence method I know. ' ...
             'Please use frames, window or newcrossf.'], m));
    end
end

function used = coherenceUsed(crossf, nsamp)
%COHERENCEUSED  The settings the coherence estimator actually ran with, for the
%   record: the frame length it really used (TransTools.FrameCoherence shortens
%   a window longer than the epoch to the epoch), the averaging range, and
%   newcrossf's band once it has been worked out. The range is [] for the whole
%   epoch, including when only one end was given, since both estimators then
%   average over every frame.
    used = struct('Method', crossf.Method);
    if ~any(strcmp(crossf.Method, {'frames', 'newcrossf'}))
        return;
    end
    used.WinSize = crossf.WinSize;
    if strcmp(crossf.Method, 'frames')
        used.WinSize = min(max(4, round(double(crossf.WinSize))), nsamp);
    end
    used.TimeStart = [];
    used.TimeStop = [];
    if ~isnan(crossf.TimeStart) && ~isnan(crossf.TimeStop)
        used.TimeStart = crossf.TimeStart;
        used.TimeStop = crossf.TimeStop;
    end
    if strcmp(crossf.Method, 'newcrossf')
        used.PadRatio = crossf.PadRatio;
        used.TimesOut = crossf.TimesOut;
        used.MinFreq = crossf.MinFreq;
        used.MaxFreq = crossf.MaxFreq;
    end
end

function v = numOr(value, default)
%NUMOR  VALUE, unless it's empty or NaN, in which case DEFAULT.
    if isempty(value) || (isnumeric(value) && isscalar(value) && isnan(value))
        v = default;
    else
        v = value;
    end
end

function [spectrum, freqs] = evokedSpectrum(EEG, taper, df)
%EVOKEDSPECTRUM  One-sided evoked (trial-averaged) amplitude spectrum per
%   channel x bin, for display only (single Hann taper).
    [nChan, nsamp, ~] = size(EEG.data);
    nF = floor(nsamp / 2) + 1;
    nBins = numel(EEG.bindesc);
    spectrum = zeros(nChan, nF, nBins);
    w = taper(:)';
    g = sum(w);
    for b = 1:nBins
        trials = TransTools.BinTrials(EEG, b);
        if isempty(trials); continue; end
        % 'omitnan': see the matching comment in computeRow -- rejected
        % trials are NaN-blanked in place, not removed from this list.
        evoked = mean(EEG.data(:, :, trials), 3, 'omitnan');   % nChan x nsamp
        F = fft((evoked .* w).', nsamp).';              % nChan x nsamp
        spectrum(:, :, b) = (2 / g) * abs(F(:, 1:nF));
    end
    freqs = (0:nF - 1) * df;
end
