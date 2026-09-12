function [EEG, options] = DCDetrend(input, varargin)
%% DCDetrend  Remove a slow drift from each channel by fitting and subtracting it.
%
%   Fits a low-order polynomial (order 0, 1 or 2) to each channel -- per trial
%   on epoched data, over the whole record on continuous data -- and subtracts
%   it. Order 0 removes the mean, order 1 a linear drift, order 2 a slow
%   curvature (electrode settling, sweat).
%
%   FOUR WAYS THIS IMPROVES ON THE USUAL TWO-INTERVAL DETREND. BrainVision
%   Analyzer's local DC-Detrend asks for a start and an end interval and runs
%   a line through their two means. That is cheap and it is fragile, in ways
%   worth being explicit about:
%
%   1. THE FIT USES EVERY SAMPLE IT IS GIVEN, not two short windows. A line
%      through two interval means is determined entirely by whatever sits in
%      those two windows -- one blink inside the end interval tilts the
%      trend across the whole epoch, and nothing about the result says so.
%      A least-squares fit over the fitting range uses all of it, so a
%      single bad stretch moves the estimate by roughly its share of the
%      data instead of half the estimate.
%
%   2. THE FITTING RANGE AND THE SUBTRACTION RANGE ARE SEPARATE. FitStart /
%      FitStop choose where the drift is ESTIMATED; the fitted trend is
%      always subtracted from the whole epoch. For an ERP that matters: fit
%      across the evoked response and the response itself pulls on the
%      trend, which is the drift estimate absorbing the very signal being
%      measured. Fitting on the pre-stimulus baseline (and, if you like, a
%      late tail) and extrapolating across the response avoids that. A
%      two-interval scheme can only ever fit where it also subtracts.
%
%   3. A ROBUST OPTION, because drift estimation is precisely where
%      outliers hurt. 'Robust (Huber)' reweights the fit iteratively so a
%      large transient contributes like a moderate one instead of
%      dominating the slope. Implemented here directly (a handful of IRLS
%      iterations) rather than through robustfit, so this needs no
%      Statistics Toolbox -- the same reasoning SpectralMeasure applies to
%      its own dpss dependency, one fewer thing that can be missing.
%
%   4. REJECTED SAMPLES ARE EXCLUDED FROM THE FIT. Alakazam writes rejection
%      as NaN (see TransTools.InterpolateFlaggedCells), so a fit that does
%      not skip NaNs returns NaN coefficients and destroys the channel. The
%      fit here runs over finite samples only, and NaNs stay NaN in the
%      output. (Baseline.m, for contrast, takes a plain mean() -- correct
%      for data that has not been rejected yet, which is where it sits in
%      the pipeline, but not something to copy here.)
%
%   A channel with too few finite samples to determine the fit (fewer than
%   order+1) is left untouched rather than being handed a degenerate
%   solution; the count is reported.
%
%   Signature (Alakazam transformation contract):
%     [EEG, options] = DCDetrend(input)        % interactive dialog
%     [EEG, options] = DCDetrend(input, opts)  % replay a stored options struct
[opts, interactive] = TransTools.InitGuard(nargin, 'Alakazam:DCDetrend', varargin{:});

if ~isfield(input, 'data') || isempty(input.data)
    throw(MException('Alakazam:DCDetrend', ...
        'Problem in DCDetrend: I''m afraid this dataset has no data to detrend.'));
end

ORDERS  = {'1 - linear', '0 - mean only', '2 - quadratic'};
METHODS = {'Least squares', 'Robust (Huber)'};

