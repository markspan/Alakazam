function text = sourceEstimateSection(assets)
%SOURCEESTIMATESECTION  The "Source Estimate (Exploratory)" section: a
%   fit-quality table plus a tabbed brain-image panel per bin, built
%   entirely from generateSourceEstimateReportAssets' own pre-rendered
%   PNGs and pre-computed statistics.
%
%   PURE MARKDOWN, NO R CODE CHUNK -- unlike every other section this
%   package builds. Everything shown here (the images, the fit
%   percentages) was already computed in MATLAB before this .qmd text was
%   assembled: there is no per-subject row for R to run a test over, so
%   there is nothing for a code chunk to compute. This keeps the whole
%   feature independent of R/Quarto's own ability to run MATLAB or
%   FieldTrip, which it cannot.
%
%   ASSETS is generateSourceEstimateReportAssets' own return value: one
%   row per (bin, method), in bin order then method order within a bin.
%   Grouped here by BinLabel, preserving that arrival order, into one
%   subsection per bin: a small fit-percentage table across its methods,
%   then a tabbed image panel (Quarto's own {.panel-tabset} div, valid in
%   the self-contained HTML output this pipeline always renders to --
%   see generateQuartoReport's own header). Returns '' for an empty
%   ASSETS (no grand average in this export, or FieldTrip unavailable),
%   so generateQuartoReport can splice this in unconditionally without
%   its own empty-vs-absent branch.
%
%   THE SAME CAVEATS AS BRAIN3DVIEW'S OWN TOOLTIP ARE RESTATED HERE,
%   rather than assumed carried over from the interactive view: a report
%   reader may never have opened Brain3DView at all. This repeats,
%   deliberately, that these are grand-average, TEMPLATE-head-model
%   estimates, that the methods are on different scales from each other
%   and from a scalp-voltage topography, and that "fit" is a forward-
%   model/registration check, not an anatomical-accuracy one -- see
%   TransTools.InverseSolution's own INFO.ResidualVariance comment for
%   the full reasoning this paragraph is a report-facing summary of.
%
%   THE IMAGE LINK DESTINATION IS WRAPPED IN <...> (CommonMark/Pandoc's
%   own escape for a link destination containing spaces or parentheses):
%   ImagePath is built from the analyst's own chosen export file name
%   (e.g. "measurements (final).csv" -> a "measurements (final)_..._images"
%   folder), which is not guaranteed to be safe as a bare, unescaped
%   Markdown link target -- an unescaped ")" inside one would close the
%   link early and silently break the image.
%
%   See also GENERATESOURCEESTIMATEREPORTASSETS, GENERATEQUARTOREPORT.
    if isempty(assets)
        text = '';
        return;
    end

    lines = { ...
        '## Source Estimate (Exploratory)' ...
        '' ...
        ['*Grand-average source estimates, from FieldTrip''s TEMPLATE head model and ' ...
         'electrode positions -- not a per-subject MRI or digitised cap. A genuine inverse ' ...
         'computation, more physiologically grounded than a scalp-voltage topography, but ' ...
         'still an approximation, not a validated per-subject localization. The methods ' ...
         'below are on DIFFERENT SCALES from each other and from scalp microvolts, so their ' ...
         'colours are not directly comparable. "Fit" is the percentage of the scalp data''s ' ...
         'own variance an estimate reproduces when projected back through the same forward ' ...
         'model -- a check on electrode registration, not on whether any one highlighted ' ...
         'region is anatomically correct; an unusually deep or medial highlight can sit ' ...
         'alongside an excellent fit.*'] ...
        ''};

    binLabels = unique({assets.BinLabel}, 'stable');
    for b = 1:numel(binLabels)
        binLabel = binLabels{b};
        rows = assets(strcmp({assets.BinLabel}, binLabel));

        lines = [lines, { ...
            sprintf('### %s', ReportSections.mdLit(binLabel)) ...
            '' ...
            '| Method | Fit (variance explained) | Rendered at |' ...
            '| --- | --- | --- |'}]; %#ok<AGROW>
        for r = 1:numel(rows)
            % "n/a" rather than a number for sLORETA, which reports no
            % residual variance (NaN): its filter output is a standardized
            % statistic, not a current, so projecting it back through the
            % leadfield is not a meaningful operation -- see
            % TransTools.InverseSolution's own comment. A cell reading
            % "NaN%" would look like a failed computation rather than a
            % quantity that does not apply.
            if isnan(rows(r).ResidualVariance)
                fitCell = 'n/a';
            else
                fitCell = sprintf('%.0f%%', 100 * (1 - rows(r).ResidualVariance));
            end
            lines{end + 1} = sprintf('| %s | %s | %.0f ms |', ...
                ReportSections.mdLit(rows(r).MethodLabel), ...
                fitCell, rows(r).InstantMs); %#ok<AGROW>
        end

        lines = [lines, {'', '::: {.panel-tabset}'}]; %#ok<AGROW>
        for r = 1:numel(rows)
            lines = [lines, { ...
                sprintf('#### %s', ReportSections.mdLit(rows(r).MethodLabel)) ...
                '' ...
                sprintf('![%s source estimate, %s](<%s>)', ...
                    ReportSections.mdLit(rows(r).MethodLabel), ReportSections.mdLit(binLabel), ...
                    rows(r).ImagePath) ...
                ''}]; %#ok<AGROW>
        end
        lines = [lines, {':::', ''}]; %#ok<AGROW>
    end

    text = char(strjoin(lines, newline));
end
