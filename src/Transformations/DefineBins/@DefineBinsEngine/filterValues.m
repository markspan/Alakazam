function v = filterValues(test, candidates, rts, ctx)
%FILTERVALUES  The values a test about the bin's trials compares, one per
%   candidate trial (CANDIDATES, positions in the sorted event context CTX):
%   its reaction time (RTS, ms, the same order) or its event's field, after
%   the test's transform. NaN for a trial without one; a field no event has
%   is refused even when there are no candidates, as it is in an expression.
    if strcmp(test.source, 'rt')
        v = reshape(double(rts), 1, []);
    else
        DefineBinsEngine.fieldValue(test.name, [], ctx);
        v = NaN(1, numel(candidates));
        for c = 1:numel(candidates)
            v(c) = DefineBinsEngine.fieldValue(test.name, candidates(c), ctx);
        end
    end
    v = DefineBinsEngine.transformValues(v, test.transform);
end
