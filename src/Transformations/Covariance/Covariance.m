function [EEG, options] = Covariance(input, varargin)
%% Covariance  Channel-by-channel covariance (or correlation) matrix, per bin.
%
%   Pools the samples inside a time window across the bin's trials and
%   estimates the p x p second-moment matrix over channels: covariance
%   (in uV^2) or correlation (unit diagonal). One matrix per bin, drawn as a
%   heatmap by CovarianceView.
%
%   FOUR THINGS THIS DOES THAT A PLAIN cov() DOES NOT, and they are the
%   reason this is a transformation rather than a formula:
%
%   1. SHRINKAGE, because the sample covariance of EEG is usually badly
%      conditioned and often singular. With p channels you need well over p
%      independent observations before the sample estimate is trustworthy,
%      and a 64-channel montage over a short window does not have them --
%      the small eigenvalues come out far too small (or zero), which is
%      exactly what breaks anything that later inverts or factorises the
%      matrix. 'Ledoit-Wolf' applies the closed-form optimal shrinkage
%      toward a scaled identity (Ledoit & Wolf, 2004): no tuning parameter,
%      no cross-validation, and it is guaranteed positive definite. The
%      condition number before and after is reported, so the improvement
%      is visible rather than asserted. BrainVision Analyzer's Covariance
%      module offers the raw estimate only.
%
%   2. COMPLETE OBSERVATIONS, NOT PAIRWISE DELETION. Alakazam marks
%      rejected samples as NaN (see TransTools.InterpolateFlaggedCells), so
%      something must be done about them. Deleting pairwise -- computing
%      each entry from whatever samples that PAIR happens to share -- is
%      the tempting choice and it is wrong here: the entries then come from
%      different sample sets and the result need not be positive
%      semidefinite, i.e. it can imply a negative variance along some
%      combination of channels and is not a covariance matrix at all.
%      Dropping whole time points that any selected channel rejected keeps
%      the estimate a genuine covariance matrix. How many were dropped is
%      reported, because that is the cost of the choice.
%
%   3. CORRELATION IS DERIVED FROM THE SHRUNK COVARIANCE, in that order.
%      Normalising first and shrinking afterwards would shrink a matrix
%      whose diagonal is already 1 toward an identity it already matches on
%      the diagonal, which is not the same estimator and is not the one
%      with the optimality result behind it.
%
%   4. PER-BIN, over the bin's own trials (TransTools.BinTrials), with the
%      observation count carried alongside each matrix -- a covariance from
%      40 trials and one from 4 should not look alike in the output when
%      they are not alike in reliability.
%
%   Signature (Alakazam transformation contract):
%     [EEG, options] = Covariance(input)        % interactive dialog
%     [EEG, options] = Covariance(input, opts)  % replay a stored options struct
[opts, interactive] = TransTools.InitGuard(nargin, 'Alakazam:Covariance', varargin{:});

if ~isfield(input, 'data') || isempty(input.data)
    throw(MException('Alakazam:Covariance', ...
        'Problem in Covariance: I''m afraid this dataset has no data.'));
end

STATS  = {'Covariance', 'Correlation'};
SHRINK = {'Ledoit-Wolf', 'None'};

labels = channelLabels(input);
if interactive
    stored = TransformSettings.get('Covariance');
    if isempty(stored) || ~isstruct(stored)
        stored = struct('Channels', {{}}, 'Statistic', STATS{1}, ...
            'Shrinkage', SHRINK{1}, 'Start', 0, 'Stop', 0);
    end
    options = TransformOptionsDialog( ...
        'Description', ['Channel-by-channel covariance or correlation over the samples in ' ...
            'a window, pooled across each bin''s trials. Ledoit-Wolf shrinkage is ' ...
            'recommended whenever there are not many more observations than channels: it ' ...
            'keeps the matrix invertible without a tuning parameter. Leave the window 0 to ' ...
            '0 for the whole epoch, and the channel list empty for all channels.'], ...
        'title', 'Covariance options', ...
        'separator', 'Channels (empty = all):', ...
        {'Channels'; 'Channels'}, multiSelectField(labels, TransTools.FieldOr(stored, 'Channels', {})), ...
        'separator', 'Statistic:', ...
        {'Matrix'; 'Statistic'}, TransTools.PutFirst(STATS, TransTools.FieldOr(stored, 'Statistic', STATS{1})), ...
        {'Shrinkage'; 'Shrinkage'}, TransTools.PutFirst(SHRINK, TransTools.FieldOr(stored, 'Shrinkage', SHRINK{1})), ...
        'separator', 'Window (ms, 0 to 0 = whole epoch):', ...
        {'Start'; 'Start'}, TransTools.FieldOr(stored, 'Start', 0), ...
        {'Stop'; 'Stop'}, TransTools.FieldOr(stored, 'Stop', 0));
    if isempty(options)
        EEG = [];       % cancelled -- no node, no compute
        options = [];   % the contract is two outputs; both must be assigned
        return;
    end
    TransformSettings.set('Covariance', options);
else
    options = opts;
end

chanIdx = TransTools.LabelsToIdx(input, TransTools.FieldOr(options, 'Channels', {}));
if isempty(chanIdx)
    chanIdx = 1:size(input.data, 1);
end
if numel(chanIdx) < 2
    throw(MException('Alakazam:Covariance', ...
        'Problem in Covariance: a covariance matrix needs at least two channels.'));
end

wantCorrelation = startsWith(lower(char(string(TransTools.FieldOr(options, 'Statistic', STATS{1})))), 'corr');
shrink = startsWith(lower(char(string(TransTools.FieldOr(options, 'Shrinkage', SHRINK{1})))), 'ledoit');