labels = channelLabels(input);
if interactive
    stored = TransformSettings.get('DCDetrend');
    if isempty(stored) || ~isstruct(stored)
        stored = struct('Channels', {{}}, 'Order', ORDERS{1}, 'Method', METHODS{1}, ...
            'FitStart', 0, 'FitStop', 0);
    end
    options = TransformOptionsDialog( ...
        'Description', ['Fit a slow trend to each channel and subtract it. The fitting ' ...
            'range sets where the drift is ESTIMATED; the trend is always subtracted from ' ...
            'the whole epoch, so you can fit on the baseline and leave the response out of ' ...
            'the estimate. Leave the range 0 to 0 to fit everything, and the channel list ' ...
            'empty for all channels.'], ...
        'title', 'DC-Detrend options', ...
        'separator', 'Channels (empty = all):', ...
        {'Channels'; 'Channels'}, multiSelectField(labels, TransTools.FieldOr(stored, 'Channels', {})), ...
        'separator', 'Trend:', ...
        {'Polynomial order'; 'Order'}, TransTools.PutFirst(ORDERS, TransTools.FieldOr(stored, 'Order', ORDERS{1})), ...
        {'Fitting method'; 'Method'}, TransTools.PutFirst(METHODS, TransTools.FieldOr(stored, 'Method', METHODS{1})), ...
        'separator', 'Fit over (ms, 0 to 0 = everything):', ...
        {'Start'; 'FitStart'}, TransTools.FieldOr(stored, 'FitStart', 0), ...
        {'Stop'; 'FitStop'}, TransTools.FieldOr(stored, 'FitStop', 0));
    if isempty(options)
        EEG = [];       % cancelled -- no node, no compute
        options = [];   % the contract is two outputs; both must be assigned
        return;
    end
    TransformSettings.set('DCDetrend', options);
else
    options = opts;
end

order  = orderOf(TransTools.FieldOr(options, 'Order', ORDERS{1}));
robust = startsWith(lower(char(string(TransTools.FieldOr(options, 'Method', METHODS{1})))), 'robust');

chanIdx = TransTools.LabelsToIdx(input, TransTools.FieldOr(options, 'Channels', {}));
if isempty(chanIdx)
    chanIdx = 1:size(input.data, 1);   % empty selection means every channel
end

[fitLo, fitHi] = fitRange(input, TransTools.FieldOr(options, 'FitStart', 0), ...
    TransTools.FieldOr(options, 'FitStop', 0), size(input.data, 2));

EEG = input;
nTrials = size(input.data, 3);
nSkipped = 0;
slopes = [];

% x is centred and scaled on the FITTING range, not on sample index: a raw
% 1..n index with a quadratic term is badly conditioned (Vandermonde columns
% of wildly different magnitude), and centring costs nothing.
xAll = (1:size(input.data, 2)).';
xMid = mean([fitLo, fitHi]);
xScale = max(1, (fitHi - fitLo) / 2);
xAll = (xAll - xMid) / xScale;

for tr = 1:nTrials
    for c = chanIdx
        y = double(EEG.data(c, :, tr)).';
        fitMask = false(numel(y), 1);
        fitMask(fitLo:fitHi) = true;
        fitMask = fitMask & isfinite(y);
        if nnz(fitMask) < order + 1
            nSkipped = nSkipped + 1;
            continue;
        end
        coeff = polyFit(xAll(fitMask), y(fitMask), order, robust);
        trend = polyEval(coeff, xAll);
        EEG.data(c, :, tr) = single2likeInput(y - trend, EEG.data(c, :, tr));
        if order >= 1
            slopes(end + 1) = coeff(end - 1); %#ok<AGROW>
        end
    end
end

report(order, robust, numel(chanIdx), nTrials, fitLo, fitHi, input, slopes, nSkipped);
end

