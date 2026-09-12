function [EEG, options] = CrossCorrelation(input, varargin)
%% CrossCorrelation  Averaged cross-correlation of each channel to a reference.
%
%   For every selected channel, the Pearson correlation with the reference
%   channel at each lag, computed per trial and then averaged over the bin's
%   trials. The result is a lag function per channel per bin, drawn by
%   CrossCorrelationView, plus the peak correlation and the lag it occurs at.
%
%   SIGN CONVENTION, stated because it is the classic way to misread a
%   cross-correlation: a POSITIVE lag means the channel FOLLOWS the
%   reference. r at +20 ms is the correlation between the reference now and
%   the channel 20 ms later, so a peak at +20 ms says the channel lags the
%   reference by 20 ms.
%
%   FOUR IMPROVEMENTS ON THE CLASSIC FORMULATION. BrainVision Analyzer's
%   Averaged Cross Correlation computes, per segment,
%
%       CrCorr(j) = SUM_i (c1(i) - Avg(c1)) (c2(i+j) - Avg(c2))*
%                   / (StdDev(c1) * StdDev(c2))
%
%   and averages that over segments. Four things here differ, each for a
%   reason:
%
%   1. NORMALISED PER LAG, ON THE OVERLAP. Avg and StdDev above are taken
%      over the WHOLE segment regardless of the lag, but at lag j only
%      n-|j| sample pairs actually overlap. Normalising a short overlap by
%      whole-segment statistics makes the value at large |lag| drift for a
%      reason that has nothing to do with the data -- it is not a
%      correlation coefficient any more, and it is not bounded by 1. Here
%      each lag is normalised by the mean and SD of exactly the samples
%      that contributed to it, so every value is a true Pearson r in
%      [-1, 1] and lags are comparable with each other.
%
%   2. AVERAGED IN FISHER-Z, NOT IN r. r is bounded and its sampling
%      distribution is skewed, so the arithmetic mean of r across trials is
%      biased toward zero -- increasingly so the larger the true
%      correlation. Averaging z = atanh(r) and transforming back with tanh
%      is the standard correction, and it also gives a usable standard
%      error (z is roughly normal with variance 1/(n-3)), which is what
%      lets the view draw a band instead of a bare line.
%
%   3. REJECTED SAMPLES ARE EXCLUDED PAIRWISE, PER LAG, and that falls out
%      of how this is computed rather than being bolted on. Alakazam marks
%      rejection as NaN; every sum below is formed by correlating the
%      signals with their own finite-value MASKS, so each lag's sums run
%      over exactly the sample pairs where both channels are finite, and
%      the count is known rather than assumed. A lag left with too few
%      pairs is returned as NaN instead of as a confident number from
%      almost no data.
%
%   4. COMPUTED BY FFT, ALL LAGS AT ONCE. The six per-lag quantities needed
%      (sum xy, sum x, sum y, sum x^2, sum y^2, and the pair count) are
%      each a cross-correlation, so each is one FFT pair rather than a loop
%      over lags. That is what makes per-lag normalisation and pairwise NaN
%      handling affordable at all -- the naive triple loop over channels,
%      trials and lags is the reason implementations reach for
%      whole-segment statistics in the first place. Implemented with fft
%      directly rather than xcorr, so this needs no Signal Processing
%      Toolbox.
%
%   Signature (Alakazam transformation contract):
%     [EEG, options] = CrossCorrelation(input)        % interactive dialog
%     [EEG, options] = CrossCorrelation(input, opts)  % replay stored options
[opts, interactive] = TransTools.InitGuard(nargin, 'Alakazam:CrossCorrelation', varargin{:});

if ~isfield(input, 'data') || isempty(input.data)
    throw(MException('Alakazam:CrossCorrelation', ...
        'Problem in CrossCorrelation: I''m afraid this dataset has no data.'));
end
if ~isfield(input, 'srate') || isempty(input.srate) || input.srate <= 0
    throw(MException('Alakazam:CrossCorrelation', ...
        'Problem in CrossCorrelation: this dataset has no usable sampling rate.'));
end

