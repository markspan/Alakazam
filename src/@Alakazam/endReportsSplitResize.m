function endReportsSplitResize(this)
%ENDREPORTSSPLITRESIZE  WindowButtonUpFcn while dragging the Grand
%   Averages/Reports splitter (see beginReportsSplitResize): stop
%   tracking the mouse.
    this.MainFigure.WindowButtonMotionFcn = [];
    this.MainFigure.WindowButtonUpFcn     = [];
    this.MainFigure.Pointer = "arrow";
end
