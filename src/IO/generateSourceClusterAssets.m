function assets = generateSourceClusterAssets(summary, imagesDir, opts)
%GENERATESOURCECLUSTERASSETS  Rendered figures and readable descriptions for
%   the clusters a source cluster test found.
%
%   ASSETS = generateSourceClusterAssets(SUMMARY, IMAGESDIR, OPTS) takes
%   SourceClusterStats' own return value and produces, per cluster, the two
%   pictures and the one sentence a reader needs.
%
%   OPTS fields, all optional:
%     SignificantOnly  render only clusters below alpha (default true)
%     Atlas            atlas used to name locations     (default 'aal')
%     MaxClusters      cap on how many are rendered     (default 8)
%
%   ASSETS is a struct array, one row per rendered cluster:
%     .Index .Sign .PValue .Significant .TimeRangeMs .NVertices
%     .SourceIndex     which summary.clusters row this was rendered from
%     .Description     TransTools.DescribeCluster's own struct
%     .MapPath         cortical map of the cluster, relative to the .qmd
%     .TimeCoursePath  the cluster's statistic over time, likewise
%
%   TWO PICTURES, BECAUSE A CLUSTER IS A SPACE-TIME OBJECT and neither view
%   alone shows it. The map answers "where", collapsed over the cluster's
%   own time range; the time course answers "when", collapsed over its own
%   vertices. Showing only the map invites a reader to treat a transient
%   effect as sustained, and showing only the time course loses the anatomy
%   entirely.
%
%   THE MAP IS MASKED TO THE CLUSTER, not the whole statistic. Drawing the
%   full t-map with the cluster merely outlined would show a great deal of
%   sub-threshold structure that the test makes no claim about at all, and
%   readers reliably interpret such maps as results. What is drawn is what
%   was found significant, and nothing else.
%
%   SIGNIFICANT ONLY BY DEFAULT. FieldTrip returns every candidate cluster
%   it formed, most of which are noise; rendering them all would fill a
%   report with pictures of nothing. SignificantOnly false is available for
%   inspecting a null result.
%
%   See also SOURCECLUSTERSTATS, GENERATESOURCECLUSTERSTATSREPORT,
%   TRANSTOOLS.DESCRIBECLUSTER, TRANSTOOLS.DRAWSOURCEMAP.
    if nargin < 3 || isempty(opts); opts = struct(); end
    significantOnly = TransTools.FieldOr(opts, 'SignificantOnly', true);
    atlasName       = TransTools.FieldOr(opts, 'Atlas', 'aal');
    maxClusters     = TransTools.FieldOr(opts, 'MaxClusters', 8);

    assets = emptyAssets();
    if isempty(summary.clusters)
        return;
    end

    % Kept as indices rather than a filtered copy, so every asset can say
    % which summary.clusters row it came from. Callers that show clusters
    % and assets side by side (the result dialog) otherwise have to guess
    % the correspondence, and guess wrong as soon as SignificantOnly drops
    % a row in the middle.
    pick = 1:numel(summary.clusters);
    if significantOnly
        pick = pick([summary.clusters.significant]);
    end
    if isempty(pick)
        return;
    end
    pick = pick(1:min(maxClusters, numel(pick)));

    if ~exist(imagesDir, 'dir')
        mkdir(imagesDir);
    end
    [~, imagesFolderName] = fileparts(imagesDir);

    for k = 1:numel(pick)
        cluster = summary.clusters(pick(k));
        [vertexMask, timeMask, statMap] = clusterMasks(summary, cluster);
        if ~any(vertexMask)
            continue;
        end

        % The peak is taken over the cluster's own points only: the largest
        % statistic anywhere in the volume may well sit outside it.
        masked = statMap;
        masked(~vertexMask, :) = 0;
        masked(:, ~timeMask) = 0;
        [~, peakLinear] = max(abs(masked(:)));
        [peakVertex, ~] = ind2sub(size(masked), peakLinear);

        description = TransTools.DescribeCluster(vertexMask, summary.sourcemodel, ...
            peakVertex, atlasName);

        stem = sprintf('cluster%d_%s', k, cluster.sign);
        mapFile  = fullfile(imagesDir, [stem '_map.png']);
        timeFile = fullfile(imagesDir, [stem '_time.png']);

        renderClusterMap(summary, vertexMask, timeMask, statMap, mapFile);
        renderClusterTimeCourse(summary, vertexMask, statMap, cluster, timeFile);

        % A CLUSTER TOUCHING THE WINDOW EDGE IS TRUNCATED BY THE ANALYSIS,
        % not by the data: its real extent may continue beyond where anyone
        % looked. Reported, because a time range that happens to equal the
        % tested window is otherwise read as a finding about onset and
        % offset when it is a finding about the window.
        edgeTolerance = median(diff(summary.times));
        touchesEdge = cluster.timeRangeMs(1) <= summary.times(1) + edgeTolerance || ...
                      cluster.timeRangeMs(2) >= summary.times(end) - edgeTolerance;

        assets(end + 1) = struct( ...
            'Index', k, 'SourceIndex', pick(k), 'Sign', cluster.sign, 'PValue', cluster.pValue, ...
            'Significant', cluster.significant, 'TimeRangeMs', cluster.timeRangeMs, ...
            'TouchesWindowEdge', touchesEdge, ...
            'NVertices', nnz(vertexMask), 'Description', description, ...
            'MapPath', sprintf('%s/%s', imagesFolderName, [stem '_map.png']), ...
            'TimeCoursePath', sprintf('%s/%s', imagesFolderName, [stem '_time.png'])); %#ok<AGROW>
    end
