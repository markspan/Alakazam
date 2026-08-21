function dragReportsSplitResize(this)
%DRAGREPORTSSPLITRESIZE  WindowButtonMotionFcn while dragging the Grand
%   Averages/Reports splitter (see beginReportsSplitResize): resize the
%   Grand Averages row (TreeGrid row 3) to track the mouse, leaving
%   Reports ('1x', row 5) to fill the remainder, clamped so neither panel
%   can be dragged to nothing.
%
%   Anchored on GrandAveragesTreePanel/ReportsTreePanel's own current
%   rendered Position, not a RowHeight-derived offset (unlike that would
%   be unreliable while a row still holds its initial fractional '1x'/
%   '2x' value rather than a dragged pixel one, since RowHeight only
%   reports what was SET, not the resolved layout) -- Position always
%   reflects the real, current geometry regardless, the same reasoning
%   dragTreeResize (the tree/plots splitter) already relies on via
%   TreeGrid.Position.
    mousePos    = this.MainFigure.CurrentPoint;
    panelTop    = this.GrandAveragesTreePanel.Position(2) + this.GrandAveragesTreePanel.Position(4);
    panelBottom = this.ReportsTreePanel.Position(2);
    available   = panelTop - panelBottom; % Grand Averages + Reports rows, minus this splitter's own 3 px
    newHeight   = max(60, min(available - 60, panelTop - mousePos(2)));
    this.TreeGrid.RowHeight{3} = newHeight;
end
