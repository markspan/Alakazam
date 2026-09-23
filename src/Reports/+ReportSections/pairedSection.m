function block = pairedSection(windowLabel, measureType, bin1, bin2)
%PAIREDSECTION  Exactly two ordinary bins: a paired t-test, or -- when the
%   within-subject differences depart from normality -- a Wilcoxon
%   signed-rank test instead. Shapiro-Wilk decides which one is reported;
%   only one test is ever shown, not both plus a Bayes factor.
%
%   CLUSTERED ACROSS CHANNELS: one descriptives table, one results table
%   and one faceted plot for the whole window/measure block, not one of
%   each repeated under a "### <channel>" heading per channel -- a
%   32-channel montage used to print thirty-two near-identical
%   subsections, which is the same numbers as a Channel column and harder
%   to scan that way. Each channel's own test still runs inside its own
%   tryCatch (a statistical edge case can still fail on one channel and
%   not others), but a failure becomes a row saying so in the results
%   table rather than its own heading.
    lines = ReportDoc.lines({ ...
        ReportDoc.template('paired-section.qmd') ...
        ['  caption_txt <- if (length(tests_used) == 0) "" else' ...
         ' if (all(tests_used == "Paired t-test")) "__CAPTION_PARAM__" else' ...
         ' if (all(tests_used == "Wilcoxon signed-rank")) "__CAPTION_WILCOX__" else' ...
         ' paste("__CAPTION_PARAM__", "__CAPTION_WILCOX__")'] ...
        '  if (nzchar(caption_txt)) cat(sprintf("\n*%s*\n\n", caption_txt))' ...
        '}' ...
        '```' ...
        });
    text = strjoin(lines, newline);
    text = strrep(text, '__CHUNKLABEL__', ReportSections.chunkLabel('paired', windowLabel, measureType));
    text = strrep(text, '__YLABEL__', ReportSections.yAxisLabel(measureType));
    text = strrep(text, '__BLOCKMATCHDIAGNOSTIC__', ReportSections.blockMatchDiagnosticText());
    text = strrep(text, '__CAPTION_PARAM__', ReportSections.rLit(ReportSections.testCaption('paired_t')));
    text = strrep(text, '__CAPTION_WILCOX__', ReportSections.rLit(ReportSections.testCaption('wilcoxon_signed_rank')));
    block = ReportSections.fillCommonTokens(text, windowLabel, measureType, bin1, bin2);
end
