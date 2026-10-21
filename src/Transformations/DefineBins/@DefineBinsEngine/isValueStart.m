function tf = isValueStart(T, k, aliases)
%ISVALUESTART  Whether the token at K begins a value test (scanValueTest):
%   the keyword rt, or the plain word field, or log( or rank(. A plain word
%   that names a let alias is the alias, so a script with an alias called
%   field, log or rank keeps meaning what it meant.
    t = DefineBinsEngine.tokAt(T, k);
    tf = t.kind == "kw" && t.val == "rt";
    if tf || t.kind ~= "ident" || isfield(aliases, char(t.val))
        return;
    end
    word = lower(char(t.val));
    if strcmp(word, 'field')
        tf = true;
    elseif any(strcmp(word, {'log', 'rank'}))
        next = DefineBinsEngine.tokAt(T, k + 1);
        tf = next.kind == "punc" && next.val == "(";
    end
end
