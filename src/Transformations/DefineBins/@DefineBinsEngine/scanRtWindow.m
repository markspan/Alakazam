function [iv, k] = scanRtWindow(T, k, binIndex)
%SCANRTWINDOW  'rt within (lo,hi] unit' right after a bin's expression.
    t = DefineBinsEngine.tokAt(T, k);
    if ~(t.kind == "kw" && t.val == "within")
        DefineBinsEngine.throwParseError(t.pos, sprintf([ ...
            'bin %g: I''m afraid ''rt'' on its own is not quite enough -- it needs ' ...
            '''within (lo,hi] ms'' right after it to say what reaction-time range to ' ...
            'keep, for example rt within (200,500] ms.'], binIndex));
    end
    [iv, k] = DefineBinsEngine.scanInterval(T, k + 1);

    % A reaction time is a duration in milliseconds, so unlike a within-window
    % (which may legitimately be counted in samples or in events) there is
    % nothing for the other two units to mean here. scanInterval accepts all
    % three because the epoch directive and the relation windows share it, and
    % evaluateBins compares the recorded window against a millisecond value
    % without consulting .unit -- so "rt within (200,500] samples" used to be
    % accepted and then silently treated as milliseconds. Refusing it is the
    % honest answer: a misread window changes which trials enter the bin, and
    % says nothing about it in the report.
    if ~strcmp(iv.unit, 'ms')
        DefineBinsEngine.throwParseError(t.pos, sprintf([ ...
            'bin %g: a reaction time is a duration, so ''rt within'' is measured in ' ...
            'milliseconds -- ''%s'' is not a unit it can use. Would you write it as ' ...
            'rt within (200,500] ms? (''samples'' and ''events'' do work on an ordinary ' ...
            'within-window, just not on this one.)'], binIndex, iv.unit));
    end
end
