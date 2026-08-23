function t = tokAt(T, k)
%TOKAT  Token at index K, or a synthetic 'eof' token past the end.
    if k >= 1 && k <= numel(T); t = T(k);
    else; t = struct('kind', "eof", 'val', "", 'pos', -1, 'len', 0); end
end
