function [v, k] = scanNum(T, k)
%SCANNUM  One plain number token, or a friendly parse error.
    t = DefineBinsEngine.tokAt(T, k);
    if t.kind ~= "num"
        DefineBinsEngine.throwParseError(t.pos, ...
            'I was hoping to find a plain number here (e.g. 200 or -1200), but did not.');
    end
    v = t.val; k = k + 1;
end
