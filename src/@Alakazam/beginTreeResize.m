function beginTreeResize(this)
%BEGINTREERESIZE  Splitter panel's ButtonDownFcn (see setupMainWindow):
%   start dragging the tree/plots divider. A plain uigridlayout has
%   no built-in resizable divider, so this hand-rolls one: track the
%   mouse via MainFigure's WindowButtonMotionFcn/WindowButtonUpFcn
%   until release, live-updating MainGrid's tree column width.
    this.MainFigure.WindowButtonMotionFcn = @(~, ~) this.dragTreeResize();
    this.MainFigure.WindowButtonUpFcn     = @(~, ~) this.endTreeResize();
    this.MainFigure.Pointer = "left";
end
