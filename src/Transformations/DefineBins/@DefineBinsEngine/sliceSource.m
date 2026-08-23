function txt = sliceSource(script, stmt)
%SLICESOURCE  The original source text spanned by a token subarray, so a
%   bin's own .text can be stored verbatim rather than reconstructed.
    if isempty(stmt); txt = ''; return; end
    a = stmt(1).pos;
    b = stmt(end).pos + stmt(end).len - 1;
    txt = script(a:min(b, numel(script)));
end
