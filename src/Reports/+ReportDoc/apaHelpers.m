function lines = apaHelpers()
%APAHELPERS  The shared R helpers every Alakazam report defines: the APA
%   formatters apa_p, apa_num and apa_gt, and the figure look (alz_theme,
%   alz_theme_map and the palette), as R source lines.
%
%   WHY THIS IS ONE COPY NOW. It used to be three, one per report
%   generator, and they had already drifted: apa_gt formatted decimal
%   columns to three places in the statistical and cluster reports and to
%   two in the data-quality report, undocumented, so the same table rounded
%   differently depending on which report you had opened. The explanatory
%   comment below survived in only one of the three. Nothing had gone wrong
%   yet that anyone had noticed, which is the point: a duplicated helper
%   does not announce the moment it stops being duplicated.
%
%   THREE DECIMALS is the settled figure -- it is what two of the three
%   copies used, and what the surviving comment already described as the
%   intent ("0 decimals, not 3"). The data-quality report's tables move
%   from two places to three.
%
%   Not shared here: apa_bf (Bayes factors) and violin_layers, which only
%   the statistical report uses, and which it still defines itself. A
%   helper used once belongs where it is used.
%
%   ONE THEME, FOR THE SAME REASON. The plots had drifted the way apa_gt
%   had: theme_minimal in twenty-one places, theme_pubr in ten, and base
%   sizes of 9, 10 and 11 scattered between them, so figures a page apart
%   in one document had different axis weights and different type sizes.
%   Three near-identical reds (#c1272d, #c0392b, #d0454a) and two blues
%   were in use for the same roles. A reader reads that as carelessness
%   before they read anything else.
%
%   TWO THEMES, NOT ONE, because a grid helps a line plot and hurts a
%   heatmap: alz_theme for data plots, alz_theme_map for rasters and
%   topographies, differing only in the panel grid and the legend.
%
%   THE R ITSELF IS rscripts/apa-helpers.R, read and inlined here: it is a
%   library of R functions with nothing for MATLAB to decide, so it belongs
%   in a file an R editor understands rather than in string literals. See
%   ReportDoc.template for why the R is inlined rather than sourced.
%
%   See also REPORTDOC.TEMPLATE, REPORTDOC.YAMLHEADER, REPORTDOC.PACKAGEBOOTSTRAP.
    lines = ReportDoc.template('apa-helpers.R');
end
