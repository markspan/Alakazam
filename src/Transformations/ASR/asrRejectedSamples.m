function rejected = asrRejectedSamples(changed, minSpan)
%ASRREJECTEDSAMPLES  Which samples burst REJECTION removes, given which
%   samples ASR changed: every changed sample, plus every stretch of
%   unchanged samples too short to keep.
%
%   REJECTED = asrRejectedSamples(CHANGED, MINSPAN) takes a logical row
%   (true where ASR's reconstruction differs from its input) and returns the
%   logical row of samples to reject. A kept stretch is rejected too when its
%   last sample is fewer than MINSPAN samples after its first, that is, when
%   it is MINSPAN samples long or shorter. MINSPAN defaults to 5.
%
%   THIS IS CLEAN_RAWDATA'S OWN RULE, reproduced exactly: clean_artifacts,
%   with BurstRejection on, takes the kept intervals as [first last] and
%   drops those with last - first < 5, since a handful of samples between
%   two removed bursts is not usable data. It applies to every kept stretch,
%   the ones at the start and end of the recording included. Reproducing it
%   here, rather than calling clean_artifacts in its rejection mode, is what
%   lets ASR mark the stretch as rejected (NaN) instead of cutting it out, so
%   the recording keeps its length and its events their latencies.
%
%   See also ASR.
    if nargin < 2
        minSpan = 5;
    end
    changed = reshape(logical(changed), 1, []);
    rejected = changed;
    edges = diff([false, ~changed, false]);
    firsts = find(edges == 1);
    lasts  = find(edges == -1) - 1;
    for k = 1:numel(firsts)
        if lasts(k) - firsts(k) < minSpan
            rejected(firsts(k):lasts(k)) = true;
        end
    end
end
