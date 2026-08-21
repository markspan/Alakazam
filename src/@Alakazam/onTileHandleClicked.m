function onTileHandleClicked(this, tag)
%ONTILEHANDLECLICKED  A tile's handle button was clicked: pick it
%   (first click, highlighted), cancel (clicking the same one
%   again), or swap it with whichever tile was already picked
%   (second click on a different tile) -- click-to-swap reordering,
%   used instead of true drag-and-drop (see migration.md: MATLAB's
%   hittest() does not support the point-based lookup live drag
%   hit-testing would need). Also counts as clicking into that tile
%   (see registerTileClick), so keyboard/wheel shortcuts follow the
%   handle click even if the user never touches the tile's content.
    this.registerTileClick(tag);
    if strcmp(this.PickedTileTag, "")
        this.PickedTileTag = tag;
        this.highlightTile(tag, true);
    elseif strcmp(this.PickedTileTag, tag)
        this.highlightTile(tag, false);
        this.PickedTileTag = "";
    else
        ia = find(this.TileOrder == this.PickedTileTag, 1);
        ib = find(this.TileOrder == tag, 1);
        this.TileOrder([ia ib]) = this.TileOrder([ib ia]);
        this.highlightTile(this.PickedTileTag, false);
        this.PickedTileTag = "";
        this.retile();
    end
end
