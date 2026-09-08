function areas = screenWorkAreas()
%SCREENWORKAREAS  Each monitor's USABLE area, in MATLAB figure coordinates.
%   AREAS = screenWorkAreas() returns an N-by-4 matrix of
%   [left bottom width height], one row per monitor, in the same
%   bottom-left-origin coordinates a figure's Position uses. The primary
%   monitor is the first row.
%
%   BOUNDS ARE NOT THE USABLE AREA. groot's MonitorPositions reports the
%   full extent of each display, taskbar included, and MATLAB exposes no
%   work area of its own. A window placed against the bottom of those
%   bounds opens underneath the taskbar. Windows itself knows the
%   difference, so this asks it: System.Windows.Forms.Screen reports
%   Bounds and WorkingArea separately, and the second excludes the taskbar
%   wherever the user has put it.
%
%   THE COORDINATE SYSTEMS DIFFER AND THE CONVERSION IS THE WHOLE POINT.
%   .NET measures from the top-left of the primary display with y
%   increasing downwards and 0-based origins; MATLAB measures from the
%   bottom-left with y increasing upwards and 1-based origins. So a .NET
%   rectangle (X, Y, W, H) becomes
%
%       left   = X + 1
%       bottom = primaryHeight - (Y + H) + 1
%
%   Getting that backwards produces coordinates that look plausible on a
%   single monitor and are mirrored on any second one, which is exactly
%   the configuration this function exists for, so
%   ScreenWorkAreasTest checks the conversion against groot's own bounds.
%
%   FALLS BACK RATHER THAN FAILING. Where .NET is unavailable (a non-
%   Windows platform, or an installation without it) this returns
%   MonitorPositions with a strip reserved at the bottom of each monitor.
%   That reserve is a guess: it costs a little usable height on a display
%   with no taskbar, where not guessing would leave a window sitting under
%   one.
%
%   See also FITONSCREEN, CENTREDON.
    areas = dotNetWorkAreas();
    if isempty(areas)
        areas = fallbackWorkAreas();
    end
end

% ======================================================================= %
function areas = dotNetWorkAreas()
%DOTNETWORKAREAS  The true work areas, or [] when .NET cannot answer.
    areas = [];
    try
        NET.addAssembly('System.Windows.Forms');
        screens = System.Windows.Forms.Screen.AllScreens;
        n = double(screens.Length);
        if n < 1
            return;
        end

        primaryHeight = [];
        isPrimary = false(n, 1);
        for k = 1:n
            isPrimary(k) = logical(screens(k).Primary);
            if isPrimary(k)
                primaryHeight = double(screens(k).Bounds.Height);
            end
        end
        if isempty(primaryHeight)
            primaryHeight = double(screens(1).Bounds.Height);
            isPrimary(1) = true;
        end

        rows = zeros(n, 4);
        for k = 1:n
            w = screens(k).WorkingArea;
            rows(k, :) = [ ...
                double(w.X) + 1, ...
                primaryHeight - (double(w.Y) + double(w.Height)) + 1, ...
                double(w.Width), ...
                double(w.Height)];
        end

        % Primary first, so a caller with nowhere sensible to put a window
        % can take row 1 and be on the display the user looks at.
        areas = [rows(isPrimary, :); rows(~isPrimary, :)];
    catch
        areas = [];
    end
end

% ======================================================================= %
function areas = fallbackWorkAreas()
%FALLBACKWORKAREAS  MonitorPositions, with a taskbar-sized strip reserved.
    areas = get(groot, 'MonitorPositions');
    if isempty(areas)
        areas = get(groot, 'ScreenSize');
    end
    if isempty(areas)
        areas = [1 1 1280 800];     % nothing to go on; a usable default
        return;
    end

    % Primary first, identified the way MATLAB documents it: the display
    % whose position starts at (1,1). Done before the reserve below moves
    % the bottom edge and makes that test untrue.
    isPrimary = areas(:, 1) == 1 & areas(:, 2) == 1;
    if ~any(isPrimary)
        isPrimary = false(size(areas, 1), 1);
        isPrimary(1) = true;
    end
    areas = [areas(isPrimary, :); areas(~isPrimary, :)];

    reserve = min(48, floor(areas(:, 4) * 0.1));
    areas(:, 2) = areas(:, 2) + reserve;
    areas(:, 4) = areas(:, 4) - reserve;
end
