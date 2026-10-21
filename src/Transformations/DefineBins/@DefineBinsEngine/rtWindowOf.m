function iv = rtWindowOf(test)
%RTWINDOWOF  A reaction-time test in the form a bin's rtWindow has held
%   since 'rt within' began, when it fits that form: plain rt (no log or
%   rank), each bound a number or mean (+|-) k sd. [] when it does not
%   (a median, a percentile, iqr or mad, an infinite bound), and the test
%   then goes with the bin's other filters.
%
%   Keeping that form for what it can say means a plan compiled with such a
%   window evaluates exactly as before (resolveRtWindow, bindesc.rtTrim,
%   the summary's line), and replays in an Alakazam from before value tests.
%
%   IV has lo, hi, loOpen, hiOpen, unit ('ms') and loSd, hiSd: NaN in
%   lo/hi and the multiplier of the standard deviation in loSd/hiSd for a
%   bound relative to the mean (0 for a bare mean), NaN in loSd/hiSd for a
%   number.
    iv = [];
    if ~strcmp(test.source, 'rt') || ~strcmp(test.transform, 'none')
        return;
    end
    [lo, loSd, okLo] = oldBound(test.window.lo);
    [hi, hiSd, okHi] = oldBound(test.window.hi);
    if ~(okLo && okHi)
        return;
    end
    iv = struct('lo', lo, 'hi', hi, 'loOpen', logical(test.window.loOpen), ...
        'hiOpen', logical(test.window.hiOpen), 'unit', 'ms', 'loSd', loSd, 'hiSd', hiSd);
end

% ======================================================================= %
function [value, sd, ok] = oldBound(b)
    value = NaN;
    sd = NaN;
    ok = true;
    if strcmp(b.kind, 'num')
        value = double(b.value);
    elseif strcmp(b.kind, 'stat') && strcmp(b.stat, 'mean') ...
            && (b.k == 0 || strcmp(b.spread, 'sd'))
        sd = double(b.k);
    else
        ok = false;
    end
end
