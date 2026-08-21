function v = firstNonEmpty(a, b)
%FIRSTNONEMPTY  A if non-empty, else B.
%
%   Previously reimplemented, identically, in erpsetToAveraged.m and
%   averagedToErpset.m; consolidated here.
    if ~isempty(a); v = a; else; v = b; end
end
