function c = asCell(v)
%ASCELL  V as a cellstr: {} for empty, {v} for a single char/string, V
%   itself otherwise -- normalises a stored seed field that may have been
%   saved as a bare char (a single selection) rather than a cellstr.
%
%   Previously reimplemented, identically, in ReRefDialog.m,
%   InterpolateDialog.m and SelectDataDialog.m; consolidated here.
    if isempty(v); c = {}; elseif ischar(v); c = {v}; else; c = v; end
end
