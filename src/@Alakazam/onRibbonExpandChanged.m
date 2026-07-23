function onRibbonExpandChanged(this, expanded)
%ONRIBBONEXPANDCHANGED  Grow / shrink the ribbon row when a group is (un)folded.
%   Wired to AlakazamRibbon.ExpandChangedFcn (see setupMainWindow): the ribbon
%   HTML reports EXPANDED = true while any group is unfolded and false once
%   everything is collapsed (a collapse click, or after a transformation is
%   chosen). The ribbon row is a fixed pixel height in MainGrid, so growing it
%   to RibbonExpandFactor x RibbonBaseHeight gives the unfolded group room for
%   its extra rows; collapsing restores the base height.
    if isempty(this.MainGrid) || ~isvalid(this.MainGrid)
        return;
    end
    if expanded
        rowHeight = this.RibbonBaseHeight * this.RibbonExpandFactor;
    else
        rowHeight = this.RibbonBaseHeight;
    end
    rows = this.MainGrid.RowHeight;
    if isequal(rows{1}, rowHeight)
        return;   % already at the target height (avoid a needless relayout)
    end
    rows{1} = rowHeight;
    this.MainGrid.RowHeight = rows;
end
