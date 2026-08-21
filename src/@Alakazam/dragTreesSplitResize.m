function dragTreesSplitResize(this)
%DRAGTREESSPLITRESIZE  WindowButtonMotionFcn while dragging the tree
%   splitter (see beginTreesSplitResize): resize the Data & Analyses
%   row to track the mouse, leaving Grand Averages ('1x') to fill the
%   remainder, clamped so neither panel can be dragged to nothing.
    mousePos  = this.MainFigure.CurrentPoint;
    treeTop   = this.TreeGrid.Position(2) + this.TreeGrid.Position(4);
    available = this.TreeGrid.Position(4) - 3; % minus the splitter row itself
    newHeight = max(60, min(available - 60, treeTop - mousePos(2)));
    this.TreeGrid.RowHeight{1} = newHeight;
end
