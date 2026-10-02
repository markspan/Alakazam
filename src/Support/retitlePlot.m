function retitlePlot(tabGroup, tileGrid, file, title)
%RETITLEPLOT  Give the plot of FILE a new title wherever it is shown.
%   RETITLEPLOT(TABGROUP, TILEGRID, FILE, TITLE) sets the title of the tab in
%   TABGROUP tagged FILE, the title button of its tile in TILEGRID when the
%   plots are tiled, and the name of its window when it is undocked. Each
%   is skipped where the plot is not shown; nothing is opened.
%
%   See also TABTITLEFOR, ONRENAMENODE, UNDOCKTAB, TILEWRAPPERFOR.
    tab = findobj(tabGroup.Children, 'flat', 'Tag', file);
    if isempty(tab)
        return;   % not plotted, so not tiled or undocked either
    end
    tab(1).Title = title;

    if ~isempty(tileGrid) && isvalid(tileGrid)
        tile = findobj(tileGrid.Children, 'flat', 'Tag', file);
        if ~isempty(tile)
            button = findobj(tile(1), 'Tag', 'tileTitle');
            if ~isempty(button)
                button(1).Text = title;
            end
        end
    end

    undocked = undockedFigureOf(tab(1));
    if ~isempty(undocked)
        undocked.Name = "Alakazam - " + string(title);   % as undockTab names it
    end
end
