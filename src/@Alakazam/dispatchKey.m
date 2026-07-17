function dispatchKey(this, eventData)
%DISPATCHKEY  Forward a key-press event to whichever View (EpochView,
%   AverageView, FourierView, TimeFrequencyView, SpectralMeasureView or
%   CoherenceView -- the views with keyboard navigation) is on the active
%   tile (see activeTileTag), if any. See dispatchWheel.
    tag = this.activeTileTag();
    if strcmp(tag, "")
        return;
    end
    tab = findobj(this.PlotsTabGroup.Children, 'flat', 'Tag', tag);
    if isempty(tab) || ~isvalid(tab(1))
        return;
    end
    for viewName = ["EpochView", "AverageView", "FourierView", "TimeFrequencyView", ...
                    "SpectralMeasureView", "CoherenceView"]
        view = getappdata(tab(1), char(viewName));
        if ~isempty(view) && isvalid(view)
            view.onKey(eventData);
            return;
        end
    end
end
