function lines = yamlHeader(title)
%YAMLHEADER  The Quarto front matter every Alakazam report shares.
%   LINES = ReportDoc.yamlHeader(TITLE) returns the '---' ... '---' block as
%   a cellstr, with TITLE as the document title and everything else fixed.
%
%   Self-contained HTML so a report can be emailed as one file, and a table
%   of contents because every one of these is long enough to need it.
%
%   THE LIGHT-MODE OVERRIDE IS NOT COSMETIC. Quarto's cosmo theme follows
%   the reader's OS dark-mode setting, but the plots baked into these
%   reports are ggplot output with a white canvas and black text. On a dark
%   background the figures stay white rectangles while the prose around
%   them inverts, and axis labels sit black-on-dark. Pinning the document
%   to light keeps the page and its figures in the same world.
%
%   WHY THIS IS SHARED. Three generators used to carry their own copy of
%   this header, identical except the title, and the same was true of the
%   package bootstrap and the APA helpers. That is how apa_gt came to round
%   to three decimals in two reports and two in the third -- see
%   ReportDoc.apaHelpers, which is where that was found and fixed.
%
%   THE SCREEN-READER RULE IS NOT DECORATION. Quarto writes a callout's
%   type name into the title as <span class="screen-reader-only">Tip</span>,
%   meant to be announced and never shown, and relies on its own stylesheet
%   to hide it. Where that stylesheet does not fully apply, which includes
%   the app's own embedded viewer, the span becomes visible and butts
%   against the title: a callout titled "Nothing flagged" renders as
%   "TipNothing flagged". Restating the rule here costs six lines and makes
%   the document carry its own fix rather than depend on the viewer.
%
%   THE FIGURE SETTINGS ARE FOR PRINT, not for the screen. Quarto's default
%   is a 96 dpi PNG sized for a browser, which is soft the moment a reader
%   drops it into a manuscript or projects it. 300 dpi is the ordinary
%   print standard, and a 7 by 4.5 inch default is a single manuscript
%   column at a readable aspect. Chunks that need a taller figure still
%   override fig-height locally.
%
%   PNG RATHER THAN SVG, and the reason is not the obvious one. Measured on
%   two real reports, SVG costs 12% more on the data-quality report (2.37
%   against 2.12 MB) and 33% more on the heatmap-heavy coherence one (3.79
%   against 2.86 MB), which is a modest penalty rather than the blow-up a
%   vector heatmap suggests.
%
%   What settles it is that SVG buys less here than it appears to. The
%   device outlines every glyph: the figures contain no <text> elements and
%   reference no fonts, only <g id="glyph-..."> path definitions used by
%   reference. So the usual argument for vector figures in a manuscript,
%   that the text stays selectable and editable, does not apply, and what
%   remains is scalability alone. 300 dpi over a 7 inch default is 2100
%   pixels across, wider than a journal column needs at 600 dpi, so that
%   scalability has little left to buy either.
%
%   Anyone who does want a true vector figure has the better route already:
%   the report's own CSVs and R, which re-plot at any size in any format.
%   Switching this line to svg is a one-line change if that trade ever
%   looks different.
%
%   THE FIGURE SIZING RULE HAS THE SAME CAUSE AS THE SCREEN-READER RULE
%   above. Quarto delivers its theme as a percent-encoded data:text/css
%   link rather than as an inline style block, and that is exactly what the
%   app's embedded viewer does not apply. Bootstrap's .img-fluid, which is
%   where max-width: 100% lives, is defined in that stylesheet and nowhere
%   else, and the emitted <img> carries no width attribute of its own.
%
%   That went unnoticed while fig-dpi was Quarto's default 96, because a 7
%   inch figure was then 672 pixels across and happened to fit the pane
%   unaided. At 300 dpi it is 2100 across, so the same markup draws roughly
%   four times too wide in the app while staying correct in a browser.
%   Restating the rule inline sizes the figures in any viewer, and a
%   browser is unaffected because the value is the one the theme sets.
%
%   BOTH OF THOSE RULES ARE NOW A FALLBACK RATHER THAN THE FIX, and the
%   history is worth keeping because it shows what treating symptoms costs.
%   Each was found separately, by a reader noticing something odd in the
%   app, and each was patched separately. They had one cause. Quarto ships
%   its whole theme as a data: URI stylesheet, and the app's viewer is not
%   reading a local file at all: MATLAB serves it from its connector, whose
%   Content-Security-Policy refuses data: styles and scripts while allowing
%   data: images. So the app was rendering every report with no Bootstrap,
%   and these two rules were the only two pieces of it anyone had missed.
%
%   renderQuartoReport now inlines those resources, so the theme applies
%   and these rules only restate what it already says. They stay because
%   they cost four lines, and because a document that has not been through
%   that step still has to be readable.
%
%   See also REPORTDOC.PACKAGEBOOTSTRAP, REPORTDOC.APAHELPERS,
%   INLINEDATAURIRESOURCES.
    lines = { ...
        '---' ...
        ['title: "' title '"'] ...
        'format:' ...
        '  html:' ...
        '    self-contained: true' ...
        '    toc: true' ...
        '    theme: cosmo' ...
        '    include-in-header:' ...
        '      text: |' ...
        '        <meta name="color-scheme" content="light">' ...
        '        <style>' ...
        '          :root { color-scheme: light !important; }' ...
        '          html, body { background-color: #ffffff !important; }' ...
        '          #TOC, .sidebar, .toc-actions { background-color: #ffffff !important; }' ...
        '          .screen-reader-only, .sr-only {' ...
        '            position: absolute !important; width: 1px !important; height: 1px !important;' ...
        '            padding: 0 !important; margin: -1px !important; overflow: hidden !important;' ...
        '            clip: rect(0, 0, 0, 0) !important; white-space: nowrap !important;' ...
        '            border: 0 !important;' ...
        '          }' ...
        '          figure img, p img, img.figure-img, img.img-fluid,' ...
        '          .cell-output-display img {' ...
        '            max-width: 100% !important; height: auto !important;' ...
        '          }' ...
        '        </style>' ...
        'execute:' ...
        '  echo: false' ...
        '  warning: false' ...
        '  message: false' ...
        '  fig-format: png' ...
        '  fig-dpi: 300' ...
        '  fig-width: 7' ...
        '  fig-height: 4.5' ...
        '---'};
end
