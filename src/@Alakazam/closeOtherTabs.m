function closeOtherTabs(this, tag)
%CLOSEOTHERTABS  Close every open plot except TAG's, which is left
%   selected. Wired as the right-click "Close others" menu on each plot tab
%   (see AlakazamPlotter.plotCurrent).
%
%   NOTHING IS DESTROYED. Like closeTab, this closes views and not data:
%   every dataset and tree node is untouched, so a plot closed here comes
%   back by selecting its node again. That is why there is no confirmation
%   step, and why it matches the plain "Close" beside it in the menu.
%
%   IT GOES THROUGH closeTab RATHER THAN DELETING TABS, so each one is
%   taken down properly: a tile in the tile grid, an undocked window, its
%   place in TileOrder and a stale picked-tile tag are all that method's
%   business, and repeating any of it here is how the two would drift.
%
%   WHICH TABS TO CLOSE IS DECIDED FIRST, in otherTabTags, and only then
%   acted on. Walking PlotsTabGroup.Children while deleting from it is the
%   ordinary way to skip half the list.
%
%   See also CLOSETAB, OTHERTABTAGS, UNDOCKTAB.
    doomed = otherTabTags(this.PlotsTabGroup.Children, tag);
    if isempty(doomed)
        return;
    end

    for k = 1:numel(doomed)
        this.closeTab(char(doomed(k)));
    end

    survivor = findobj(this.PlotsTabGroup.Children, 'flat', 'Tag', char(tag));
    if ~isempty(survivor) && strcmp(this.PlotsViewMode, "tabs")
        this.PlotsTabGroup.SelectedTab = survivor(1);
    end
    this.refreshPlotsView();
end