labels = channelLabels(input);
if interactive
    stored = TransformSettings.get('CrossCorrelation');
    if isempty(stored) || ~isstruct(stored)
        stored = struct('RefChannel', '', 'Channels', {{}}, 'MaxLagMs', 200, ...
            'MinPairs', 20, 'Start', 0, 'Stop', 0);
    end
    refList = TransTools.ReferenceChoices(labels, TransTools.FieldOr(stored, 'RefChannel', ''));
    options = TransformOptionsDialog( ...
        'Description', ['Pearson correlation of each channel to a reference at every lag, ' ...
            'computed per trial and averaged in Fisher-z across the bin''s trials. A ' ...
            'positive lag means the channel FOLLOWS the reference. Leave the channel list ' ...
            'empty for all channels, and the window 0 to 0 for the whole epoch.'], ...
        'title', 'Cross Correlation options', ...
        'separator', 'Channels:', ...
        {'Reference channel'; 'RefChannel'}, refList, ...
        {'Channels (empty = all)'; 'Channels'}, multiSelectField(labels, TransTools.FieldOr(stored, 'Channels', {})), ...
        'separator', 'Lags:', ...
        {'Maximum lag (ms)'; 'MaxLagMs'}, TransTools.FieldOr(stored, 'MaxLagMs', 200), ...
        {'Minimum sample pairs per lag'; 'MinPairs'}, TransTools.FieldOr(stored, 'MinPairs', 20), ...
        'separator', 'Window (ms, 0 to 0 = whole epoch):', ...
        {'Start'; 'Start'}, TransTools.FieldOr(stored, 'Start', 0), ...
        {'Stop'; 'Stop'}, TransTools.FieldOr(stored, 'Stop', 0));
    if isempty(options)
        EEG = [];       % cancelled -- no node, no compute
        options = [];   % the contract is two outputs; both must be assigned
        return;
    end
    TransformSettings.set('CrossCorrelation', options);
else
    options = opts;
end

refIdx = find(strcmpi(labels, strtrim(char(string(TransTools.FieldOr(options, 'RefChannel', ''))))), 1);
if isempty(refIdx)
    throw(MException('Alakazam:CrossCorrelation', ...
        'Problem in CrossCorrelation: I''m afraid reference channel "%s" is not a channel in this dataset.', ...
        char(string(TransTools.FieldOr(options, 'RefChannel', '')))));
end

chanIdx = TransTools.LabelsToIdx(input, TransTools.FieldOr(options, 'Channels', {}));
if isempty(chanIdx)
    chanIdx = 1:size(input.data, 1);
end

[lo, hi] = windowRange(input, TransTools.FieldOr(options, 'Start', 0), ...
    TransTools.FieldOr(options, 'Stop', 0), size(input.data, 2));
nSamp = hi - lo + 1;

maxLagMs = TransTools.FieldOr(options, 'MaxLagMs', 200);
maxLag = min(nSamp - 1, max(1, round(maxLagMs * input.srate / 1000)));
minPairs = max(3, round(TransTools.FieldOr(options, 'MinPairs', 20)));

lags = -maxLag:maxLag;
lagMs = lags / input.srate * 1000;
nLags = numel(lags);

[binTrialSets, binLabels] = binning(input);
nBins = numel(binTrialSets);
nChan = numel(chanIdx);

rMean = nan(nChan, nLags, nBins);
zSE   = nan(nChan, nLags, nBins);
nUsed = zeros(1, nBins);

for b = 1:nBins
    trials = binTrialSets{b};
    if isempty(trials)
        continue;
    end
    nUsed(b) = numel(trials);
    zAll = nan(nChan, nLags, numel(trials));
    for k = 1:numel(trials)
        t = trials(k);
        x = double(input.data(refIdx, lo:hi, t)).';
        for ci = 1:nChan
            y = double(input.data(chanIdx(ci), lo:hi, t)).';
            r = laggedPearson(x, y, maxLag, minPairs);
            zAll(ci, :, k) = atanh(clampR(r));
        end
    end
    zBar = mean(zAll, 3, 'omitnan');
    nValid = sum(isfinite(zAll), 3);
    rMean(:, :, b) = tanh(zBar);
    sd = std(zAll, 0, 3, 'omitnan');
    se = sd ./ sqrt(max(1, nValid));
    se(nValid < 2) = NaN;      % no spread from a single trial
    zSE(:, :, b) = se;
