function block = comboSection(windowLabel, measureType, comboLabel, recipeText)
%COMBOSECTION  One combination (difference) bin. For most measure types: a
%   one-sample t-test against zero -- or, when the values depart from
%   normality, a Wilcoxon signed-rank test against zero instead. Run
%   entirely separately from the omnibus test above, never as one more
%   level within it (see this file's own header comment for why that would
%   be statistically invalid). For a LATENCY or CIRCULAR measure type (see
%   isDescriptiveOnlyType): descriptive statistics only, no test.
%
%   CLUSTERED ACROSS CHANNELS -- see pairedSection's own header comment for
%   why: one descriptives table, one results table and one faceted plot
%   for the whole block, not one of each per channel.
    if ReportSections.isDescriptiveOnlyType(measureType)
        block = ReportSections.comboSectionDescriptiveOnly(windowLabel, measureType, comboLabel, recipeText);
        return;
    end
    lines = ReportDoc.lines({ ...
        '## __WINDOW_MD__ -- __MEASURETYPE_MD__: __COMBOLABEL_MD__' ...
        '' ...
        ... % Not "its scores are a linear combination of the other bins' scores": that
        ... % holds for a mean amplitude, but a peak measured on a difference wave is not
        ... % the difference of the two peaks.
        ReportDoc.template('combo-section.qmd') ...
        ['  caption_txt <- if (length(tests_used) == 0) "" else' ...
         ' if (all(tests_used == "One-sample t-test")) "__CAPTION_PARAM__" else' ...
         ' if (all(tests_used == "Wilcoxon signed-rank")) "__CAPTION_WILCOX__" else' ...
         ' paste("__CAPTION_PARAM__", "__CAPTION_WILCOX__")'] ...
        '  if (nzchar(caption_txt)) cat(sprintf("\n*%s*\n\n", caption_txt))' ...
        '}' ...
        '```' ...
        });
    text = strjoin(lines, newline);
    text = ReportSections.fillToken(text, 'COMBOLABEL', comboLabel);
    text = ReportSections.fillToken(text, 'RECIPE', recipeText);
    text = strrep(text, '__CHUNKLABEL__', ReportSections.chunkLabel('combo', windowLabel, measureType, comboLabel));
    text = strrep(text, '__YLABEL__', ReportSections.yAxisLabel(measureType));
    text = strrep(text, '__BLOCKMATCHDIAGNOSTIC__', ReportSections.blockMatchDiagnosticText());
    text = strrep(text, '__CAPTION_PARAM__', ReportSections.rLit(ReportSections.testCaption('one_sample_t')));
    text = strrep(text, '__CAPTION_WILCOX__', ReportSections.rLit(ReportSections.testCaption('wilcoxon_signed_rank_one_sample')));
    block = ReportSections.fillCommonTokens(text, windowLabel, measureType, '', '');
end
