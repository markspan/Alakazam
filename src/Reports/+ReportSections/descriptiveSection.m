function block = descriptiveSection(windowLabel, measureType, binLabel)
%DESCRIPTIVESECTION  Exactly one ordinary bin: nothing to compare, so just
%   a descriptive-statistics table and a plot, both clustered ACROSS every
%   channel in this window/measure block rather than repeated once per
%   channel -- a report with a 32-channel montage used to print thirty-two
%   near-identical "### Cz" / "### Fz" / ... subsections, one descriptives
%   table apiece, which is the same information as one table with a
%   Channel column and is harder to scan that way, not easier. No test
%   here (nothing to compare), so there is nothing that can fail
%   per-channel the way a statistical test can -- the channel grouping is
%   one vectorised summarise(), not a loop with its own tryCatch.
    lines = ReportDoc.template('descriptive-section.qmd');
    text = strjoin(lines, newline);
    text = strrep(text, '__CHUNKLABEL__', ReportSections.chunkLabel('desc', windowLabel, measureType));
    text = strrep(text, '__YLABEL__', ReportSections.yAxisLabel(measureType));
    text = strrep(text, '__BLOCKMATCHDIAGNOSTIC__', ReportSections.blockMatchDiagnosticText());
    block = ReportSections.fillCommonTokens(text, windowLabel, measureType, binLabel, '');
end
