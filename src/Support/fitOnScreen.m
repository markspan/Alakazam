function pos = fitOnScreen(pos, areas, titleBarHeight)
%FITONSCREEN  A window position clamped so the whole window is reachable.
%   POS = fitOnScreen(POS) takes a [left bottom width height] figure
%   position and returns one that lies entirely within a single monitor's
%   usable area, with room above it for the title bar.
%
%   POS = fitOnScreen(POS, AREAS, TITLEBARHEIGHT) uses the given work
%   areas (see screenWorkAreas) and title-bar allowance instead of asking
%   the system. Both are for tests: a monitor layout is the one input that
%   cannot be arranged on the machine running the suite, so it is injected
%   rather than mocked.
%
%   THE TITLE BAR IS THE POINT. A uifigure's Position describes its
%   drawable area, and the window frame sits ABOVE that: OuterPosition
%   reports the same rectangle, so MATLAB never says how tall the frame is
%   (checked, on a visible figure, not assumed). A window whose Position
%   reaches the top of the display therefore has its title bar off the
%   screen, and a window that cannot be grabbed by its title bar cannot be
%   moved or resized by any ordinary means. That is the failure this
%   function exists to prevent, so the allowance is subtracted from the
%   usable height rather than treated as a margin that could be dropped.
%
%   WHY 1280 x 720 AT (100, 100) WAS NOT SAFE. It is a perfectly ordinary
%   default, and on a 1366 x 768 display its top edge lands at 820, over
%   the top of a 768-pixel screen before the title bar is even counted.
%   The window opens, draws correctly, and cannot be moved.
%
%   IT STAYS ON THE MONITOR IT WAS ASKED FOR wherever that monitor exists.
%   The target is the display the requested rectangle overlaps most, so a
%   window remembered on a second screen is corrected on that screen
%   rather than yanked to the primary. Only a rectangle overlapping
%   nothing (a display that has since been unplugged) falls back to the
%   primary. MATLAB's own movegui('onscreen') does not make this
%   distinction: asked to fix a window hanging off the primary display, it
%   moved it to the secondary one.
%
%   Shrinking comes before moving, since a window larger than the display
%   cannot be made to fit by moving it, and a caller would rather have a
%   smaller reachable window than a correctly sized unreachable one.
%
%   See also SCREENWORKAREAS, CENTREDON, ALAKAZAM.SETUPMAINWINDOW.
    if nargin < 2 || isempty(areas)
        areas = screenWorkAreas();
    end
    if nargin < 3 || isempty(titleBarHeight)
        titleBarHeight = defaultTitleBarHeight();
    end
    if numel(pos) ~= 4 || ~all(isfinite(pos))
        return;     % nothing usable to clamp; leave the caller's value alone
    end

    target = targetArea(pos, areas);

    % The frame lives above the drawable area, so the height available to
    % Position is the work area less the title bar.
    usableHeight = max(target(4) - titleBarHeight, 1);

    width  = max(min(pos(3), target(3)), 1);
    height = max(min(pos(4), usableHeight), 1);

    left   = min(max(pos(1), target(1)), target(1) + target(3) - width);
    bottom = min(max(pos(2), target(2)), target(2) + usableHeight - height);

    pos = [left, bottom, width, height];
end

% ======================================================================= %
function area = targetArea(pos, areas)
%TARGETAREA  The monitor this window belongs on: the one it overlaps most,
%   or the primary when it overlaps none.
    if isempty(areas)
        area = [1 1 1280 800];
        return;
    end

    best = 0;
    area = areas(1, :);
    for k = 1:size(areas, 1)
        overlap = overlapArea(pos, areas(k, :));
        if overlap > best
            best = overlap;
            area = areas(k, :);
        end
    end
end

function a = overlapArea(r1, r2)
%OVERLAPAREA  Area shared by two [left bottom width height] rectangles.
    dx = min(r1(1) + r1(3), r2(1) + r2(3)) - max(r1(1), r2(1));
    dy = min(r1(2) + r1(4), r2(2) + r2(4)) - max(r1(2), r2(2));
    a = max(dx, 0) * max(dy, 0);
end

function h = defaultTitleBarHeight()
%DEFAULTTITLEBARHEIGHT  Room for the window frame, scaled for the display.
%   A Windows title bar is about 31 pixels at 96 DPI; 40 leaves a little
%   over for the border and for themes that draw a taller one. MATLAB
%   cannot be asked (see this file's own header), so this is the one
%   quantity here that is a considered guess rather than a measurement.
    try
        scale = get(groot, 'ScreenPixelsPerInch') / 96;
    catch
        scale = 1;
    end
    h = round(40 * max(scale, 1));
end
