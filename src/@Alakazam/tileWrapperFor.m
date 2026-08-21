function wrapper = tileWrapperFor(this, tab)
%TILEWRAPPERFOR  The tile wrapper for TAB in TileGrid: a small
%   2-row grid (title/close handle row | the view's own content),
%   built once and reused on later retile() calls. The handle row
%   is itself a 2-column grid: a title button (click-to-swap, see
%   onTileHandleClicked) and a small close-x button (closeTab).
%   uibutton, not uilabel, for both -- uibutton.ButtonPushedFcn is
%   guaranteed reliable and already used everywhere in this app;
%   uilabel click handling is not. The wrapper itself is tagged
%   with the tab's own Tag, the same correlate-by-Tag idiom used
%   everywhere else in this app, so onDeleteNode's existing
%   tiled-content lookup finds (and deletes) the whole wrapper
%   unchanged; the two handle buttons are tagged "tileTitle"/
%   "tileClose" so highlightTile can find the title one specifically.
    existing = findobj(this.TileGrid.Children, 'flat', 'Tag', tab.Tag);
    if ~isempty(existing)
        wrapper = existing(1);
        return;
    end
    content = tab.Children(1); % the view's own top container, still in the tab
    wrapper = uigridlayout(this.TileGrid, [2 1], ...
        "RowHeight", {18, '1x'}, "Padding", [1 1 1 1], "RowSpacing", 1, ...
        "Tag", tab.Tag);

    handleRow = uigridlayout(wrapper, [1 2], "ColumnWidth", {'1x', 18}, ...
        "Padding", [0 0 0 0], "ColumnSpacing", 1);
    handleRow.Layout.Row = 1;

    titleBtn = uibutton(handleRow, "Text", tab.Title, "FontSize", 9, ...
        "BackgroundColor", [.85 .85 .93], "Tag", "tileTitle", ...
        "ButtonPushedFcn", @(~, ~) this.onTileHandleClicked(tab.Tag));
    titleBtn.Layout.Column = 1;

    closeBtn = uibutton(handleRow, "Text", char(215), "FontSize", 9, ...
        "FontWeight", "bold", "BackgroundColor", [.93 .82 .82], ...
        "Tag", "tileClose", "Tooltip", "Close this plot", ...
        "ButtonPushedFcn", @(~, ~) this.closeTab(tab.Tag));
    closeBtn.Layout.Column = 2;

    content.Parent = wrapper;
    content.Layout.Row = 2;
end
