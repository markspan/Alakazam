function highlightTile(this, tag, picked)
%HIGHLIGHTTILE  Colour TAG's tile title button to show whether it is
%   currently picked for a click-to-swap reorder. Searches the
%   whole wrapper subtree (not just its direct Children), since the
%   title button now sits one level down inside the handle row --
%   see tileWrapperFor.
    wrapper = findobj(this.TileGrid.Children, 'flat', 'Tag', tag);
    if isempty(wrapper)
        return;
    end
    handle = findobj(wrapper(1), 'Tag', 'tileTitle');
    if isempty(handle)
        return;
    end
    if picked
        handle(1).BackgroundColor = [.6 .75 1];
    else
        handle(1).BackgroundColor = [.85 .85 .93];
    end
end