end

[peakR, peakLagMs] = peaks(rMean, lagMs);

EEG = input;
EEG.xcorr           = rMean;
EEG.xcorrSE         = zSE;          % in Fisher-z units; see the header
EEG.xcorrLags       = lagMs;
EEG.xcorrRef        = char(labels{refIdx});
EEG.xcorrLabels     = labels(chanIdx);
EEG.xcorrBinLabels  = binLabels;
EEG.xcorrTrials     = nUsed;
EEG.xcorrPeakR      = peakR;
EEG.xcorrPeakLagMs  = peakLagMs;
EEG.xcorrWindowMs   = windowMs(input, lo, hi);

report(EEG, nChan, nBins, maxLagMs, minPairs);
end

% ======================================================================= %
function r = laggedPearson(x, y, maxLag, minPairs)
%LAGGEDPEARSON  Pearson r between X and Y at every lag in [-maxLag, maxLag],
%   each normalised by the statistics of exactly the sample pairs that
%   overlap at that lag, and each formed only from pairs where BOTH series
%   are finite.
%
%   r(L) correlates x(t) with y(t+L), so a positive L means Y follows X.
%
%   Every sum is a cross-correlation, so each is one FFT pair: the signals
%   with NaNs zeroed carry the sums, and their finite-value masks carry the
%   counts, which is what makes the pairwise NaN handling exact rather than
%   approximate.
    n = numel(x);
    mx = isfinite(x);
    my = isfinite(y);
    x0 = x; x0(~mx) = 0;
    y0 = y; y0(~my) = 0;

    cnt  = lagCorr(double(mx), double(my), n, maxLag);      % pair count
    sx   = lagCorr(x0,          double(my), n, maxLag);      % sum x
    sy   = lagCorr(double(mx),  y0,         n, maxLag);      % sum y
    sxx  = lagCorr(x0.^2,       double(my), n, maxLag);      % sum x^2
    syy  = lagCorr(double(mx),  y0.^2,      n, maxLag);      % sum y^2
    sxy  = lagCorr(x0,          y0,         n, maxLag);      % sum xy

    cnt = round(cnt);
    ok = cnt >= minPairs;

    cov = sxy - (sx .* sy) ./ max(cnt, 1);
    vx  = sxx - (sx.^2) ./ max(cnt, 1);
    vy  = syy - (sy.^2) ./ max(cnt, 1);

    den = sqrt(vx .* vy);
    r = nan(1, numel(cnt));
    good = ok & den > 0;
    r(good) = cov(good) ./ den(good);

    % Clip the last bit of floating-point slack -- but ONLY where there is a
    % value to clip. min/max ignore NaN in MATLAB (min(1, NaN) is 1, not
    % NaN), so clipping the whole array turns every refused lag into a
    % perfect correlation of 1: "too few sample pairs to say" would be
    % reported as the strongest coupling in the dataset. Caught by
    % aLagWithTooFewPairsIsNaNNotAConfidentNumber.
    r(good) = max(-1, min(1, r(good)));
end

function c = lagCorr(a, b, n, maxLag)
%LAGCORR  c(L) = sum_t a(t) b(t+L) for L in [-maxLag, maxLag], by FFT.
%   Zero-padded to at least 2n-1 so nothing wraps around; positive lags come
%   off the front of the circular result and negative lags off the back,
%   which is the indexing this returns in ascending lag order.
    nfft = 2^nextpow2(2 * n - 1);
    A = fft(a(:), nfft);
    B = fft(b(:), nfft);
    full = real(ifft(conj(A) .* B));
    pos = full(1:maxLag + 1).';               % L = 0 .. maxLag
    neg = full(nfft - maxLag + 1:nfft).';     % L = -maxLag .. -1
    c = [neg, pos];
end

