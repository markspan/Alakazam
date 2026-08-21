function colorbarWrap = AddSharedColorbar(grid, rowSpec, col, cmap, climRange, labelText)
%ADDSHAREDCOLORBAR  One shared colorbar, centred in a dedicated GRID cell
%   (ROWSPEC/COL, either a scalar Layout.Row/Column or a [start, end] span)
%   rather than attached directly to one of a view's real tiles/axes:
%   confirmed directly, repeatedly, across every view that needed this,
%   that colorbar(realAxes) shrinks that axes' InnerPosition to make room
%   for it -- visibly worse when every sibling tile/axes needs to stay the
%   same size, or (as in ScalpDistributionView/Brain3DView, which force
%   axis 'square'/'equal') when narrowing also shrinks the axes' height,
%   making it noticeably smaller than it should be. A dedicated hidden
%   axes sidesteps that entirely: every real axes' own InnerPosition stays
%   unaffected by the colorbar's presence.
%
%   The hidden axes/colorbar itself sits in the MIDDLE column of a nested
%   [1x, InnerColorbarPx, 1x] sub-grid, not spanning GRID's own cell
%   directly: TransTools.ColorbarColumnWidth reserves a generous column so
%   the label (see below) never clips, but the colorbar itself does not
%   grow to fill that whole width -- left unpadded it renders hard against
%   one edge with a wide dead strip of empty space on the other, reported
%   directly as looking off-centre. Centring it in a narrower, fixed-width
%   middle column, flanked by two equal flexible columns, fixes that
%   regardless of how wide the caller's own reserved column is.
%
%   Returns COLORBARWRAP, the nested sub-grid (NOT the inner axes) --
%   deleting it deletes the axes/colorbar inside it too, so a caller whose
%   colour scale/label can change later (Brain3DView's own Source-estimate
%   vs. Scalp-projection modes) can delete() and rebuild the whole thing
%   with one handle, the same as when this returned the bare axes; if it
%   returned the inner axes instead, delete()-ing just that would leave
%   this wrapper behind as an empty, orphaned sub-grid on every rebuild.
%   Most callers ignore the return value (a colorbar built once at
%   construction and never touched again).
%
%   CMAP must be the SAME colormap the real tiles/axes themselves use, or
%   the colorbar shows MATLAB's default (parula) gradient instead of a
%   scale matching what is actually drawn. CLIMRANGE is a [lo, hi] pair.
%   LABELTEXT is the colorbar's own axis label (e.g. "Amplitude (\muV)").
%
%   Previously reimplemented, identically apart from these six parameters,
%   in EpochView.m, TimeFrequencyView.m, CoherenceView.m,
%   ScalpDistributionView.m, Brain3DView.m and CoherenceTopographyView.m
%   (which had already drifted to a differently-named local variable, `cax`
%   instead of `colorbarAxes`) -- consolidated here so the six copies
%   cannot drift further out of sync with each other. Note the OUTER
%   column width is still each caller's own concern, not this helper's --
%   use TransTools.ColorbarColumnWidth for that (see its own header
%   comment: a too-narrow column clips the colorbar's own Label, silently,
%   since a grid cell just crops whatever overflows it rather than
%   erroring).
    InnerColorbarPx = 120;   % wide enough for the bar + tick numbers + the (FontSize 12) label; centred within the caller's own, wider reserved column

    colorbarWrap = uigridlayout(grid, [1, 3], ...
        'ColumnWidth', {'1x', InnerColorbarPx, '1x'}, 'Padding', [0 0 0 0], 'ColumnSpacing', 0);
    colorbarWrap.Layout.Row = rowSpec;
    colorbarWrap.Layout.Column = col;

    colorbarAxes = uiaxes(colorbarWrap);
    colorbarAxes.Layout.Row = 1;
    colorbarAxes.Layout.Column = 2;
    colorbarAxes.Visible = "off";
    colormap(colorbarAxes, cmap);
    colorbarAxes.CLim = climRange;
    cb = colorbar(colorbarAxes);
    cb.Label.String = labelText;
    cb.Label.FontSize = 12;   % larger than uiaxes' own default (~10pt) for readability -- 20, then 14, were tried first and reported too big/didn't fit
end
