function beginTreesSplitResize(this)
%BEGINTREESSPLITRESIZE  Data/Grand-Averages splitter's ButtonDownFcn
%   (see setupMainWindow): start dragging the divider between the two
%   workspace trees -- the same hand-rolled pattern as
%   beginTreeResize, tracking the mouse via MainFigure's
%   WindowButtonMotionFcn/WindowButtonUpFcn until release.
    this.MainFigure.WindowButtonMotionFcn = @(~, ~) this.dragTreesSplitResize();
    this.MainFigure.WindowButtonUpFcn     = @(~, ~) this.endTreesSplitResize();
    this.MainFigure.Pointer = "top";
end
