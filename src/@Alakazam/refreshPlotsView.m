function refreshPlotsView(this)
%REFRESHPLOTSVIEW  Re-tile the plots area if currently in a tiled
%   mode ("grid" or "stack"). Called by AlakazamPlotter.plotCurrent
%   after opening or selecting a tab, so a newly opened dataset
%   appears in the tile grid immediately if tiling is already
%   active. No-op in Tabs mode.
    if ~strcmp(this.PlotsViewMode, "tabs")
        this.retile();
    end
end
