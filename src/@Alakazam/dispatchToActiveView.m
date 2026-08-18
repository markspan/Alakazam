function dispatchToActiveView(this, eventData, viewNames, methodName)
%DISPATCHTOACTIVEVIEW  Forward EVENTDATA to whichever of VIEWNAMES is on
%   the active tile (see activeTileTag), if any, by calling its own
%   METHODNAME(eventData). Shared by dispatchKey/dispatchWheel, whose
%   bodies -- look up the active tab, walk a hardcoded list of view-type
%   names via getappdata, call the first valid one's own event method --
%   were previously duplicated identically apart from that list and which
%   method to call.
    tag = this.activeTileTag();
    if strcmp(tag, "")
        return;
    end
    tab = findobj(this.PlotsTabGroup.Children, 'flat', 'Tag', tag);
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
