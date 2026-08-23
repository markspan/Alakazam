function idx = upperBoundIdx(sortedLat, nValid, target)
%UPPERBOUNDIDX  Last index in sortedLat(1:nValid) with sortedLat(i) <=
%   target (0 if none).
    lo = 0; hi = nValid;
    while lo < hi
        mid = ceil((lo + hi + 1) / 2);
        if sortedLat(mid) <= target
            lo = mid;
        else
            hi = mid - 1;
        end
    end
    idx = lo;
end
