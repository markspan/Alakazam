function tl0 = zeroTimelock(tl)
%ZEROTIMELOCK  A same-shaped FieldTrip timelock struct with .avg all zero.
%   Used for a "combination bin against zero" contrast (e.g. is the N400
%   difference wave reliably nonzero anywhere across the scalp/epoch): the
%   standard FieldTrip idiom for a one-sample test is a PAIRED test of the
%   real condition against a matched all-zero one, not a dedicated
%   one-sample statistic, so this plus ClusterStats.pairedDesign together
%   reproduce that idiom (see e.g. FieldTrip's own tutorial on
%   within-subject cluster statistics against a null/baseline condition).
    tl0 = tl;
    tl0.avg = zeros(size(tl.avg));
end
