function setPlotsViewMode(this, mode)
%SETPLOTSVIEWMODE  Switch the plots area between "tabs" (one dataset
%   shown at a time, PlotsTabGroup) and the two tiled arrangements,
%   "grid" and "stack" (every open dataset shown at once, TileGrid)
%   -- see retile/untile. Switching directly between "grid" and
%   "stack" just re-lays-out TileGrid in place, without dropping
%   back to Tabs first.
    if strcmp(mode, this.PlotsViewMode)
        return;
    end
    this.PlotsViewMode = mode;
    if strcmp(mode, "tabs")
        this.untile();
        this.PlotsTabGroup.Visible = "on";
        this.TileGrid.Visible      = "off";
    else
        this.retile();
        this.TileGrid.Visible      = "on";
        this.PlotsTabGroup.Visible = "off";
    end
end
