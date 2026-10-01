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
%      two-interval scheme can only ever fit where it also subtracts. The
%      range goes to samples by FieldTrip's rule, the nearest sample at each
%      end (TransTools.NearestSample), as Baseline's window does.
%
%   3. A ROBUST OPTION, because drift estimation is precisely where
%      outliers hurt. 'Robust (Huber)' reweights the fit iteratively so a
%      large transient contributes like a moderate one instead of
%      dominating the slope: MATLAB's robustfit with Huber weights.
%
%   4. REJECTED SAMPLES ARE EXCLUDED FROM THE FIT. Alakazam writes rejection
%      as NaN (see TransTools.InterpolateFlaggedCells), so a fit that does
%      not skip NaNs returns NaN coefficients and destroys the channel. Both
%      fits run over finite samples only, and NaNs stay NaN in the output.
%
%   A channel with too few finite samples to determine the fit (fewer than
%   order+1) is left untouched rather than being handed a degenerate
%   solution; the count is reported.
%
%   TOOLBOX OR OWN CODE. Both fits are a toolbox's. Least squares is
%   MATLAB's polyfit and polyval, centred and scaled, on the finite samples
%   of the fitting range, subtracted from the whole epoch: what FieldTrip's
%   ft_preproc_polyremoval does (the function ft_preprocessing's
%   polyremoval and demean call), and on an epoch the same numbers. It is
%   not called because, as FieldTrip itself calls it, it fits the raw
%   sample index, and an order-2 trend on a long continuous record is then
%   lost entirely (50 uV off on 300 000 samples); its standardising option
%   needs a function private to another FieldTrip folder. The robust fit is
%   robustfit (Statistics and Machine Learning Toolbox) with Huber weights,
%   on the sample index z-scored over the epoch. MATLAB's detrend fits over
%   every sample it is given, so it could not serve. What is Alakazam's is
%   the choice of channels, the guard above and the report. This used to fit
%   by its own mldivide and a five-iteration Huber IRLS, and to take the
%   samples inside the fitting range rather than the nearest; least squares
%   is unchanged by the switch, the robust fit moves slightly (robustfit
%   adjusts for leverage and iterates to convergence).
%   FieldTripReferenceTest holds the least-squares fit to ft_preprocessing
%   and ft_preproc_polyremoval on epochs; DCDetrendTest checks known drifts
%   and MATLAB's detrend over the whole epoch.
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
        {'Channels'; 'Channels'}, DialogFields.Channels(input, TransTools.FieldOr(stored, 'Channels', {})), ...
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

nSamp = size(input.data, 2);
[fitLo, fitHi] = fitRange(input, TransTools.FieldOr(options, 'FitStart', 0), ...
    TransTools.FieldOr(options, 'FitStop', 0), nSamp);

EEG = input;
nTrials = size(input.data, 3);
nSkipped = 0;
slopes = [];

% The robust fit's basis: the sample index z-scored over the epoch, raised
% to the powers 0 to ORDER (constant included, so robustfit adds none). A raw
% index with a quadratic term is badly conditioned, and on a long continuous
% record unusable; polyfit centres and scales its own for the same reason.
sampleIndex = (0:nSamp - 1).';
z = (sampleIndex - mean(sampleIndex)) / std(sampleIndex);
basis = z .^ (0:order);                           % nSamp x (order + 1)
fitIdx = (fitLo:fitHi).';

for tr = 1:nTrials
    for c = chanIdx
        y = double(EEG.data(c, :, tr)).';
        use = fitIdx(isfinite(y(fitIdx)));
        if numel(use) < order + 1
            nSkipped = nSkipped + 1;
            continue;
        end
        if robust
            b = robustfit(basis(use, :), y(use), 'huber', [], 'off');
            trend = basis * b;
            slope = b(min(2, end)) * (z(min(2, end)) - z(1));            % per sample
        else
            [p, ~, mu] = polyfit(sampleIndex(use), y(use), order);
            trend = polyval(p, sampleIndex, [], mu);
            slope = p(max(1, end - 1)) / mu(2);                           % per sample
        end
        EEG.data(c, :, tr) = cast(reshape(y - trend, 1, []), 'like', EEG.data);
        if order >= 1
            slopes(end + 1) = slope; %#ok<AGROW>
        end
    end
end

report(order, robust, numel(chanIdx), nTrials, fitLo, fitHi, input, slopes, nSkipped);
end

% ======================================================================= %
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
%   testRange uses. Each end goes to the nearest sample, FieldTrip's rule
%   (TransTools.WindowSamples), and a range wholly outside the data is
%   refused rather than shrunk to its edge sample.
%
%   The range is given in ms, and a continuous recording keeps its time axis
%   in seconds (DEVELOPER.md), so there it is converted first: compared
%   directly, a 0 to 5000 ms range was read as 0 to 5000 seconds.
    lo = 1; hi = nSamp;
    if stopMs <= startMs || ~isfield(EEG, 'times') || isempty(EEG.times)
        return;
    end
    timesMs = double(EEG.times);
    if strcmpi(char(string(TransTools.FieldOr(EEG, 'DataFormat', ''))), 'CONTINUOUS')
        timesMs = timesMs * 1000;
    end
    [lo, hi] = TransTools.WindowSamples(timesMs, startMs, stopMs, 'Alakazam:DCDetrend', 'fitting range');
end

function report(order, robust, nChan, nTrials, fitLo, fitHi, input, slopes, nSkipped)
%REPORT  What was removed, in units a user can check against the trace.
%   The median slope is reported in uV/s rather than per sample, because
%   that is the number a drifting electrode is described by.
    method = 'least squares';
    if robust; method = 'robust (Huber)'; end
    if order >= 1 && ~isempty(slopes) && isfield(input, 'srate') && input.srate > 0
        % MEDIAN AND WORST, not just the median: on a recording where one
        % electrode drifts and the rest are steady, the median across
        % channel-trials is ~0 and says nothing about the drift that was
        % actually worth removing. The worst case is the number that
        % answers "did this dataset drift?".
        perSecond = abs(slopes) * input.srate;
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
