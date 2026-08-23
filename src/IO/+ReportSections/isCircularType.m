function tf = isCircularType(measureType)
%ISCIRCULARTYPE  True for the subset of isDescriptiveOnlyType's own types
%   that are circular specifically (phase, phaselag), not just
%   descriptive-only for the UNRELATED "no meaningful zero" latency
%   reason. The distinction matters once a between-subjects group is
%   assigned (see comboSectionGrouped): a latency has no natural zero to
%   test AGAINST (isDescriptiveOnlyType's own concern), but it is still an
%   ordinary linear quantity, so comparing it BETWEEN groups is perfectly
%   valid -- unlike a circular quantity, for which no linear comparison
%   (one-sample OR between-groups) is valid at all.
    tf = any(strcmp(measureType, {'phase', 'phaselag'}));
end

