function dispatchToActiveView(this, eventData, viewNames, methodName, tab)
%DISPATCHTOACTIVEVIEW  Forward EVENTDATA to whichever of VIEWNAMES is on
%   the active tile (see activeTileTag), if any, by calling its own
%   METHODNAME(eventData). With TAB given, deliver to that tab's view
%   instead of looking one up: an undocked plot's window knows its own tab
%   and has no notion of which tile is active (see undockTab). Shared by dispatchKey/dispatchWheel, whose
%   bodies -- look up the active tab, walk a hardcoded list of view-type
%   names via getappdata, call the first valid one's own event method --
%   were previously duplicated identically apart from that list and which
%   method to call.
    % TAB given: the event came from that plot's own undocked window, so
    % there is nothing to resolve. Otherwise it came from the main window
    % and belongs to whichever tab or tile is active there.
    if nargin < 5 || isempty(tab)
        tag = this.activeTileTag();
        if strcmp(tag, "")
            return;
        end
        tab = findobj(this.PlotsTabGroup.Children, 'flat', 'Tag', tag);
    end
    if isempty(tab) || ~isvalid(tab(1))
        return;
    end
    for viewName = viewNames
        view = getappdata(tab(1), char(viewName));
        if ~isempty(view) && isvalid(view)
            view.(methodName)(eventData);
            return;
        end
    end
end
