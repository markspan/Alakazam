function [thresholds, curves] = autorejectThresholds(X, folds)
%AUTOREJECTTHRESHOLDS  Each channel's peak-to-peak rejection threshold,
%   chosen by cross-validation (Jas et al., 2017, NeuroImage 159:417).
%
%   [THRESHOLDS, CURVES] = autorejectThresholds(X, FOLDS) takes X as
%   channels x samples x epochs (no NaN) and FOLDS from autorejectFolds, and
%   returns a 1 x nChan row of thresholds (in X's units) and, per channel,
%   the cross-validation curve it was chosen from (.thresholds, .error).
%
%   THE CRITERION, for one channel and a candidate threshold T: in each
%   fold, average the training epochs whose peak-to-peak amplitude is at
%   most T (at least the smallest, as autoreject keeps), and measure how far
%   that average is from the MEDIAN of the held-out epochs, as a root mean
%   square over samples. The median is a robust stand-in for the clean ERP:
%   a threshold that lets artefacts in pulls the average away from it, and
%   one that throws good epochs away makes the average noisy, so the error
%   is smallest in between. The threshold with the smallest error, averaged
%   over folds, is the channel's.
%
%   EXHAUSTIVE, WHERE AUTOREJECT SEARCHES. The error only changes where the
%   threshold crosses an epoch's own peak-to-peak value, so the candidates
%   are exactly those values; autoreject scores 40 of them and refines with
%   10 steps of Bayesian optimisation. Here every candidate is scored, which
%   is the exact minimum of the same criterion and needs no random state.
%   It is fast because, with a fold's training epochs sorted by peak-to-peak
%   amplitude, the average kept at each threshold is a running mean: one
%   cumulative sum per fold gives all of them.
%
%   See also AUTOREJECT, AUTOREJECTFOLDS, AUTOREJECTCONSENSUS.
    [nChan, nSamples, nEpochs] = size(X);
    ptp = reshape(max(X, [], 2) - min(X, [], 2), nChan, nEpochs);

    thresholds = zeros(1, nChan);
    curves = repmat(struct('thresholds', [], 'error', []), 1, nChan);
    for c = 1:nChan
        x = reshape(X(c, :, :), nSamples, nEpochs).';   % epochs x samples
        [thresholds(c), curves(c)] = channelThreshold(x, ptp(c, :), folds);
    end
end

% ======================================================================= %
function [best, curve] = channelThreshold(x, delta, folds)
%CHANNELTHRESHOLD  One channel's cross-validated threshold (see above).
    nEpochs = numel(delta);
    candidates = unique(delta(:));
    total = zeros(numel(candidates), 1);
    for f = 1:numel(folds)
        test = folds{f};
        train = setdiff(1:nEpochs, test);
        target = median(x(test, :), 1);

        [sortedDelta, order] = sort(delta(train));
        sortedDelta = sortedDelta(:);
        % The average of the k smallest-amplitude training epochs, for every
        % k at once, and its distance from the held-out median.
        runningMean = cumsum(x(train(order), :), 1) ./ (1:numel(train)).';
        errorOfK = sqrt(mean((runningMean - target) .^ 2, 2));

        % How many training epochs each candidate keeps: those at or below
        % it, and never fewer than the smallest (autoreject keeps
        % delta <= max(threshold, min(delta))).
        kept = max(countAtOrBelow(sortedDelta, candidates), nnz(sortedDelta <= sortedDelta(1)));
        total = total + errorOfK(kept);
    end
    curve = struct('thresholds', candidates, 'error', total / numel(folds));
    [~, i] = min(curve.error);
    best = candidates(i);
end

function counts = countAtOrBelow(sortedValues, queries)
%COUNTATORBELOW  For each query, how many of SORTEDVALUES are <= it.
%   Through the distinct values and their cumulative counts, so the cost is
%   a sort's, not a comparison of every value with every query.
    [distinct, ~, which] = unique(sortedValues);
    cumulative = cumsum(accumarray(which, 1));
    bin = discretize(queries, [distinct; Inf]);   % distinct(bin) <= q < distinct(bin + 1)
    counts = zeros(size(queries));
    inside = ~isnan(bin);
    counts(inside) = cumulative(bin(inside));
end