% ======================================================================= %
function coeff = polyFit(x, y, order, robust)
%POLYFIT  Least-squares (or Huber-weighted) polynomial coefficients, highest
%   power first -- the same ordering polyval expects. Solved through
%   mldivide on the Vandermonde matrix rather than polyfit(), so the robust
%   path can reuse exactly the same design matrix with weights applied.
    V = vander(x, order);
    coeff = V \ y;
    if ~robust
        return;
    end

    % IRLS with Huber weights. Five iterations: the weights settle well
    % before that on real drift data, and a fixed small count keeps a
    % per-channel-per-trial loop predictable rather than occasionally slow.
    for iter = 1:5
        r = y - V * coeff;
        s = 1.4826 * median(abs(r - median(r)));   % robust sigma (MAD)
        if s <= 0
            return;      % a perfect fit: nothing for the weights to do
        end
        u = r / (1.345 * s);                       % Huber's usual tuning
        w = ones(size(u));
        big = abs(u) > 1;
        w(big) = 1 ./ abs(u(big));
        sw = sqrt(w);
        coeff = (V .* sw) \ (y .* sw);
    end
end

function V = vander(x, order)
%VANDER  [x.^order ... x 1], highest power first.
    V = ones(numel(x), order + 1);
    for k = order:-1:1
        V(:, order + 1 - k) = x(:) .^ k;
    end
end

function y = polyEval(coeff, x)
    y = vander(x, numel(coeff) - 1) * coeff;
end

function out = single2likeInput(values, template)
%SINGLE2LIKEINPUT  Put VALUES back in the row shape and class the data
%   already had: EEGLAB commonly stores single, and silently widening one
%   channel to double would make EEG.data a mixed-class assignment error.
    out = cast(reshape(values, size(template)), 'like', template);
end

function order = orderOf(choice)
    token = regexp(char(string(choice)), '^\s*(\d+)', 'tokens', 'once');
    if isempty(token)
        order = 1;
    else
        order = str2double(token{1});
    end
end

function [lo, hi] = fitRange(EEG, startMs, stopMs, nSamp)
%FITRANGE  Sample range to ESTIMATE the trend over. A degenerate or absent
%   window means the whole epoch, the same convention ArtefactDetect's own
%   testRange uses.
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

function labels = channelLabels(EEG)
    if isfield(EEG, 'chanlocs') && ~isempty(EEG.chanlocs) && isfield(EEG.chanlocs, 'labels')
        labels = cellfun(@(s) char(string(s)), {EEG.chanlocs.labels}, 'UniformOutput', false);
    else
        labels = arrayfun(@(i) sprintf('ch%d', i), 1:size(EEG.data, 1), 'UniformOutput', false);
    end
end

function report(order, robust, nChan, nTrials, fitLo, fitHi, input, slopes, nSkipped)
%REPORT  What was removed, in units an analyst can check against the trace.
%   The median slope is reported in uV/s rather than per sample, because
%   that is the number a drifting electrode is described by.
    method = 'least squares';
    if robust; method = 'robust (Huber)'; end
    if order >= 1 && ~isempty(slopes) && isfield(input, 'srate') && input.srate > 0
        % coeff is in the centred/scaled x of the fit; one scaled unit is
        % (fitHi-fitLo)/2 samples, so convert back to per second.
        %
        % MEDIAN AND WORST, not just the median: on a recording where one
        % electrode drifts and the rest are steady, the median across
        % channel-trials is ~0 and says nothing about the drift that was
        % actually worth removing. The worst case is the number that
        % answers "did this dataset drift?".
        xScale = max(1, (fitHi - fitLo) / 2);
        perSecond = abs(slopes) / xScale * input.srate;
        trendText = sprintf(', |slope| removed: median %.3g, worst %.3g uV/s', ...
            median(perSecond), max(perSecond));
    else
        trendText = '';
    end
    fprintf('DCDetrend (order %d, %s): %d channel(s) x %d trial(s), fitted over samples %d-%d%s.\n', ...
        order, method, nChan, nTrials, fitLo, fitHi, trendText);
    if nSkipped > 0
        fprintf(['DCDetrend: %d channel-trial(s) had too few finite samples in the fitting ' ...
            'range to determine an order-%d trend and were left untouched.\n'], nSkipped, order);
    end
end
