function closeTab(this, tag)
%CLOSETAB  Close just the view for TAG (a dataset's uitab and, if
%   tiled, its tile) -- the underlying dataset and tree node are
%   left untouched, so reopening it just means selecting its tree
%   node again. Lighter than onDeleteNode, which also destroys the
%   dataset on disk. Wired as the right-click "Close" menu on each
%   plot tab (AlakazamPlotter.plotCurrent) and the close-x button
%   on each tile handle (tileWrapperFor).
    if strcmp(this.PickedTileTag, tag)
        this.PickedTileTag = "";
    end
    this.TileOrder = this.TileOrder(this.TileOrder ~= tag);
    tiledContent = findobj(this.TileGrid.Children, 'flat', 'Tag', tag);
    if ~isempty(tiledContent)
        delete(tiledContent);
    end
    tab = findobj(this.PlotsTabGroup.Children, 'flat', 'Tag', tag);
    if ~isempty(tab)
        % If it is undocked, its window holds the content and is not a
        % child of anything being deleted here (see undockTab).
        undocked = undockedFigureOf(tab(1));
        if ~isempty(undocked)
            delete(undocked);
        end
        delete(tab);
    end
end
