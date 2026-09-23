function lines = vsZeroLines(includeVsZero)
%VSZEROLINES  The per-group one-sample-vs-zero test, spliced into
%   comboSectionGrouped's own per-channel loop when INCLUDEVSZERO -- {}
%   (no-op) otherwise. Each group is tested with a t-test, or -- when that
%   group's own values depart from normality -- a Wilcoxon signed-rank
%   test instead; picked independently per group, since one group's
%   distribution says nothing about another's.
%
%   Appends its result (one row per group, tagged with the current
%   channel) to the CALLER's vszero_list[[ch]] rather than printing
%   anything itself: comboSectionGrouped accumulates this across every
%   channel in the block and prints one combined table, not one per
%   channel -- see pairedSection's own header comment for why.
    if ~includeVsZero
        lines = {};
        return;
    end
    lines = ReportDoc.template('vs-zero.R');
end
