function block = betweenSection(windowLabel, measureType, binLabel)
%BETWEENSECTION  Exactly one ordinary bin, but a between-subjects group is
%   assigned (see WorkSpace.editSubjects/distinctGroups) -- so, unlike
%   descriptiveSection's own single-bin, no-comparison-possible case,
%   there IS a comparison here: independent-samples across groups.
%   n_distinct(d$group) is checked PER CHANNEL at R runtime, not decided
%   once in MATLAB (unlike ordinaryLabels/comboBins), since it can
%   legitimately vary channel to channel once NA values are dropped -- a
%   Welch two-sample *t*-test (2 groups, or a Mann-Whitney U when the data
%   depart from normality), or a Welch one-way ANOVA + Games-Howell
%   post-hoc (3+ groups), mirroring pairedSection/lmmSection's own split
%   for the WITHIN-subjects case one bin count up.
%
%   CLUSTERED ACROSS CHANNELS -- see pairedSection's own header comment.
%   A channel's own 2-group-vs-3+-group branch is still decided at R
%   runtime from that channel's own data, so two separate result tables
%   (2-group; 3+-group ANOVA + its own pairwise table) are accumulated and
%   only the ones that end up with any rows are printed -- almost always
%   just one of the two, since every channel in one window/measure block
%   ordinarily has the same number of groups.
    lines = ReportDoc.lines({ ...
        ReportDoc.template('between-section.qmd') ...
        ['  caption_txt <- if (length(tests_used) == 0) "" else' ...
         ' if (all(tests_used == "Welch two-sample t-test")) "__CAPTION_WELCH_T__" else' ...
         ' if (all(tests_used == "Mann-Whitney U")) "__CAPTION_MANN_WHITNEY__" else' ...
         ' paste("__CAPTION_WELCH_T__", "__CAPTION_MANN_WHITNEY__")'] ...
        ReportDoc.template('between-anova-table.qmd') ...
        });
    text = strjoin(lines, newline);
    text = strrep(text, '__CHUNKLABEL__', ReportSections.chunkLabel('between', windowLabel, measureType));
    text = strrep(text, '__YLABEL__', ReportSections.yAxisLabel(measureType));
    text = strrep(text, '__BLOCKMATCHDIAGNOSTIC__', ReportSections.blockMatchDiagnosticText());
    text = strrep(text, '__CAPTION_WELCH_T__', ReportSections.rLit(ReportSections.testCaption('welch_t')));
    text = strrep(text, '__CAPTION_MANN_WHITNEY__', ReportSections.rLit(ReportSections.testCaption('mann_whitney')));
    text = strrep(text, '__CAPTION_WELCH_ANOVA__', ReportSections.rLit(ReportSections.testCaption('welch_anova')));
    text = strrep(text, '__CAPTION_GAMES_HOWELL__', ReportSections.rLit(ReportSections.testCaption('games_howell')));
    block = ReportSections.fillCommonTokens(text, windowLabel, measureType, binLabel, '');
end
