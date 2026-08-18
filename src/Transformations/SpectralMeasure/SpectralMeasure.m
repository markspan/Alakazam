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
if ~isfield(input, 'DataFormat') || ~strcmpi(input.DataFormat, 'EPOCHED')
    throw(MException('Alakazam:SpectralMeasure', sprintf([ ...
        'Problem in SpectralMeasure: needs single-trial epoched data (DataFormat = ' ...
        '"EPOCHED"), not this dataset (DataFormat = "%s"). Run DefineBins with an ' ...
        '''epoch'' statement first -- phase-locking and coherence are computed across ' ...
        'trials, so they need the individual trials.'], input.DataFormat)));
end
if interactive
    stored = TransformSettings.get('SpectralMeasure');
    [rows, fundamentals, refChannel, method, nTapers, snrN, snrGuard] = ...
        SpectralMeasureDialog(input.chanlocs, stored);
    if isempty(rows)
        EEG = [];   % cancelled
        return;
    end
    options = struct('rows', {rows}, 'fundamentals', fundamentals, ...
        'refChannel', refChannel, 'method', method, 'tapers', nTapers, ...
        'snrNeighbours', snrN, 'snrGuard', snrGuard);
    TransformSettings.set('SpectralMeasure', options);
else
    if ~isstruct(opts) || ~isfield(opts, 'rows')
        throw(MException('Alakazam:SpectralMeasure', ...
            ['SpectralMeasure was asked to replay a previous run, but the stored settings ' ...
             'do not look like ones it produced (no .rows field).']));
    end
    options = opts;
end
rows         = options.rows;
fundamentals = TransTools.FieldOr(options, 'fundamentals', '');
refChannel   = TransTools.FieldOr(options, 'refChannel', '');
method       = TransTools.FieldOr(options, 'method', 'Hann');
nTapers      = TransTools.FieldOr(options, 'tapers', 3);
snrN         = TransTools.FieldOr(options, 'snrNeighbours', 10);
snrGuard     = TransTools.FieldOr(options, 'snrGuard', 1);

if isempty(rows)
    throw(MException('Alakazam:SpectralMeasure', ...
        'No frequencies are defined, so there is nothing for SpectralMeasure to do.'));
end

%% Resolve frequencies (Hz) from the expression rows + fundamentals
freqExprs = cellfun(@(r) r.freq, rows, 'UniformOutput', false);
freqHz = spectralFreqSpecs(freqExprs, fundamentals);

%% Build tapers (nsamp x K)
[~, nsamp, ~] = size(EEG.data);
srate = EEG.srate;
nyq   = srate / 2;
tapers = buildTapers(method, nsamp, nTapers);

allLabels = string({EEG.chanlocs.labels});
refIdx = [];
if ~isempty(strtrim(char(string(refChannel))))
    refIdx = find(strcmpi(allLabels, strtrim(char(string(refChannel)))), 1);
    if isempty(refIdx)
        throw(MException('Alakazam:SpectralMeasure', ...
            'Reference channel "%s" is not a channel in this dataset.', refChannel));
    end
end

nBins = numel(EEG.bindesc);
t = (0:nsamp - 1) / srate;
df = srate / nsamp;

%% Per-row computation
measurements = cell(1, numel(rows));
for w = 1:numel(rows)
    measurements{w} = computeRow(EEG, rows{w}, freqHz(w), allLabels, refIdx, ...
        nBins, t, df, nyq, tapers, snrN, snrGuard);
end
EEG.spectralMeasures = measurements;

%% Evoked amplitude spectrum per channel x bin, for the view
[EEG.spectrum, EEG.specFreqs] = evokedSpectrum(EEG, tapers(:, 1), df);
end

% ======================================================================= %
function m = computeRow(EEG, row, fHz, allLabels, refIdx, nBins, t, df, nyq, tapers, snrN, snrGuard)
%COMPUTEROW  All metrics for one frequency row, per channel x bin.
    specs = measureChannelSpecs(row.channels, allLabels, row.label);
    nCh = numel(specs);

    fUse = abs(fHz);
    if fUse <= 0 || fUse >= nyq
        throw(MException('Alakazam:SpectralMeasure', sprintf([ ...
            'Frequency "%s" resolves to %.4g Hz, which is outside the analysable range ' ...
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
        trials = binTrials(EEG, b);
        if isempty(trials)
            continue;   % combination bins have no trials of their own
        end
        if ~isempty(refIdx)
            Vref = squeeze(EEG.data(refIdx, :, trials));   % nsamp x nT
            Xref = tdft(Vref, fUse, t, tapers);            % K x nT (raw)
        end
        for c = 1:nCh
            Vc = poolWave(EEG, specs(c).members, trials);  % nsamp x nT
            X = tdft(Vc, fUse, t, tapers);                 % K x nT (raw)

            Ek = mean(X, 2);                               % K x 1 evoked per taper
            amplitude(c, b) = coh1 * abs(Ek(1));           % calibrated (uV) via taper 0
            power(c, b)     = amplitude(c, b)^2;
            phase(c, b)     = angle(Ek(1));
            itc(c, b)       = mean(abs(mean(X ./ max(abs(X), eps), 2)));

            if ~isempty(neigh)
                Pf = mean(abs(Ek).^2);                     % raw evoked power (ratio use)
                np = zeros(1, numel(neigh));
                for q = 1:numel(neigh)
                    np(q) = mean(abs(mean(tdft(Vc, neigh(q), t, tapers), 2)).^2);
                end
                snr(c, b) = Pf / mean(np);
            end

            if ~isempty(refIdx)
                cross = sum(X(:) .* conj(Xref(:)));
                den = sum(abs(X(:)).^2) * sum(abs(Xref(:)).^2);
                if den > 0
                    coherence(c, b) = abs(cross)^2 / den;
                    phaselag(c, b)  = angle(cross);
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

function X = tdft(V, f, t, tapers)
%TDFT  Raw tapered single-frequency DFT of V (nsamp x nT) at frequency F, one
%   row per taper: X(k, :) = sum_t V .* taper_k .* exp(-i2*pi*f*t). Left
%   unnormalised on purpose -- the caller applies taper 0's coherent gain for
%   the calibrated amplitude, while SNR / ITC / coherence use magnitudes or
%   ratios in which the taper scale cancels (so the zero-sum higher DPSS
%   tapers are safe).
    e = exp(-1i * 2 * pi * f * t(:));    % nsamp x 1
    X = (tapers .* e).' * V;             % K x nT
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

function idx = binTrials(EEG, b)
%BINTRIALS  Trial indices for bin b (mirrors Average.binTrials).
    idx = [];
    if isfield(EEG.bindesc, 'trials') && ~isempty(EEG.bindesc(b).trials)
        idx = EEG.bindesc(b).trials;
    elseif isfield(EEG, 'epoch') && ~isempty(EEG.epoch) && isfield(EEG.epoch, 'bini')
        binIndex = EEG.bindesc(b).index;
        idx = find(arrayfun(@(e) any(e.bini == binIndex), EEG.epoch));
    end
end

function tapers = buildTapers(method, nsamp, K)
%BUILDTAPERS  nsamp x K taper matrix: a single Hann taper, or K DPSS tapers.
    if strcmpi(char(string(method)), 'Multitaper')
        if exist('dpss', 'file') ~= 2
            throw(MException('Alakazam:SpectralMeasure', ...
                ['Multitaper needs the Signal Processing Toolbox (dpss), which is not ' ...
                 'available. Choose the Hann taper instead.']));
        end
        K = max(1, round(K));
        NW = (K + 1) / 2;                 % time-bandwidth; K = 2*NW-1
        tapers = dpss(nsamp, NW, K);      % nsamp x K
    else
        n = (0:nsamp - 1)';
        tapers = 0.5 - 0.5 * cos(2 * pi * n / (nsamp - 1));   % Hann, nsamp x 1
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
        trials = binTrials(EEG, b);
        if isempty(trials); continue; end
        evoked = mean(EEG.data(:, :, trials), 3);       % nChan x nsamp
        F = fft((evoked .* w).', nsamp).';              % nChan x nsamp
        spectrum(:, :, b) = (2 / g) * abs(F(:, 1:nF));
    end
    freqs = (0:nF - 1) * df;
end
