function block = comboSectionDescriptiveOnly(windowLabel, measureType, comboLabel, recipeText)
%COMBOSECTIONDESCRIPTIVEONLY  A combination bin's own LATENCY or CIRCULAR
%   measure type (see isDescriptiveOnlyType): descriptive statistics and a
%   plot only, no one-sample-vs-zero test and no contribution to the
%   cross-group omnibus summary -- see descriptiveOnlyReason for why,
%   specific to which of the two categories MEASURETYPE falls into.
%   Clustered ACROSS every channel in one table + one faceted plot, same
%   as descriptiveSection -- see its own header comment for why.
%
%   A CIRCULAR measure gets circular statistics (circularStatsLines) and no
%   plot, as the ordinary bins of the same measure do in circularSection. It
%   used to get a linear mean and SD and a violin on a linear axis, directly
%   under the sentence saying that linear statistics are not valid for it.
    if ReportSections.isCircularType(measureType)
        summaryLines = [{ ...
            'd <- grp %>% filter(!is.na(value)) %>% droplevels()' ...
            'if (nrow(d) == 0) {' ...
            '  cat("\n*No usable values for this combination bin.*\n\n")' ...
            '} else {'}, ...
            ReportSections.circularStatsLines(), ...
            {'}'}];
    else
        summaryLines = linearSummaryLines();
    end
    lines = ReportDoc.lines([{ ...
        ReportDoc.template('combo-descriptive-heading.qmd') ...
        ''}, ...
        summaryLines, ...
        {'```' ...
        ''}]);
    text = strjoin(lines, newline);
    text = ReportSections.fillToken(text, 'COMBOLABEL', comboLabel);
    text = ReportSections.fillToken(text, 'RECIPE', recipeText);
    text = ReportSections.fillToken(text, 'REASON', ReportSections.descriptiveOnlyReason(measureType));
    text = strrep(text, '__CHUNKLABEL__', ReportSections.chunkLabel('combo-desc', windowLabel, measureType, comboLabel));
    text = strrep(text, '__YLABEL__', ReportSections.yAxisLabel(measureType));
    text = strrep(text, '__BLOCKMATCHDIAGNOSTIC__', ReportSections.blockMatchDiagnosticText());
    block = ReportSections.fillCommonTokens(text, windowLabel, measureType, '', '');
end

function lines = linearSummaryLines()
%LINEARSUMMARYLINES  Mean, SD and n per channel, and a faceted violin: a latency.
    lines = ReportDoc.template('combo-descriptive-stats.R');
end
