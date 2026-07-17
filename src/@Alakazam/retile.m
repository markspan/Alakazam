function retile(this)
%RETILE  Lay every open plot tab's content out in TileGrid, wrapped
%   in a small handle+content wrapper (see tileWrapperFor) so each
%   tile has a click target for reordering (onTileHandleClicked).
%   TileOrder is synced first (drop tags for tabs that no longer
%   exist, append any new tab's tag at the end), then wrappers are
%   placed in that order rather than PlotsTabGroup.Children's
%   creation order, so a click-to-swap reorder (which only mutates
%   TileOrder) survives repeated retile() calls. Recomputes the
%   full grid from scratch on every call (simple, cheap, avoids
%   incremental-placement bugs). "grid" arranges tiles in a near-
%   square rows/cols layout; "stack" is a single column, one tile
%   per row.
    tabs = this.PlotsTabGroup.Children;
    tabTags = arrayfun(@(t) string(t.Tag), tabs);

    this.TileOrder = this.TileOrder(ismember(this.TileOrder, tabTags));
    newTags = tabTags(~ismember(tabTags, this.TileOrder));
    this.TileOrder = [this.TileOrder, newTags];

    n = numel(this.TileOrder);
    if n == 0
        return;
    end
    if strcmp(this.PlotsViewMode, "stack")
        rows = n;
        cols = 1;
    else % "grid"
        rows = max(1, floor(sqrt(n)));
        cols = ceil(n / rows);
    end
    this.TileGrid.RowHeight   = repmat({'1x'}, 1, rows);
    this.TileGrid.ColumnWidth = repmat({'1x'}, 1, cols);

    for i = 1:n
        tab = tabs(tabTags == this.TileOrder(i));
        wrapper = this.tileWrapperFor(tab);
        wrapper.Layout.Row    = ceil(i / cols);
        wrapper.Layout.Column = mod(i - 1, cols) + 1;
    end
end
