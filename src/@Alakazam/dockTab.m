function dockTab(this, tag)
%DOCKTAB  Bring the plot for TAG back into its tab, and close its window.
%   Called by the undocked window's own CloseRequestFcn and by both of its
%   Dock buttons (the one in the window and the one on the placeholder left
%   in the tab), so closing the window and asking to dock are the same act.
%
%   The tab is selected afterwards only in Tabs mode. In a tiled mode the
%   tab strip is not showing, and the plot reappears as a tile instead,
%   which refreshPlotsView takes care of.
%
%   See also UNDOCKTAB, DOCKTABCONTENT, REFRESHPLOTSVIEW.
    tab = findobj(this.PlotsTabGroup.Children, 'flat', 'Tag', char(tag));
    if isempty(tab)
        return;
    end
    tab = tab(1);

    if ~dockTabContent(tab)
        return;   % it was not undocked
    end

    if strcmp(this.PlotsViewMode, "tabs")
        this.PlotsTabGroup.SelectedTab = tab;
    end
    this.refreshPlotsView();
end
