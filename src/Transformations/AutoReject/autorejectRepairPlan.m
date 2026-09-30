function interpolate = autorejectRepairPlan(ptp, bad, rho)
%AUTOREJECTREPAIRPLAN  Which bad channels of each epoch to interpolate:
%   all of them when there are at most RHO, otherwise the RHO worst.
%
%   INTERPOLATE = autorejectRepairPlan(PTP, BAD, RHO) takes the channels x
%   epochs peak-to-peak amplitudes PTP, the logical BAD (PTP above each
%   channel's threshold) and the most channels to interpolate per epoch, and
%   returns a logical channels x epochs plan. "Worst" is the largest
%   peak-to-peak amplitude, as in autoreject's _get_epochs_interpolation.
%   The bad channels left out stay as they were; whether the epoch is kept
%   at all is the consensus' decision (autorejectConsensus), not this one's.
%
%   Each RHO starts from BAD. autoreject's own cross-validation carries the
%   previous candidate's labels into the next, so an epoch can there have
%   more than RHO channels interpolated; the plan here is the one the paper
%   describes and the one autoreject's final repair uses.
%
%   See also AUTOREJECT, AUTOREJECTCONSENSUS.
    interpolate = logical(bad);
    crowded = find(sum(interpolate, 1) > rho);
    for e = crowded
        amplitude = ptp(:, e);
        amplitude(~interpolate(:, e)) = -Inf;
        [~, order] = sort(amplitude, 'descend');
        interpolate(:, e) = false;
        interpolate(order(1:rho), e) = true;
    end
end
