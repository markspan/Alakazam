function [iv, k] = scanInterval(T, k)
%SCANINTERVAL  Standalone interval scanner, shared by the epoch directive
%   and the expression parser's within-window. Returns the window and the
%   next cursor.
    o = DefineBinsEngine.tokAt(T, k);
    if ~(o.kind == "punc" && (o.val == "(" || o.val == "["))
        DefineBinsEngine.throwParseError(o.pos, [ ...
            'A window needs to start with ''('' (exclusive bound) or ''['' ' ...
            '(inclusive bound), like within (200,1200] ms -- I wasn''t able to find ' ...
            'either one here.']);
    end
    loOpen = (o.val == "("); k = k + 1;
    [lo, k] = DefineBinsEngine.scanNum(T, k);
    cComma = DefineBinsEngine.tokAt(T, k);
    if ~(cComma.kind == "punc" && cComma.val == ",")
        DefineBinsEngine.throwParseError(cComma.pos, [ ...
            'A window needs a comma between its low and high bound, for example ' ...
            'within (200,1200] ms -- I''m afraid I found the low bound, but no comma ' ...
            'after it.']);
    end
    k = k + 1;
    [hi, k] = DefineBinsEngine.scanNum(T, k);
    c = DefineBinsEngine.tokAt(T, k);
    if ~(c.kind == "punc" && (c.val == ")" || c.val == "]"))
        DefineBinsEngine.throwParseError(c.pos, [ ...
            'A window needs to end with '')'' (exclusive bound) or '']'' ' ...
            '(inclusive bound), like within (200,1200] ms -- I couldn''t find ' ...
            'either one here, I''m afraid.']);
    end
    hiOpen = (c.val == ")"); k = k + 1;
    unit = 'ms';
    u = DefineBinsEngine.tokAt(T, k);
    if u.kind == "kw" && (u.val == "ms" || u.val == "samples" || u.val == "events")
        unit = char(u.val); k = k + 1;
    end
    if lo > hi
        DefineBinsEngine.throwParseError(o.pos, sprintf([ ...
            'This window''s low bound (%g) is greater than its high bound (%g), ' ...
            'I''m afraid, so nothing could ever fall inside it. Windows are signed and ' ...
            'measured from the anchor (+ = later, - = earlier); did you perhaps mean %s?'], ...
            lo, hi, sprintf('(%g,%g]', min(lo,hi), max(lo,hi))));
    end
    iv = struct('lo', lo, 'hi', hi, 'loOpen', loOpen, 'hiOpen', hiOpen, 'unit', unit);
end
