function v = transformValues(v, transform)
%TRANSFORMVALUES  The values V (a row, NaN for a trial without one) as a
%   value test's TRANSFORM makes them:
%     'none'  as they are;
%     'log'   the natural logarithm; a value of 0 or less has none (NaN),
%             so it lies in no window, as a missing value does;
%     'rank'  the percentile rank of each among them all, 0 to 100:
%             100 * (r - 0.5) / n, with r its rank from 1 to n and tied
%             values given the mean of their ranks. That is the definition
%             MATLAB's prctile uses for its percentiles (Hazen's), so, ties
%             apart, a value's rank is at most 50 exactly when the value is
%             at most the median, and at most 25 exactly when it is at most
%             p25. (Tied values share one rank, so a tie across the median
%             falls wholly on one side.)
    switch transform
        case 'log'
            positive = v > 0;
            v(positive) = log(v(positive));
            v(~positive) = NaN;
        case 'rank'
            v = percentRanks(v);
    end
end

% ======================================================================= %
function r = percentRanks(v)
    r = NaN(size(v));
    ok = ~isnan(v);
    x = v(ok);
    n = numel(x);
    if n == 0
        return;
    end
    [sorted, order] = sort(x);
    ranks = zeros(size(x));
    i = 1;
    while i <= n
        j = i;
        while j < n && sorted(j + 1) == sorted(i)
            j = j + 1;
        end
        ranks(order(i:j)) = (i + j) / 2;
        i = j + 1;
    end
    r(ok) = 100 * (ranks - 0.5) / n;
end
