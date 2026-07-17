function dragTreeResize(this)
%DRAGTREERESIZE  WindowButtonMotionFcn while dragging the splitter
%   (see beginTreeResize): resize the tree column to track the
%   mouse, clamped to a sane range.
    mousePos = this.MainFigure.CurrentPoint;
    treeLeft = this.TreeGrid.Position(1);
    newWidth = max(150, min(600, mousePos(1) - treeLeft));
    this.MainGrid.ColumnWidth{1} = newWidth;
end
