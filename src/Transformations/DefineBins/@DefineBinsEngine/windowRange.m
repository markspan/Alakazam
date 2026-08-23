function [qLo, qHi] = windowRange(p, ctx, iv)
%WINDOWRANGE  The contiguous index range (into ctx.lat's ascending order)
%   that could possibly satisfy IV relative to event P. next/prev/any all
%   still re-check every candidate they actually visit with the exact
%   inInterval test afterwards, so this only needs to be a safe
%   (inclusive-bound) superset, not exact -- but restricting next/prev/any
%   to it is what turns a 'within (lo,hi]' window (used by nearly every
%   real DefineBins script) into a scan bounded by how many events fall in
%   that window, rather than an unconditional scan of the whole recording
%   for every one of its own events -- e.g. a "no response" bin (not
%   next(code) within (0,2000] ms), previously the worst case, used to keep
%   hunting for a same next(code) match arbitrarily far past the window
%   before finally giving up on it.
    if strcmp(iv.unit, 'events')
        % Ordinal distance, not elapsed time: the range is just an index
        % offset from p, no latency lookup needed.
        qLo = p + iv.lo;
        qHi = p + iv.hi;
        return;
    end
    if strcmp(iv.unit, 'samples')
        loLat = ctx.lat(p) + iv.lo;
        hiLat = ctx.lat(p) + iv.hi;
    else
        loLat = ctx.lat(p) + iv.lo / 1000 * ctx.srate;
        hiLat = ctx.lat(p) + iv.hi / 1000 * ctx.srate;
    end
    qLo = DefineBinsEngine.lowerBoundIdx(ctx.lat, ctx.nValid, loLat);
    qHi = DefineBinsEngine.upperBoundIdx(ctx.lat, ctx.nValid, hiLat);
end
