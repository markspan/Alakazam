function tag = activeTileTag(this)
%ACTIVETILETAG  The tab Tag that keyboard/wheel shortcuts should
%   target. In Tabs mode that is unambiguous (PlotsTabGroup.
%   SelectedTab): only one plot is ever visible. In Grid/Stack mode
%   several tiles are visible at once and PlotsTabGroup.SelectedTab
%   does not change as the user clicks between them (the tabgroup
%   itself is hidden), so LastClickedTag (kept current by
%   registerTileClick) is used instead.
    if strcmp(this.PlotsViewMode, "tabs")
        tab = this.PlotsTabGroup.SelectedTab;
        if isempty(tab) || ~isvalid(tab)
            tag = "";
        else
            tag = string(tab.Tag);
        end
    else
        tag = this.LastClickedTag;
    end
end
