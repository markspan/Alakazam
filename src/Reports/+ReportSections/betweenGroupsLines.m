function lines = betweenGroupsLines(includeBetweenGroups)
%BETWEENGROUPSLINES  The actually-new comparison comboSectionGrouped adds:
%   an independent-samples test of the combo score BETWEEN groups --
%   spliced in when INCLUDEBETWEENGROUPS, {} (no-op) otherwise. Mirrors
%   betweenSection's own 2-group-t-test/3+-group-one-way-ANOVA split
%   (including its own normality gating for the 2-group case), just on a
%   combination bin's already-differenced score instead of an ordinary
%   bin's raw one.
%
%   Appends its result, tagged with the current channel, to the CALLER's
%   betweenRes2_list/betweenAnova_list/betweenPw_list rather than printing
%   anything itself -- see vsZeroLines' own header comment for why.
    if ~includeBetweenGroups
        lines = {};
        return;
    end
    lines = ReportDoc.template('between-groups.R');
end
