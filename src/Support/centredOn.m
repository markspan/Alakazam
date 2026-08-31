function pos = centredOn(parent, width, height)
%CENTREDON  A WIDTH x HEIGHT figure position, centred over PARENT.
%   POS = centredOn(PARENT, WIDTH, HEIGHT) returns a uifigure Position
%   vector. PARENT is the figure to centre over; pass [] (or anything
%   without a usable Position) to centre on the screen instead.
%
%   CENTRE ON THE APP, NOT THE SCREEN, wherever a parent is available. On a
%   multi-monitor desk the screen centre is frequently not the monitor
%   Alakazam is on, so a screen-centred dialog can open on a different
%   display from the window that raised it.
%
%   The screen fallback is not a defensive afterthought: a transformation's
%   own options dialog is opened from inside the transformation, which has
%   no handle on the main window, so [] is the ordinary case there rather
%   than an error one.
%
%   There were five copies of this before it lived anywhere -- two spelled
%   centredOn and three spelled centred, differing only in whether they
%   bothered with a parent at all.
%
%   See also BEGINBUSY, CONFIRMACTION.
    try
        p = parent.Position;
        pos = [p(1) + (p(3) - width) / 2, p(2) + (p(4) - height) / 2, width, height];
    catch
        screen = get(groot, 'ScreenSize');
        pos = [(screen(3) - width) / 2, (screen(4) - height) / 2, width, height];
    end
end
