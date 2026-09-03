function DrawScalpMap(ax, values, chanlocs, mapLimit)
%DRAWSCALPMAP  Scalp topography (colour-filled interpolated map, contour
%   lines, cartoon head/nose/ears, electrode dots) drawn directly into AX.
%
%   A port of EEGLAB's topoplot() (functions/sigprocfunc/topoplot.m),
%   restricted to exactly the code path ScalpDistribution.m's own
%   topoplot(...) call used to take (STYLE='both', SHADING='flat',
%   ELECTRODES='on', EMARKER='.', headrad=rmax=0.5, CONVHULL off, no
%   EMARKER2CHANS/grid/colorbar) -- not a general-purpose reimplementation
%   of every topoplot option. Needed because topoplot() itself cannot draw
%   into a uiaxes: it works throughout via gca/gcf-implicit state
%   (axes(ax); topoplot(...)), and confirmed directly (not assumed) that
%   this silently draws ZERO graphics children into a uiaxes hosted inside
%   a uitab, rather than erroring -- see migration.md. Every graphics call
%   here instead targets AX explicitly (surface/contour/patch/plot all
%   accept an axes handle as their first argument), which does work
%   correctly inside a uiaxes.
%
%   VALUES is one value per channel in CHANLOCS, in the same order as
%   CHANLOCS (both length n); CHANLOCS a struct array with resolved
%   .theta/.radius (or .X/.Y/.Z) position fields, as produced by
%   ScalpDistribution.m's own 10-5 template lookup. MAPLIMIT is a single
%   positive scalar; the colour scale is fixed to [-MAPLIMIT, MAPLIMIT],
%   matching ScalpDistribution.m's own shared, symmetric colour scale
%   across every bin/instant.
%
%   Coordinate convention: [a,b] = pol2cart(theta,radius) reproduces
%   topoplot.m's own raw electrode positions exactly (verified directly
%   against real topoplot() output -- see below), which for
%   Template1005File's standard_1005.elc template plots the
%   anterior-posterior (Fpz-Cz-Oz) axis *horizontally* and the left-right
%   (T7-T8) axis *vertically*, not the more usual "nose up" cartoon-head
%   orientation. Rotated 90 degrees clockwise here on request (horiz = a,
%   vert = -b) so the anterior-posterior line runs vertically, nose (Fpz)
%   up -- do NOT trust topoplot.m's help text claim that "0 deg. points to
%   the nose" as a shortcut for the *unrotated* (a,b) themselves: verified
%   that a template's raw .theta is not already in that oriented
%   convention (frontal/occipital electrodes land on the horizontal axis
%   before this rotation) -- readlocs() is therefore called here exactly
%   as topoplot.m itself calls it (topoplot.m:692-699), rather than
%   reading chanlocs.theta/.radius directly, and the unrotated electrode
%   placement this produces was verified to match real topoplot()'s own
%   drawn positions exactly (to floating-point precision) for a real
%   6-channel test set -- see test_drawscalpmap.m referenced from
%   migration.md, not derived from the help text's documented convention
%   alone.
%
%   Ported from topoplot.m, EEGLAB 2026.0.0
%   (functions/sigprocfunc/topoplot.m).

    GRID_SCALE = 67;          % interpolation grid resolution (topoplot default)
    CIRCGRID = 201;            % points used to draw circular outlines
    rmax = 0.5;                % head radius, topoplot's fixed convention
    AXHEADFAC = 1.3;           % headroom around the head in the axes
    CONTOURNUM = 6;            % number of contour levels
    HEADCOLOR = [0 0 0];
    CCOLOR = [0.2 0.2 0.2];
    HLINEWIDTH = 2;
    BLANKINGRINGWIDTH = 0.035;
    HEADRINGWIDTH = 0.007;
    BACKCOLOR = ax.Color;      % blend the masking ring into the axes background

    % topoplot.m ALWAYS re-derives Th/Rd via readlocs(loc_file) internally
    % -- even when loc_file is already a struct (topoplot.m:692-694) -- so
    % chanlocs.theta/.radius are not necessarily what topoplot would
    % actually use directly: readlocs/convertlocs prefers Cartesian X/Y/Z
    % (also set on this struct, by the same template lookup that set
    % theta/radius) as the ground truth and recomputes theta/radius from
    % it, which does not always match a template file's own raw
    % theta/radius values (confirmed empirically -- the standard_1005.elc
    % template's raw .theta for T7/T8 put them at the front/back midline,
    % nowhere near the ears, until routed through this same readlocs
    % call). Calling the identical readlocs(chanlocs) topoplot.m itself
    % calls guarantees identical coordinates to the real topoplot(),
    % rather than a hand-rolled approximation of its conversion chain.
    % The 5th output, indices, lists which positions in CHANLOCS the
    % returned Th/Rd/labels correspond to -- readlocs() drops channels
    % lacking usable coordinates, so this reorders/subsets VALUES to
    % match exactly, rather than assuming Th/Rd/labels come back in the
    % same order/length as CHANLOCS (topoplot.m relies on this same
    % indices output for its own Values(indices) selection).
    [~, ~, Th, Rd, indices] = readlocs(chanlocs);
    theta = deg2rad(Th);
    radius = Rd;
    values = values(indices);
    [a, b] = pol2cart(theta, radius);   % topoplot.m's own raw (unrotated) electrode positions
    horiz  =  a;                        % rotated 90 degrees clockwise: anterior-posterior line now vertical, nose up
    vert   = -b;

    plotrad = min(1.0, max(radius) * 1.08);
    plotrad = max(plotrad, rmax);         % ScalpDistribution.m never overrides this, so plotrad >= rmax always
    headrad = rmax;                       % => always draw the cartoon head, matching the original's own behaviour
    squeezefac = rmax / plotrad;
    horiz = horiz * squeezefac;
    vert  = vert * squeezefac;

    %% Interpolate the scalp map onto a GRID_SCALE x GRID_SCALE grid.
    vmin = min(-rmax, min(vert));  vmax = max(rmax, max(vert));    % vertical (screen) range
    hmin = min(-rmax, min(horiz)); hmax = max(rmax, max(horiz));   % horizontal (screen) range
    vi = linspace(vmin, vmax, GRID_SCALE);
    hi = linspace(hmin, hmax, GRID_SCALE);
    [Hq, Vq] = meshgrid(hi, vi);
    Zi = griddata(horiz, vert, double(values(:)), Hq, Vq, 'v4'); % 'v4' matches topoplot.m exactly

    mask = sqrt(Hq.^2 + Vq.^2) <= rmax;
    Zi(~mask) = NaN;
    delta = hi(2) - hi(1);

    %% Draw.
    cla(ax);
    hold(ax, 'on');
    ax.XLim = [-rmax, rmax] * AXHEADFAC;
    ax.YLim = [-rmax, rmax] * AXHEADFAC;
    % Amplitude is a signed, zero-centred quantity, same as ERSP power
    % (TimeFrequencyView) and ERP-image amplitude (EpochView) -- the same
    % blue/white/red diverging colormap, not MATLAB's default (parula),
    % for a consistent convention (and a consistent colorbar) across
    % every plot in the app that shows one.
    colormap(ax, TransTools.DivergingColormap());

    surface(ax, Hq - delta / 2, Vq - delta / 2, zeros(size(Zi)) - 0.1, Zi, ...
        'EdgeColor', 'none', 'FaceColor', 'flat');
    [~, contourHandle] = contour(ax, Hq, Vq, Zi, CONTOURNUM, 'k');
    contourHandle.LineColor = CCOLOR;
    ax.CLim = [-mapLimit, mapLimit];

    %% Masking ring: hide the jagged interpolation-grid boundary outside rmax.
    circ = linspace(0, 2 * pi, CIRCGRID);
    rx = sin(circ);
    ry = cos(circ);
    hwidth = HEADRINGWIDTH;
    hin = squeezefac * headrad * (1 - hwidth / 2);
    rwidth = BLANKINGRINGWIDTH;
    rin = rmax * (1 - rwidth / 2);
    if hin > rin
        rin = hin;
    end
    ringx = [[rx, rx(1)] * (rin + rwidth), [rx, rx(1)] * rin];
    ringy = [[ry, ry(1)] * (rin + rwidth), [ry, ry(1)] * rin];
    patch(ax, ringx, ringy, 0.01 * ones(size(ringx)), BACKCOLOR, 'EdgeColor', 'none');

    %% Cartoon head outline, nose and ears.
    headx = [rx, rx(1)] * hin;
    heady = [ry, ry(1)] * hin;
    plot(ax, headx, heady, 'Color', HEADCOLOR, 'LineWidth', HLINEWIDTH);

    base = rmax - 0.0046;
    basex = 0.18 * rmax;
    tip = 1.15 * rmax;
    tiphw = 0.04 * rmax;
    tipr = 0.01 * rmax;
    earLead  = [.497 - .005, .510, .518, .5299, .5419, .54, .547, .532, .510, .489 - .005];
    earTrail = [.04 + .0555, .04 + .0775, .04 + .0783, .04 + .0746, .04 + .0555, ...
        -.0055, -.0932, -.1313, -.1384, -.1199];
    sf = headrad / plotrad;
    plot(ax, [basex, tiphw, 0, -tiphw, -basex] * sf, [base, tip - tipr, tip, tip - tipr, base] * sf, ...
        'Color', HEADCOLOR, 'LineWidth', HLINEWIDTH);
    plot(ax, earLead * sf, earTrail * sf, 'Color', HEADCOLOR, 'LineWidth', HLINEWIDTH);
    plot(ax, -earLead * sf, earTrail * sf, 'Color', HEADCOLOR, 'LineWidth', HLINEWIDTH);

    %% Electrode markers.
    if numel(horiz) >= 100
        markerSize = 3;
    elseif numel(horiz) >= 80
        markerSize = 4;
    elseif numel(horiz) >= 64
        markerSize = 4;
    elseif numel(horiz) >= 48
        markerSize = 4;
    elseif numel(horiz) >= 32
        markerSize = 4;
    else
        markerSize = 5;
    end
    plot(ax, horiz, vert, 'o', 'Color', [0 0 0], 'MarkerSize', markerSize);

    axis(ax, 'square');
    axis(ax, 'off');
    hold(ax, 'off');
end
