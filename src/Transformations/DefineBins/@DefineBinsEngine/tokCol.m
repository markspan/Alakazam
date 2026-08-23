function c = tokCol(toks)
%TOKCOL  The source column of the first token in TOKS, or -1 if empty.
    if isempty(toks); c = -1; else; c = toks(1).pos; end
end
