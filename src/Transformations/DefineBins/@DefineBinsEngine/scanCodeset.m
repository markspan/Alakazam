function [node, k] = scanCodeset(T, k, aliases)
%SCANCODESET  Standalone codeset scanner, shared by the expression parser
%   and 'let'. Expands identifiers (alias references) to their expression
%   node, which may itself be compound (not/and/or) rather than a flat code
%   list. Returns a node (op 'anchor', with the common case a flat .codes
%   list; or 'not'/'and'/'or' when an alias expands to a combination) and
%   the next cursor.
%#ok<*AGROW>
    o = DefineBinsEngine.tokAt(T, k);
    if o.kind == "punc" && o.val == "{"
        openPos = o.pos;
        k = k + 1;
        kids = {};
        while ~(DefineBinsEngine.tokAt(T, k).kind == "punc" && DefineBinsEngine.tokAt(T, k).val == "}")
            if DefineBinsEngine.tokAt(T, k).kind == "eof"
                DefineBinsEngine.throwParseError(openPos, [ ...
                    'This ''{'' code list never closes, I''m afraid -- I read all the ' ...
                    'way to the end of the script looking for its matching ''}''. Would ' ...
                    'you check for a missing closing brace, e.g. {"s11" "s22" "s33"}?']);
            end
            if DefineBinsEngine.tokAt(T, k).kind == "punc" && DefineBinsEngine.tokAt(T, k).val == ","
                k = k + 1; continue;                       % optional separators
            end
            [c, k] = DefineBinsEngine.scanCodeElem(T, k, aliases);
            kids{end + 1} = c;
        end
        k = k + 1;                                          % consume '}'
        if isempty(kids)
            DefineBinsEngine.throwParseError(openPos, [ ...
                'This ''{}'' code list is empty, I''m afraid -- it needs at least one ' ...
                'code inside, for example {112 122} or {"s11" "s22"}. You could remove ' ...
                'it entirely if you meant to leave this out.']);
        end
        node = DefineBinsEngine.combineOr(kids);
    else
        [first, k] = DefineBinsEngine.scanCodeElem(T, k, aliases);
        kids = {first};
        while DefineBinsEngine.tokAt(T, k).kind == "punc" && DefineBinsEngine.tokAt(T, k).val == "|"
            k = k + 1;
            [c, k] = DefineBinsEngine.scanCodeElem(T, k, aliases);
            kids{end + 1} = c;
        end
        node = DefineBinsEngine.combineOr(kids);
    end
end
