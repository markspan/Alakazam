function undockTab(this, tag)
%UNDOCKTAB  Open the plot for TAG in a window of its own.
%   Wired as the right-click "Undock" menu on each plot tab (see
%   AlakazamPlotter.plotCurrent). The tab itself stays where it is, holding
%   its Tag and its view object, and shows a placeholder with a way back;
%   only the content moves. Calling it again on an already undocked tab
%   raises that window rather than making a second one.
%
%   WHY THERE IS NO NATIVE VERSION OF THIS. MATLAB offers no docking for
%   uifigures. migration.md records the two attempts: AppContainer with
%   FigureDocument rendered "undefined", and the R2025a Tabbed Figure
%   Container worked but put the plots in a second OS window separate from
%   the app's own shell, which was the thing being avoided. Reparenting the
%   content is the remaining route, and it is the one the tile grid already
%   uses (see retile and untile).
%
%   THE WINDOW OPENS OFFSET FROM THE APP rather than centred, so it does
%   not land exactly on top of the window it came from, and it goes through
%   fitOnScreen for the same reason the main window does: an offset from a
%   window already near the top of a small display otherwise puts the title
%   bar out of reach.
%
%   See also DOCKTAB, UNDOCKTABCONTENT, RETILE, ALAKAZAMPLOTTER.
    tab = findobj(this.PlotsTabGroup.Children, 'flat', 'Tag', char(tag));
    if isempty(tab)
        return;
    end
    tab = tab(1);

    existing = undockedFigureOf(tab);
    if ~isempty(existing)
        figure(existing);
        return;
    end

    main = this.MainFigure.Position;
    wanted = [main(1) + 80, main(2) + 40, max(480, main(3) - 380), max(360, main(4) - 140)];

    fig = undockTabContent(tab, ...
        "Title", "Alakazam - " + string(tab.Title), ...
        "Position", fitOnScreen(wanted), ...
        "CloseFcn", @() this.dockTab(tag), ...
        "WheelFcn", @(e) this.dispatchWheel(e, tab), ...
        "KeyFcn",   @(e) this.dispatchKey(e, tab));
    if isempty(fig)
        return;   % nothing to move: the content is tiled, not in the tab
    end

    % A tiled layout has one tile fewer now, so it has to be recomputed.
    this.refreshPlotsView();
end
