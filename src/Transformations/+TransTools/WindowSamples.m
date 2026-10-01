function [lo, hi] = WindowSamples(times, startMs, stopMs, errorId, what)
%WINDOWSAMPLES  The first and last sample of a time window, by FieldTrip's
%   rule for a latency range (ft_selectdata, through its nearest.m): each end
%   goes to the nearest sample, the earlier one on an exact tie, and an end
%   beyond the data to its first or last sample (TransTools.NearestSample).
%   A window lying wholly outside TIMES is refused with ERRORID, as
%   ft_selectdata refuses it, rather than quietly replaced by the whole epoch.
%
%   [LO, HI] = TransTools.WindowSamples(TIMES, STARTMS, STOPMS, ERRORID, WHAT)
%   TIMES and the window are in the same unit (ms for an epoch); WHAT names
%   the window in the message ('test window', 'fitting range'). An unset or
%   empty window is the caller's to interpret, usually as the whole epoch, so
%   this is called only for a real one, with STARTMS < STOPMS.
%
%   See also TRANSTOOLS.NEARESTSAMPLE.
    times = double(times(:)).';
    if stopMs < times(1) || startMs > times(end)
        name = regexprep(char(errorId), '^Alakazam:', '');
        throw(MException(errorId, sprintf([ ...
            'Problem in %s: the %s, %g to %g ms, lies wholly outside this epoch ' ...
            '(%.4g to %.4g ms), I''m afraid, so there is nothing in it to use. Would you ' ...
            'choose one inside the epoch?'], name, what, startMs, stopMs, times(1), times(end))));
    end
    lo = TransTools.NearestSample(times, startMs);
    hi = TransTools.NearestSample(times, stopMs);
end
