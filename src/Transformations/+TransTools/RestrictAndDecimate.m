function [values, times] = RestrictAndDecimate(values, times, window, targetHz, errorId)
%RESTRICTANDDECIMATE  Cut a signal to a latency window and thin it in time.
%
%   [VALUES, TIMES] = RestrictAndDecimate(VALUES, TIMES, WINDOW, TARGETHZ,
%   ERRORID). WINDOW is [startMs stopMs] or [] for everything; TARGETHZ is
%   an approximate rate or [] to keep every sample.
%
%   ONE IMPLEMENTATION, SHARED, AND THAT IS THE ENTIRE POINT. Both the
%   SourceEstimate transformation and SourceClusterStats prepare data this
%   way, and a stored estimate is reused only when its key says the window
%   and rate match (SourceCache.Key). If the two sides thinned
%   time even slightly differently, the key would keep asserting they agree
%   while the data quietly did not, and the analysis would run on samples it
%   did not think it had. That is not hypothetical: a second copy of this
%   logic was written with round() where the original had floor(), and
%   produced a different number of samples at the same requested rate.
%
%   APPLIED BEFORE THE INVERSE by both callers, deliberately: a
%   data-covariance method such as sLORETA must see the window actually
%   under analysis, so an estimate over a wider window is a different fit
%   rather than a superset that could be cropped afterwards.
%
%   PLAIN SUBSAMPLING, NOT A FILTERED RESAMPLE. These are already
%   baseline-corrected, low-pass-filtered averages, so the frequencies a
%   decimation filter would remove are not present to alias. downsample()
%   would also shift the latencies, and a cluster's reported timing has to
%   stay the recording's own.
%
%   See also SOURCEESTIMATE, SOURCECLUSTERSTATS,
%   TRANSTOOLS.SOURCEESTIMATEKEY.
    if nargin < 5 || isempty(errorId)
        errorId = 'Alakazam:RestrictAndDecimate';
    end

    if ~isempty(window)
        keep = times >= window(1) & times <= window(2);
        if ~any(keep)
            throw(MException(errorId, '%s', sprintf( ...
                'The time window [%g %g] ms contains no samples of this epoch (%g to %g ms).', ...
                window(1), window(2), times(1), times(end))));
        end
        values = values(:, keep);
        times  = times(keep);
    end

    if isempty(targetHz) || numel(times) < 2
        return;
    end
    currentHz = 1000 / median(diff(times));
    step = max(1, floor(currentHz / targetHz));
    if step <= 1
        return;
    end
    values = values(:, 1:step:end);
    times  = times(1:step:end);
end
