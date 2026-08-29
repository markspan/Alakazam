function [node, k] = scanCodeElem(T, k, aliases)
%SCANCODEELEM  One code element: a literal number/string, or an alias
%   reference spliced in from ALIASES.
    t = DefineBinsEngine.tokAt(T, k);
    if t.kind == "num"
        % EVENT CODES ARE NEVER NEGATIVE, which is what makes ranges
        % unambiguous. The lexer reads a leading '-' as the start of a
        % negative number, so "21-30" arrives as the two numbers 21 and -30
        % and "21 - 30" as 21, '-', 30. Since neither -30 nor a bare minus
        % can be a code, both spellings can only be the range 21 to 30, and
        % whitespace around the dash does not matter.
        if t.val < 0
            DefineBinsEngine.throwParseError(t.pos, sprintf([ ...
                'Event codes are never negative, so %g cannot be one, I''m afraid. ' ...
                'If you meant a range of codes, would you write it as low-high, e.g. ' ...
                '21-30? If you meant a text marker that happens to start with a ' ...
                'minus, it needs quotes: "%g".'], t.val, t.val));
        end
        [range, k2] = scanNumericRange(T, k);
        if ~isempty(range)
            node = DefineBinsEngine.anchorNode(range);
            k = k2;
            return;
        end
        node = DefineBinsEngine.anchorNode(DefineBinsEngine.canonType(t.val)); k = k + 1;
    elseif t.kind == "str"
        node = DefineBinsEngine.anchorNode(DefineBinsEngine.canonType(t.val)); k = k + 1;
    elseif t.kind == "ident"
        name = char(t.val);
        if ~isfield(aliases, name)
            DefineBinsEngine.throwParseError(t.pos, sprintf([ ...
                'I don''t know what ''%s'' means, I''m afraid -- there is no let alias by ' ...
                'that name (at least, not one defined earlier in the script). If you ' ...
                'meant a text marker, it needs quotes: "%s". If you meant an alias, ' ...
                'would you define it first: let %s = ...'], name, name, name));
        end
        node = aliases.(name); k = k + 1;                   % splice in the alias's expression
    else
        DefineBinsEngine.throwParseError(t.pos, [ ...
            'I was hoping to find a marker code here -- a number (112), a quoted text ' ...
            'marker ("S112"), a {...} or |-separated set of these, or the name of a ' ...
            'let alias.']);
    end
end
% ----------------------------------------------------------------------- %
function [codes, k] = scanNumericRange(T, k)
%SCANNUMERICRANGE  "<lo>-<hi>" at cursor K as the codes it covers, or [] if
%   what is there is a single code. K advances past the range only on a hit.
%
%   Two token shapes reach here, because the lexer treats a leading '-' as
%   the start of a negative number and so splits the same range differently
%   depending on the spaces around the dash:
%
%       21-30    ->  num(21)  num(-30)
%       21 -30   ->  num(21)  num(-30)
%       21 - 30  ->  num(21)  punc('-')  num(30)
%       21- 30   ->  num(21)  punc('-')  num(30)
%
%   All four are the same range. Event codes are never negative, so neither
%   a negative number nor a bare '-' can be anything else in a code
%   position, and no whitespace rule is needed to tell them apart.
    codes = strings(1, 0);
    lo = DefineBinsEngine.tokAt(T, k);
    nxt = DefineBinsEngine.tokAt(T, k + 1);

    if nxt.kind == "num" && nxt.val < 0
        hiVal = -nxt.val;
        step = 2;
    elseif nxt.kind == "punc" && nxt.val == "-"
        after = DefineBinsEngine.tokAt(T, k + 2);
        if after.kind ~= "num"
            DefineBinsEngine.throwParseError(nxt.pos, [ ...
                'This ''-'' starts a code range, so I was hoping to find the range''s ' ...
                'high bound after it -- for example 21-30. Would you check what comes ' ...
                'next?']);
        end
        hiVal = after.val;
        step = 3;
    else
        return;                                  % a single code, not a range
    end

    loVal = lo.val;
    if mod(loVal, 1) ~= 0 || mod(hiVal, 1) ~= 0
        DefineBinsEngine.throwParseError(lo.pos, sprintf([ ...
            'A code range needs whole numbers for its bounds, I''m afraid, but this ' ...
            'one reads %g-%g. Would you check it?'], loVal, hiVal));
    end
    if hiVal < loVal
        DefineBinsEngine.throwParseError(lo.pos, sprintf([ ...
            'This code range runs backwards (%d-%d), so it covers nothing. Would you ' ...
            'mean %d-%d?'], loVal, hiVal, hiVal, loVal));
    end
    % A guard rather than a limit anyone should reach: a mistyped range like
    % 1-100000 would otherwise build a hundred thousand code literals and
    % look like a hang.
    if hiVal - loVal > 1000
        DefineBinsEngine.throwParseError(lo.pos, sprintf([ ...
            'This code range covers %d codes (%d-%d), which is almost certainly not ' ...
            'what was meant -- a range is expanded to every code inside it. Would you ' ...
            'check the bounds?'], hiVal - loVal + 1, loVal, hiVal));
    end

    codes = string(arrayfun(@(v) sprintf('%d', v), loVal:hiVal, 'UniformOutput', false));
    k = k + step;
end
