function beginReportsSplitResize(this)
%BEGINREPORTSSPLITRESIZE  Grand-Averages/Reports splitter's ButtonDownFcn
%   (see setupMainWindow): start dragging the divider between those two
%   trees -- the same hand-rolled pattern as beginTreesSplitResize,
%   tracking the mouse via MainFigure's WindowButtonMotionFcn/
%   WindowButtonUpFcn until release.
    this.MainFigure.WindowButtonMotionFcn = @(~, ~) this.dragReportsSplitResize();
    this.MainFigure.WindowButtonUpFcn     = @(~, ~) this.endReportsSplitResize();
    this.MainFigure.Pointer = "top";
end
