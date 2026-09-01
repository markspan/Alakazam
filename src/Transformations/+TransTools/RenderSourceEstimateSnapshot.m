function info = RenderSourceEstimateSnapshot(values, times, leadfield, elec, headmodel, sourcemodel, method, pngPath)
%RENDERSOURCEESTIMATESNAPSHOT  Solve METHOD's inverse for one bin's full
%   time course, render it at that bin's global-field-power peak onto an
%   offscreen figure, and save the result to PNGPATH -- the batch/report
%   counterpart of Brain3DView's own interactive redraw(), reusing the
%   EXACT same drawing code (TransTools.DrawSourceMap, which itself calls
%   TransTools.DrawBrainPatch) so a report snapshot can never look
%   different from what the interactive view would show for the same
%   bin/method/instant.
%
%   VALUES is nChan x nTime, already reordered to LEADFIELD's own
%   RESOLVEDLABELS order -- see TransTools.BuildSourceForwardModel's own
%   header comment for why that reordering is the CALLER'S job, not
%   this function's (the same contract TransTools.InverseSolution has).
%   TIMES is the matching 1 x nTime vector of sample latencies in ms,
%   used only to report which instant was actually rendered.
%
%   THE RENDERED INSTANT is this bin's own global-field-power peak: the
%   sample where sqrt(mean(values.^2, 1)) is largest across the WHOLE
%   time course given. This is a standard, measure-agnostic convention
%   for "the moment of peak scalp activity" that does not depend on
%   which (if any) Measure windows this bin happens to have defined --
%   a Peak window, a Mean Amplitude window and an unmeasured bin all get
%   a sensible instant chosen the same way, rather than three different
%   special cases.
%
%   METHOD is 'mne' | 'eloreta' | 'sloreta', passed straight through to
%   TransTools.InverseSolution with the default 'magnitude' orientation
%   (matching Brain3DView's own default, and what its 3-D view shows
%   unless Signed is ticked) -- a report snapshot deliberately does not
%   expose the Signed option, keeping one image per bin/method instead
%   of two.
%
%   INFO is TransTools.InverseSolution's own INFO struct (.Method,
%   .ScaleLabel, .ScaleNote, .ResidualVariance -- see its header) with
%   one field added here, INFO.InstantMs, the rendered latency.
%
%   RESIDUALVARIANCE IN INFO IS FOR THE WHOLE BIN, NOT JUST THE RENDERED
%   INSTANT: InverseSolution computes it over the entire VALUES matrix
%   handed to it, so the number reported alongside a report snapshot is
%   exactly the number Brain3DView's own axes title would show for that
%   bin/method -- the image just cannot show every instant at once; the
%   fit statistic already summarises across all of them.
%
%   See also TRANSTOOLS.INVERSESOLUTION, TRANSTOOLS.DRAWSOURCEMAP,
%   TRANSTOOLS.BUILDSOURCEFORWARDMODEL, GENERATESOURCEESTIMATEREPORTASSETS.
    [sourcePower, info] = TransTools.InverseSolution(values, leadfield, elec, headmodel, method);

    gfp = sqrt(mean(double(values) .^ 2, 1));
    [~, peakIdx] = max(gfp);
    info.InstantMs = times(peakIdx);

    mapLimit = max(abs(sourcePower(:)), [], 'omitnan');
    if ~isfinite(mapLimit) || mapLimit == 0
        mapLimit = 1;
    end

    % A plain figure/axes, not a uifigure/uiaxes: this figure is never
    % shown, so App Designer's interactive component (needed elsewhere for
    % rotation/callbacks) buys nothing here, only extra weight.
    % 'HandleVisibility','off' keeps a batch run generating many of these
    % in a row from ever becoming gcf/findall-reachable by anything else
    % that might be running (report generation is a background export
    % step, not a modal one). onCleanup guarantees the figure is closed
    % even if exportgraphics itself throws (a bad path, an unwritable
    % folder), so a failed report never leaves stray offscreen figures
    % accumulating in the caller's session.
    fig = figure('Visible', 'off', 'HandleVisibility', 'off', 'Color', 'white');
    closeFig = onCleanup(@() close(fig)); %#ok<NASGU>
    ax = axes('Parent', fig);

    TransTools.DrawSourceMap(ax, sourcePower(:, peakIdx), sourcemodel, mapLimit, [], false);
    exportgraphics(ax, pngPath, 'Resolution', 150, 'BackgroundColor', 'white');
end
