function endTreesSplitResize(this)
%ENDTREESSPLITRESIZE  WindowButtonUpFcn while dragging the tree
%   splitter (see beginTreesSplitResize): stop tracking the mouse.
    this.MainFigure.WindowButtonMotionFcn = [];
    this.MainFigure.WindowButtonUpFcn     = [];
    this.MainFigure.Pointer = "arrow";
end
