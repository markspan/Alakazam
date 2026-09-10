function fig = undockedFigureOf(tab)
%UNDOCKEDFIGUREOF  The window a plot tab's content has been moved into, or
%   an empty figure array if the tab's content is still in the tab.
%
%   THE TAB IS THE RECORD, not a map held by the app. A tab already carries
%   its own view object in appdata (see AlakazamPlotter.plotEpoched, read
%   back by Alakazam.dispatchToActiveView), so noting the window there too
%   keeps one fact in one place: deleting the tab takes the record with it,
%   and there is no separate table to fall out of step with the tabs.
%
%   A window deleted from underneath the tab reads as docked rather than as
%   an error, which is what every caller wants: the question they are
%   really asking is "is this tab's content somewhere else".
%
%   See also UNDOCKTABCONTENT, DOCKTABCONTENT, ALAKAZAM.UNDOCKTAB.
    fig = matlab.ui.Figure.empty;
    if isempty(tab) || ~isvalid(tab)
        return;
    end
    if ~isappdata(tab, 'UndockedFigure')
        return;
    end

    candidate = getappdata(tab, 'UndockedFigure');
    if ~isempty(candidate) && isa(candidate, 'matlab.ui.Figure') && isvalid(candidate)
        fig = candidate;
    end
end
