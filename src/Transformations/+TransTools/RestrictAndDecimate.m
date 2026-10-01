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
%   APPLIED BEFORE THE INVERSE by the callers that compute one, and AFTER it
%   when SourceCache.Lookup crops a stored estimate. Both give the same
%   answer, and that is measured rather than assumed: every ft_inverse_*
%   spatial filter is data-independent, so cropping commutes with inverting
%   to a relative 1.5e-16 for mne, sloreta and eloreta alike.
%
%   This comment used to claim the opposite, that a data-covariance method
%   must see the window under analysis and a wider estimate was therefore a
%   different fit. It is recorded here because that claim was load-bearing:
%   it put the window in the reuse key, which meant a whole-epoch estimate
%   could not serve a windowed analysis and every subject re-inverted for
%   each window tried.
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
        % FieldTrip's rule for a latency range, as ft_selectdata applies it:
        % the nearest sample at each end, and a window wholly outside the
        % epoch refused (TransTools.WindowSamples).
        [lo, hi] = TransTools.WindowSamples(times, window(1), window(2), errorId, 'time window');
        values = values(:, lo:hi);
        times  = times(lo:hi);
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
