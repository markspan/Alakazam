function [ctx, order] = buildContext(EEG)
%BUILDCONTEXT  Latency-ordered view of EEG.event for the evaluator: sorted
%   latencies, canonicalised type strings in the same order, the sampling
%   rate, NVALID (sort() puts NaN-latency events last, so windowRange's
%   binary search only ever needs the real, ascending-sorted prefix), and
%   the events themselves in the same order, for a 'field' test to read
%   the candidate event's own fields.
    ev  = EEG.event;
    n   = numel(ev);
    lat = zeros(1, n);
    typ = strings(1, n);
    for i = 1:n
        L = ev(i).latency;
        if isempty(L); L = NaN; else; L = double(L); end
        lat(i) = L;
        typ(i) = DefineBinsEngine.canonType(ev(i).type);
    end
    [latS, order] = sort(lat);
    ctx.lat    = latS;
    ctx.typ    = typ(order);
    ctx.srate  = EEG.srate;
    ctx.nValid = sum(~isnan(latS));
    ctx.ev     = ev(order);
end