end

% ======================================================================= %
function [vertexMask, timeMask, statMap] = clusterMasks(summary, cluster)
%CLUSTERMASKS  Which vertices and which samples this cluster covers.
%   Resolved through the label list rather than by parsing 'v123' back into
%   a number: the labels are generated in one place
%   (TransTools.SourceVertexLabels) precisely so nothing else has to know
%   their format, and a parse here would quietly reintroduce that coupling.
    statMap = summary.stat.stat;
    vertexMask = ismember(summary.vertexLabels(:), cluster.channels(:));

    timeMs = summary.times;
    timeMask = timeMs >= cluster.timeRangeMs(1) & timeMs <= cluster.timeRangeMs(2);
end

function renderClusterMap(summary, vertexMask, timeMask, statMap, pngPath)
%RENDERCLUSTERMAP  The cluster's spatial extent on the cortical sheet,
%   coloured by its own statistic averaged over its own time range.
%
%   FOUR FIXED 2-D VIEWS, NOT ONE 3-D RENDER. A single three-quarter view of
%   a cortex hides most of the cortex: the medial wall of both hemispheres
%   is invisible, and so is whichever lateral surface faces away. A cluster
%   sitting in cingulate or medial prefrontal cortex, which is where a great
%   many ERP effects are placed, would simply not appear, and the reader has
%   no way to tell an absent cluster from a hidden one. In a printed report
%   nobody can rotate the view to find out.
%
%   So each hemisphere is drawn twice, laterally and medially, which is the
%   convention every surface-based package uses for exactly this reason.
%   Together the four panels cover the whole sheet: every vertex that could
%   be in a cluster is visible in one of them.
%
%   The hemispheres are split by vertex index, which is safe on these
%   templates: the first half is left and the second right, and no triangle
%   joins the two (checked on all three sheets FieldTrip ships).
%
%   Averaged over the cluster's time range rather than shown at its peak
%   instant: a cluster is a space-time object, and its peak sample is one
%   arbitrary slice of it.
%
%   EXPLICIT PER-VERTEX COLOUR, NOT TransTools.DrawSourceMap, and the
%   difference matters. DrawSourceMap colours a CONTINUOUS map through a
%   colormap, so vertices outside a cluster would take whatever colour the
%   map assigns to zero. Tried that first: with the app's default colormap
%   zero is mid-green, and the entire cortex came out painted, which reads
%   as a result covering the whole brain rather than as "not in the
%   cluster". Here everything outside is a flat neutral grey that cannot be
%   mistaken for a value, which is what makes "nothing sub-threshold is
%   drawn" true in the picture and not just in the docstring.
%
%   THE DIVERGING SCALE IS FIXED, not TransTools.DivergingColormap. That one
%   follows a user preference which may be sequential or a rainbow; the sign
%   of a cluster's statistic is the entire point of this figure, so it needs
%   a map where one direction is unambiguously one colour. Blue is negative,
%   red positive, white near zero.
    values = zeros(size(statMap, 1), 1);
    values(vertexMask) = mean(statMap(vertexMask, timeMask), 2);

    limit = max(abs(values), [], 'omitnan');
    if ~isfinite(limit) || limit == 0
        limit = 1;
    end

    outsideGrey = [0.82 0.82 0.82];
    rgb = repmat(outsideGrey, numel(values), 1);
    rgb(vertexMask, :) = blueWhiteRed(values(vertexMask) / limit);

    pos = summary.sourcemodel.pos;
    tri = summary.sourcemodel.tri;
    half = size(pos, 1) / 2;

    % azimuth 90 puts the viewer on the +x side, -90 on the -x side, so the
    % lateral and medial views of a hemisphere are the same two angles
    % swapped between them.
    panels = { ...
        'Left, lateral',  1:half,          -90; ...
        'Right, lateral', (half + 1):size(pos, 1),  90; ...
        'Left, medial',   1:half,           90; ...
        'Right, medial',  (half + 1):size(pos, 1), -90};

    fig = figure('Visible', 'off', 'HandleVisibility', 'off', 'Color', 'white', ...
        'Position', [100 100 900 700]);
    closeFig = onCleanup(@() close(fig));
    layout = tiledlayout(fig, 2, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

    % ONE BOUNDING BOX FOR ALL FOUR PANELS. Letting each panel scale itself
    % renders the hemispheres at visibly different sizes, and a reader
    % comparing two panels then reads a difference in extent that is purely
    % an artefact of the layout. The box is the whole mesh, so every panel
    % shares a scale and a cluster is the same size wherever it appears.
    box = [min(pos, [], 1); max(pos, [], 1)];
    pad = 0.02 * (box(2, :) - box(1, :));
    box = [box(1, :) - pad; box(2, :) + pad];

    for k = 1:size(panels, 1)
        keep = panels{k, 2};
        ax = nexttile(layout);
        drawHemisphere(ax, pos, tri, rgb, keep, panels{k, 3}, box);
        % Labelled inside the axes, not with title(): a title sits outside
        % the axes box and is the first thing to be clipped once the camera
        % is zoomed to fill the panel, which is exactly what happened.
        text(ax, 0.5, 0.02, panels{k, 1}, 'Units', 'normalized', ...
            'HorizontalAlignment', 'center', 'FontSize', 10, 'Color', [0.25 0.25 0.25]);
    end

    exportgraphics(layout, pngPath, 'Resolution', 150, 'BackgroundColor', 'white');
end

function drawHemisphere(ax, pos, tri, rgb, keep, azimuth, box)
%DRAWHEMISPHERE  One hemisphere, from one side, with the cluster's colours.
%   The triangle list is renumbered into the kept vertices rather than
%   passed whole with the other hemisphere merely hidden: drawing the far
%   hemisphere and relying on depth to obscure it would let its surface
%   show through wherever the two are close, and doubles the geometry in
%   every panel for nothing.
    isKept = false(size(pos, 1), 1);
    isKept(keep) = true;
    faces = tri(all(isKept(tri), 2), :);
    renumber = zeros(size(pos, 1), 1);
    renumber(keep) = 1:numel(keep);

    patch(ax, 'Vertices', pos(keep, :), 'Faces', renumber(faces), ...
        'FaceVertexCData', rgb(keep, :), 'FaceColor', 'interp', 'EdgeColor', 'none', ...
        'FaceLighting', 'gouraud', 'AmbientStrength', 0.55, 'SpecularStrength', 0.1);
    % Lights follow the camera, so each panel is lit from the side it is
    % viewed from; a fixed world-space light would leave two of the four
    % panels looking at an unlit surface.
    light(ax, 'Position', [sign(azimuth) 0.3 0.8], 'Style', 'infinite');
    light(ax, 'Position', [sign(azimuth) -0.4 -0.3], 'Style', 'infinite');
    % The shared box, with equal data aspect, is what makes the four panels
    % the same scale; the modest camera zoom then takes up the slack MATLAB
    % leaves when it fits a 3-D box whose depth axis we are looking straight
    % down. Too much zoom here clips the brain and collides with the titles.
    set(ax, 'XLim', box(:, 1)', 'YLim', box(:, 2)', 'ZLim', box(:, 3)');
    daspect(ax, [1 1 1]);
    axis(ax, 'off');
    view(ax, azimuth, 0);
    camzoom(ax, 1.08);
end

function rgb = blueWhiteRed(scaled)
%BLUEWHITERED  Signed values in [-1, 1] to blue-white-red.
%   Written out rather than taken from a colormap function so the mapping
%   is fixed for every reader of every report: see renderClusterMap's own
%   note on why a user-configurable map is wrong for a signed figure.
    scaled = max(-1, min(1, scaled(:)));

    % A FLOOR ON THE TINT, so cluster membership is always visible. Without
    % it, an in-cluster vertex whose statistic is near zero renders white,
    % which against the neutral grey outside is indistinguishable from not
    % being in the cluster at all -- and a large cluster then looks like a
    % small one. The floor keeps intensity meaningful (a strong vertex is
    % still obviously stronger) while making extent legible, which are the
    % two things this figure has to convey at once.
    magnitude = 0.15 + 0.85 * abs(scaled);

    rgb = ones(numel(scaled), 3);
    negative = scaled < 0;

    % Toward blue for negative, toward red for positive; white at zero. Both
    % off-channels fall together, so a full-strength positive vertex is red
    % rather than orange. An earlier version damped green by 0.55, which
    % made every strong positive cluster render orange and quietly turned
    % this into a different colour scale from the one its name claims.
    rgb(negative, 1) = 1 - magnitude(negative);
    rgb(negative, 2) = 1 - magnitude(negative);
    rgb(~negative, 2) = 1 - magnitude(~negative);
    rgb(~negative, 3) = 1 - magnitude(~negative);
end

function renderClusterTimeCourse(summary, vertexMask, statMap, cluster, pngPath)
%RENDERCLUSTERTIMECOURSE  The cluster's statistic over the whole tested
%   epoch, averaged across its own vertices, with its time range shaded.
%
%   THE WHOLE TESTED WINDOW IS PLOTTED, not just the cluster's extent. A
%   cluster's boundaries are where the statistic crossed a threshold, not
%   where the effect started and stopped, and showing only the inside of
%   those boundaries makes an arbitrary cut look like a measured onset.
%   Shading the range while drawing beyond it is the honest presentation.
    course = mean(statMap(vertexMask, :), 1);
    t = summary.times;

    fig = figure('Visible', 'off', 'HandleVisibility', 'off', 'Color', 'white', ...
        'Position', [100 100 700 300]);
    closeFig = onCleanup(@() close(fig));
    ax = axes('Parent', fig);
    hold(ax, 'on');

    inRange = [cluster.timeRangeMs(1), cluster.timeRangeMs(2)];

    % Zero is always in range, even when the whole trace sits on one side of
    % it. The sign of the statistic is the direction of the effect, and a
    % y-axis that omits zero hides how far from no-effect the trace actually
    % is -- an axis from -2.9 to -1.3 makes a weak effect look dramatic.
    yl = [min([course(:); 0]), max([course(:); 0])];
    if diff(yl) == 0; yl = yl + [-1 1]; end
    yl = yl + [-1 1] * 0.05 * diff(yl);
    fill(ax, [inRange(1) inRange(2) inRange(2) inRange(1)], [yl(1) yl(1) yl(2) yl(2)], ...
        [0.29 0.44 0.71], 'FaceAlpha', 0.12, 'EdgeColor', 'none');
    yline(ax, 0, 'Color', [0.6 0.6 0.6]);
    plot(ax, t, course, 'Color', [0.29 0.44 0.71], 'LineWidth', 1.6);

    hold(ax, 'off');
    xlim(ax, [t(1), t(end)]);
    ylim(ax, yl);
    xlabel(ax, 'Time (ms)');
    ylabel(ax, 'Mean t over cluster vertices');
    box(ax, 'off');
    exportgraphics(ax, pngPath, 'Resolution', 150, 'BackgroundColor', 'white');
end

function assets = emptyAssets()
    assets = struct('Index', {}, 'SourceIndex', {}, 'Sign', {}, 'PValue', {}, 'Significant', {}, ...
        'TimeRangeMs', {}, 'TouchesWindowEdge', {}, 'NVertices', {}, 'Description', {}, ...
        'MapPath', {}, 'TimeCoursePath', {});
end
