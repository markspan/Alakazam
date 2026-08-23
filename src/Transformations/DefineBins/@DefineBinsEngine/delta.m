function d = delta(q, p, ctx, iv)
%DELTA  Signed distance from event P to event Q, in IV's own unit.
    if ~isempty(iv) && strcmp(iv.unit, 'events')
        % Ordinal distance in the event stream, not elapsed time: immune to
        % RT/ISI jitter, unlike ms/samples -- e.g. within [-2,-2] events means
        % "exactly two events before", regardless of how long that took.
        d = q - p;
        return;
    end
    d = ctx.lat(q) - ctx.lat(p);
    if isempty(iv) || ~strcmp(iv.unit, 'samples')
        d = d / ctx.srate * 1000;   % ms
    end
end
