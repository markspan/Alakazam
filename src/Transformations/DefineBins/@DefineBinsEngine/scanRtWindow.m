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
end