function r = clampR(r)
%CLAMPR  Keep atanh finite: r of exactly +/-1 (a channel correlated with
%   itself, or a two-pair overlap) would otherwise become +/-Inf and poison
%   the average.
%
%   FINITE ENTRIES ONLY, for the same reason laggedPearson clips only its
%   own: min/max ignore NaN in MATLAB, so clamping the whole array would
%   turn every "too few sample pairs to say" into 1 - 1e-12, which atanh
%   then maps to a large finite z and tanh maps back to ~1. A refused lag
%   would come out as near-perfect correlation.
    lim = 1 - 1e-12;
    finite = isfinite(r);
    r(finite) = max(-lim, min(lim, r(finite)));
end

function [peakR, peakLagMs] = peaks(rMean, lagMs)
%PEAKS  The largest-magnitude correlation per channel per bin, and its lag.
%   Magnitude, not signed maximum: an inverted relationship is as much a
%   finding as a positive one, and reporting only the positive peak would
%   hide it.
    [nChan, ~, nBins] = size(rMean);
    peakR = nan(nChan, nBins);
    peakLagMs = nan(nChan, nBins);
    for b = 1:nBins
        for c = 1:nChan
            row = rMean(c, :, b);
            [~, ix] = max(abs(row));
            if isempty(ix) || ~isfinite(row(ix))
                continue;
            end
            peakR(c, b) = row(ix);
            peakLagMs(c, b) = lagMs(ix);
        end
    end
end

function [sets, labels] = binning(input)
    if isfield(input, 'bindesc') && ~isempty(input.bindesc)
        n = numel(input.bindesc);
        sets = cell(1, n);
        for b = 1:n
            sets{b} = TransTools.BinTrials(input, b);
        end
        labels = {input.bindesc.label};
    else
        sets = {1:size(input.data, 3)};
        labels = {char(string(TransTools.FieldOr(input, 'id', 'all trials')))};
    end
end

function [lo, hi] = windowRange(EEG, startMs, stopMs, nSamp)
    lo = 1; hi = nSamp;
    if stopMs <= startMs || ~isfield(EEG, 'times') || isempty(EEG.times)
        return;
    end
    a = find(EEG.times >= startMs, 1, 'first');
    b = find(EEG.times <= stopMs,  1, 'last');
    if isempty(a) || isempty(b) || b < a
        return;
    end
    lo = a; hi = b;
end

function ms = windowMs(EEG, lo, hi)
    if isfield(EEG, 'times') && numel(EEG.times) >= hi
        ms = [EEG.times(lo), EEG.times(hi)];
    else
        ms = [NaN, NaN];
    end
end

function labels = channelLabels(EEG)
    if isfield(EEG, 'chanlocs') && ~isempty(EEG.chanlocs) && isfield(EEG.chanlocs, 'labels')
        labels = cellfun(@(s) char(string(s)), {EEG.chanlocs.labels}, 'UniformOutput', false);
    else
        labels = arrayfun(@(i) sprintf('ch%d', i), 1:size(EEG.data, 1), 'UniformOutput', false);
    end
end

function report(EEG, nChan, nBins, maxLagMs, minPairs)
    % THE REFERENCE IS EXCLUDED FROM "strongest": correlated with itself it
    % is exactly 1 at lag 0, so it wins every time and says nothing -- the
    % same reason CoherenceTopography skips self-coherence. It stays in the
    % OUTPUT, where an r of 1 at lag 0 is a useful alignment check.
    peaks = EEG.xcorrPeakR;
    self = strcmpi(EEG.xcorrLabels, EEG.xcorrRef);
    peaks(self, :) = NaN;

    strongest = NaN; atLag = NaN; whichChan = '';
    [~, ix] = max(abs(peaks(:)));
    if ~isempty(ix) && isfinite(peaks(ix))
        [c, b] = ind2sub(size(peaks), ix);
        strongest = peaks(c, b);
        atLag = EEG.xcorrPeakLagMs(c, b);
        whichChan = EEG.xcorrLabels{c};
    end
    fprintf(['CrossCorrelation (reference %s): %d channel(s) x %d bin(s), lags +/-%g ms, ' ...
        'at least %d sample pairs per lag.\n'], EEG.xcorrRef, nChan, nBins, maxLagMs, minPairs);
    if isfinite(strongest)
        fprintf(['CrossCorrelation: strongest coupling r = %+.3f at %+g ms (%s) -- a ' ...
            'positive lag means the channel follows the reference.\n'], ...
            strongest, atLag, whichChan);
    end
end
