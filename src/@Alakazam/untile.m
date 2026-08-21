function untile(this)
%UNTILE  Reparent every tiled plot's content back into its own tab,
%   unwrapping it from its tile wrapper (see tileWrapperFor) first,
%   then discarding the now-empty wrapper. The content is found by
%   its Layout.Row (2 -- see tileWrapperFor) rather than by
%   excluding uibuttons, since the handle row itself now also
%   contains two uibuttons nested one level down.
    tabs = this.PlotsTabGroup.Children;
    for i = 1:numel(tabs)
        tab = tabs(i);
        wrapper = findobj(this.TileGrid.Children, 'flat', 'Tag', tab.Tag);
        if isempty(wrapper)
            continue;
        end
        kids = wrapper(1).Children;
        content = kids(arrayfun(@(k) isequal(k.Layout.Row, 2), kids));
        if ~isempty(content)
            content(1).Parent = tab;
        end
        delete(wrapper(1));
    end
    this.PickedTileTag = "";
end
