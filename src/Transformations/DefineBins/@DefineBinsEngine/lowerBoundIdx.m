function idx = lowerBoundIdx(sortedLat, nValid, target)
%LOWERBOUNDIDX  First index in sortedLat(1:nValid) with sortedLat(i) >=
%   target (nValid + 1 if none). Binary search, so a window lookup costs
%   O(log n) rather than the O(n) linear scan it is replacing.
    lo = 1; hi = nValid + 1;
    while lo < hi
        mid = floor((lo + hi) / 2);
        if sortedLat(mid) >= target
            hi = mid;
        else
            lo = mid + 1;
        end
    end
    idx = lo;
end
