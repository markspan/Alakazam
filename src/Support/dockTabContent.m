function docked = dockTabContent(tab)
%DOCKTABCONTENT  Put an undocked plot back into its own tab.
%   DOCKED = dockTabContent(TAB) is true if TAB had a window and its
%   content has been moved back, false if there was nothing to do.
%
%   ORDER MATTERS HERE. The content is reparented before the window is
%   deleted, or deleting the window would take the plot with it. And the
%   window is removed with delete rather than close, which bypasses its own
%   CloseRequestFcn: that callback is what usually calls this function, so
%   closing would be a loop.
%
%   See also UNDOCKTABCONTENT, UNDOCKEDFIGUREOF, ALAKAZAM.DOCKTAB.
    docked = false;

    fig = undockedFigureOf(tab);
    if isempty(fig)
        return;
    end

    content = getappdata(fig, 'DockContent');
    delete(tab.Children);   % the placeholder put there when it left

    if ~isempty(content) && isvalid(content)
        content.Parent = tab;
    end

    rmappdata(tab, 'UndockedFigure');
    delete(fig);
    docked = true;
end
