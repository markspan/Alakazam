function pooled = pooledValues(events, eventTypes, formulas)
%POOLEDVALUES  For each continuous or spline field any formula uses, its
%   values over every modelled event whose type uses it: the common ground
%   Unfold.fitBins evaluates every bin's waveform on, so that a covariate
%   whose values differ between bins is held at the same values for all of
%   them rather than at each bin's own (see Unfold.fitBins). Factors are
%   not pooled: each bin keeps its own mix of levels. .common is the range
%   of values every type using the field shares, [] when they share none:
%   a spline is only evaluated there, since outside a bin's own values it
%   would be extrapolating.
%
%   EVENTS are the events in the fit (Unfold.binModel's plan.events where
%   plan.kept), so an event uf_imputeMissing's 'drop' left out, or whose
%   epoch was left out, is not among them (Unfold.keepEvents).
%
%   A 2D SPLINE (2dspl(x, z, n)) is evaluated at both fields at once, so it
%   gets an entry of its own: named as the toolbox names it, the two field
%   names run together ("xz"), with .pair {x, z}, .values the pairs of every
%   event that uses it (2 x n, from the same events), and .common a 2 x 2
%   box, each row the range of one field every type using it shares.
%
%   See also UNFOLD.BINMODEL, UNFOLD.KEEPEVENTS, UNFOLD.FORMULAVARIABLES.
    pooled = struct('name', {}, 'values', {}, 'common', {}, 'pair', {});
    for t = 1:numel(eventTypes)
        rows = strcmp({events.type}, eventTypes{t});
        [vars, pairs] = Unfold.formulaVariables(formulas{t});
        for v = vars
            if v.categorical
                continue;
            end
            pooled = addPooled(pooled, v.name, [events(rows).(v.name)], {});
        end
        for p = pairs
            pooled = addPooled(pooled, [p{1}{:}], ...
                [[events(rows).(p{1}{1})]; [events(rows).(p{1}{2})]], p{1});
        end
    end
end

function pooled = addPooled(pooled, name, values, pair)
%ADDPOOLED  VALUES (one row per field) added to the entry NAME of the same
%   kind (a field, or a 2D spline's PAIR), and the range every type using it
%   shares narrowed to the values of this one. A missing value (NaN, before
%   uf_imputeMissing fills it in) is not a value of the field, so it is
%   left out, and a pair with one missing is left out whole.
    values = values(:, all(isfinite(values), 1));
    span = [min(values, [], 2), max(values, [], 2)];
    at = find(strcmp({pooled.name}, name) & cellfun(@isempty, {pooled.pair}) == isempty(pair), 1);
    if isempty(at)
        pooled(end + 1) = struct('name', name, 'values', values, 'common', span, 'pair', {pair});
        return;
    end
    pooled(at).values = [pooled(at).values, values];
    common = pooled(at).common;
    if ~isempty(common)
        common = [max(common(:, 1), span(:, 1)), min(common(:, 2), span(:, 2))];
        if any(common(:, 1) > common(:, 2))
            common = [];
        end
    end
    pooled(at).common = common;
end
