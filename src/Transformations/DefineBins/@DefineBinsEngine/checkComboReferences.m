function checkComboReferences(bins)
%CHECKCOMBOREFERENCES  Catch two combination-bin mistakes right after
%   parsing, rather than as an opaque error much later during Average: a
%   combination referencing a bin number that does not exist in the script,
%   and a circular reference (a bin that, directly or through others,
%   combines itself) -- a combination bin may reference another
%   combination bin (nested/interaction differences), so this is not just
%   "must reference an ordinary bin".
    byIndex = containers.Map('KeyType', 'double', 'ValueType', 'double');
    for i = 1:numel(bins); byIndex(bins(i).index) = i; end

    state = zeros(1, numel(bins));  % 0 unvisited, 1 visiting, 2 done

    function visit(i, path, atPos)
        if state(i) == 2; return; end
        if state(i) == 1
            DefineBinsEngine.throwParseError(atPos, sprintf([ ...
                'I''m afraid this combination forms a loop, so it can never be computed: %s. ' ...
                'Every combination bin needs to bottom out, eventually, in bins that ' ...
                'match events directly -- would you mind untangling that chain of references?'], ...
                strjoin([path, {sprintf('bin %g "%s"', bins(i).index, bins(i).label)}], ' -> ')));
        end
        if isempty(bins(i).combo); state(i) = 2; return; end
        state(i) = 1;
        for t = 1:numel(bins(i).combo)
            refIdx = bins(i).combo(t).bin;
            termPos = bins(i).combo(t).pos;
            if ~isKey(byIndex, refIdx)
                DefineBinsEngine.throwParseError(termPos, sprintf([ ...
                    'bin %g "%s" combines bin %g, but there is no bin %g in this script, ' ...
                    'I''m afraid. Would you check for a typo in the bin number, or confirm ' ...
                    'that bin %g is actually defined somewhere (combination bins may ' ...
                    'reference ordinary bins, or even other combination bins, declared ' ...
                    'anywhere in the script)?'], ...
                    bins(i).index, bins(i).label, refIdx, refIdx, refIdx));
            end
            visit(byIndex(refIdx), [path, {sprintf('bin %g "%s"', bins(i).index, bins(i).label)}], termPos);
        end
        state(i) = 2;
    end
    for i = 1:numel(bins)
        visit(i, {}, -1);
    end
end
