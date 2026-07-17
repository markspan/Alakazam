function endTreeResize(this)
%ENDTREERESIZE  WindowButtonUpFcn while dragging the splitter (see
%   beginTreeResize): stop tracking the mouse.
    this.MainFigure.WindowButtonMotionFcn = [];
    this.MainFigure.WindowButtonUpFcn     = [];
    this.MainFigure.Pointer = "arrow";
end