[lo, hi] = windowRange(input, TransTools.FieldOr(options, 'Start', 0), ...
    TransTools.FieldOr(options, 'Stop', 0), size(input.data, 2));

[binTrialSets, binLabels] = binning(input);
nBins = numel(binTrialSets);
p = numel(chanIdx);

matrices = nan(p, p, nBins);
deltas   = nan(1, nBins);
nObs     = zeros(1, nBins);
nDropped = zeros(1, nBins);
condBefore = nan(1, nBins);
condAfter  = nan(1, nBins);

for b = 1:nBins
    trials = binTrialSets{b};
    if isempty(trials)
        continue;   % a combination bin owns no trials of its own
    end
    X = reshape(input.data(chanIdx, lo:hi, trials), p, []);   % p x observations
    X = double(X);

    % COMPLETE OBSERVATIONS ONLY -- see the header for why this is not
    % pairwise deletion.
    keep = all(isfinite(X), 1);
    nDropped(b) = nnz(~keep);
    X = X(:, keep);
    nObs(b) = size(X, 2);
    if nObs(b) < 2
        continue;
    end

    X = X - mean(X, 2);
    S = (X * X') / nObs(b);
    condBefore(b) = conditionOf(S);

    if shrink
        [S, deltas(b)] = ledoitWolf(X, S, nObs(b));
    else
        deltas(b) = 0;
    end
    condAfter(b) = conditionOf(S);

    if wantCorrelation
        S = toCorrelation(S);
    end
    matrices(:, :, b) = S;
end

EEG = input;
EEG.covariance    = matrices;
EEG.covLabels     = labels(chanIdx);
EEG.covBinLabels  = binLabels;
EEG.covStatistic  = lower(ternary(wantCorrelation, 'correlation', 'covariance'));
EEG.covShrinkage  = deltas;
EEG.covN          = nObs;
EEG.covDropped    = nDropped;
EEG.covWindowMs   = windowMs(input, lo, hi);

report(EEG.covStatistic, shrink, p, nObs, nDropped, deltas, condBefore, condAfter);
end

% ======================================================================= %
function [S, delta] = ledoitWolf(X, S, n)
%LEDOITWOLF  Shrink S toward a scaled identity by the Ledoit-Wolf (2004)
%   optimal intensity. X is p x n and already centred; S is X*X'/n.
%
%   The target is m*I with m the average eigenvalue (trace(S)/p), so the
%   estimate keeps S's overall scale and pulls only its SHAPE toward
%   sphericity -- which is what makes the small, badly estimated
%   eigenvalues grow while the large, well-estimated ones barely move.
%
%   delta is clamped to [0, 1]: the closed form can stray outside it on
%   small samples, and a negative shrinkage (extrapolating AWAY from the
%   target) or one above 1 (overshooting past it) is never what is wanted.
    p = size(X, 1);
    m = trace(S) / p;
    dSq = sum((S - m * eye(p)).^2, 'all');           % ||S - m I||_F^2

    % bBarSq: mean over observations of ||x_k x_k' - S||_F^2, divided by n.
    % Written as a sum over observations of (x'x)^2 rather than forming each
    % outer product, which is the same quantity and stays O(p n).
    xSq = sum(X.^2, 1);                               % 1 x n, = x_k' x_k
    bBarSq = (sum(xSq.^2) / n - sum(S.^2, 'all')) / n;

    bSq = max(0, min(bBarSq, dSq));
    if dSq <= 0
        delta = 0;      % S is already m*I: nothing to shrink toward
    else
        delta = bSq / dSq;
    end
    delta = max(0, min(1, delta));
    S = delta * m * eye(p) + (1 - delta) * S;
end

function R = toCorrelation(S)
%TOCORRELATION  Normalise to a unit diagonal, guarding a zero-variance
%   channel (a flat or fully rejected channel) rather than dividing by it.
    d = sqrt(diag(S));
    d(d <= 0 | ~isfinite(d)) = NaN;
    R = S ./ (d * d.');
    R(1:size(R, 1) + 1:end) = 1;    % exact ones on the diagonal
end

function c = conditionOf(S)
    if any(~isfinite(S(:)))
        c = NaN;
        return;
    end
    c = cond(S);
end

function [sets, labels] = binning(input)
%BINNING  One trial-index set per bin, or a single set of every trial when
%   the dataset has no bin description.
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

function report(statistic, shrink, p, nObs, nDropped, deltas, condBefore, condAfter)
    usable = nObs >= 2;
    fprintf('Covariance (%s, %d channels): %d of %d bin(s) estimated, %d-%d observations each.\n', ...
        statistic, p, nnz(usable), numel(nObs), min(nObs(usable), [], 'omitnan'), ...
        max(nObs(usable), [], 'omitnan'));
    if any(nDropped > 0)
        fprintf(['Covariance: %d time point(s) were dropped as incomplete (a rejected ' ...
            'sample on any selected channel drops that whole observation, which is what ' ...
            'keeps the matrix a valid covariance).\n'], sum(nDropped));
    end
    if shrink && any(usable)
        fprintf(['Covariance: Ledoit-Wolf shrinkage %.3f-%.3f; condition number %.3g -> ' ...
            '%.3g (lower is better conditioned).\n'], ...
            min(deltas(usable)), max(deltas(usable)), ...
            median(condBefore(usable), 'omitnan'), median(condAfter(usable), 'omitnan'));
    end
end

function out = ternary(cond, a, b)
    if cond; out = a; else; out = b; end
end
