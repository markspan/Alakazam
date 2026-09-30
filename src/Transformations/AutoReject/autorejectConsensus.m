function [kappa, rho, loss] = autorejectConsensus(X, bad, ptp, folds, kappaGrid, rhoGrid, interpolate)
%AUTOREJECTCONSENSUS  How many bad channels condemn an epoch (kappa), and
%   how many are interpolated in the epochs that are kept (rho), chosen by
%   cross-validation (Jas et al., 2017, the "local" autoreject).
%
%   [KAPPA, RHO, LOSS] = autorejectConsensus(X, BAD, PTP, FOLDS, KAPPAGRID,
%   RHOGRID, INTERPOLATE) takes
%     X            channels x samples x epochs, the data (no NaN);
%     BAD, PTP     channels x epochs: which channel-epochs exceed their
%                  channel's threshold, and the peak-to-peak amplitudes;
%     FOLDS        from autorejectFolds;
%     KAPPAGRID    candidate consensus fractions (autoreject: 0:0.1:1);
%     RHOGRID      candidate numbers of channels to interpolate
%                  (autoreject: 1, 4 and min(nChan - 1, 32));
%     INTERPOLATE  a function handle, @(plan) -> X with the channel-epochs
%                  in the logical channels x epochs PLAN interpolated from
%                  the rest of their epoch. Passed in, so this function is
%                  the algorithm alone and can be tested without EEGLAB.
%   and returns the chosen pair and the kappa x rho grid of mean losses.
%
%   THE CRITERION, for one (kappa, rho): repair every epoch by interpolating
%   up to rho of its bad channels (autorejectRepairPlan); in each fold, drop
%   the training epochs with kappa * nChan or more bad channels, average the
%   rest, and measure the root mean square distance from the median of the
%   held-out epochs as recorded, over channels and samples. The pair with
%   the smallest loss, averaged over folds, wins, the first in (kappa, rho)
%   order on a tie, as autoreject's argmin over its loss array is.
%
%   Two rules are autoreject's own and are kept: a pair with
%   kappa * nChan <= rho scores infinity (an epoch would be repaired and
%   rejected by the same channels), and so does a fold with no training
%   epoch left to average.
%
%   See also AUTOREJECT, AUTOREJECTTHRESHOLDS, AUTOREJECTREPAIRPLAN.
    [nChan, ~, nEpochs] = size(X);
    counts = sum(bad, 1);
    targets = cellfun(@(test) median(X(:, :, test), 3), folds, 'UniformOutput', false);

    lossByFold = inf(numel(kappaGrid), numel(rhoGrid), numel(folds));
    for j = 1:numel(rhoGrid)
        repaired = interpolate(autorejectRepairPlan(ptp, bad, rhoGrid(j)));
        for f = 1:numel(folds)
            train = setdiff(1:nEpochs, folds{f});
            for i = 1:numel(kappaGrid)
                limit = kappaGrid(i) * nChan;
                if limit <= rhoGrid(j)
                    continue;   % kappa must exceed rho
                end
                kept = train(counts(train) < limit);
                if isempty(kept)
                    continue;
                end
                average = mean(repaired(:, :, kept), 3);
                lossByFold(i, j, f) = sqrt(mean((targets{f} - average) .^ 2, 'all'));
            end
        end
    end

    loss = mean(lossByFold, 3);
    if all(isinf(loss(:)))
        throw(MException('Alakazam:AutoReject', ['I''m afraid no combination of consensus ' ...
            'and interpolation left any epoch to average, so AutoReject cannot choose one. ' ...
            'This happens with very few channels or very few epochs.']));
    end
    % The first minimum in (kappa, rho) order, which is numpy's argmin over
    % a kappa x rho array: MATLAB's own min walks columns first, so the grid
    % is transposed for it.
    byRow = loss.';
    [~, at] = min(byRow(:));
    [j, i] = ind2sub(size(byRow), at);
    kappa = kappaGrid(i);
    rho = rhoGrid(j);
end
