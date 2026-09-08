function onRibbonWidthMeasured(this, width)
%ONRIBBONWIDTHMEASURED  AlakazamRibbon's ContentWidthMeasuredFcn: WIDTH is
%   the widest any one ribbon tab's own content needs to be to show without
%   a horizontal scrollbar (see AlakazamRibbon.html's own
%   alzMeasureAndReportWidth -- it checks every tab, typically Tools, the
%   one with every transformation group, not just whichever tab happens to
%   be active at startup). The ribbon spans MainFigure's full width (see
%   setupMainWindow's ToolbarGrid), so this only ever needs to grow
%   MainFigure's own width to match -- never shrinks it, since a user-sized
%   (or already-wide-enough) window should never be narrowed back down.
    margin = 20; % MainGrid padding + ribbon-internal padding, not part of WIDTH itself
    needed = ceil(width) + margin;
    pos = this.MainFigure.Position;
    if pos(3) < needed
        pos(3) = needed;
        % Growing the width can push the right edge, and with it the whole
        % window, off the display: the ribbon needs whatever it needs, and
        % the monitor is whatever size it is. fitOnScreen caps the width at
        % the display and shifts the window back on, which leaves the
        % ribbon with its own horizontal scrollbar, the fallback this
        % method's own header already describes.
        pos = fitOnScreen(pos);
        this.MainFigure.Position = pos;
    end
end
