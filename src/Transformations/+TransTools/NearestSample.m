function index = NearestSample(times, value)
%NEARESTSAMPLE  The index of the sample of TIMES nearest VALUE, by
%   FieldTrip's rule (nearest.m, which ft_preprocessing's baseline window
%   and ft_timelockbaseline use; ERPLAB's baseline does the same through its
%   closest.m):
%     - a VALUE before the first sample gives the first, after the last
%       gives the last;
%     - a VALUE exactly halfway between two samples gives the earlier one.
%   TIMES must be in ascending order, in the same unit as VALUE.
%
%   One rule for every place a time window in ms becomes samples, so that a
%   window means what it means in FieldTrip and ERPLAB.
%
%   See also BASELINE, DCDETREND.
    times = double(times(:));
    value = double(value);
    if value >= times(end)
        index = numel(times);
    elseif value <= times(1)
        index = 1;
    else
        below = find(times <= value, 1, 'last');
        above = find(times >= value, 1, 'first');
        if abs(times(below) - value) <= abs(times(above) - value)
            index = below;
        else
            index = above;
        end
    end
end
