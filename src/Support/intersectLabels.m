function v = intersectLabels(all, want)
%INTERSECTLABELS  The entries of ALL that also appear in WANT, in ALL's own
%   order (a stored channel-label seed, filtered down to labels the
%   current dataset actually has). Always {} (never a 1x0/0x1 shape) when
%   nothing matches.
%
%   Previously reimplemented, identically, in ReRefDialog.m and
%   InterpolateDialog.m, and near-identically (one extra, logically
%   inert `&& ~isempty(all)` condition -- WANT already empty-shapes V the
%   same way regardless) in SelectDataDialog.m; consolidated here.
    v = all(ismember(all, want));
    if isempty(v); v = {}; end
end
