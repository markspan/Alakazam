function dispatchWheel(this, eventData)
%DISPATCHWHEEL  Forward a mouse-wheel event to whichever View
%   (SignalView, EpochView, TimeFrequencyView,
%   ScalpDistributionView or AverageView -- the views with wheel
%   navigation) is on the active tile (see activeTileTag), if
%   any. Wheel events are figure-wide; every open dataset is a
%   uitab on the one shared MainFigure, so they are dispatched
%   centrally here rather than each view wiring its own
%   fig.WindowScrollWheelFcn (see SignalView.buildGraphics and
%   setupMainWindow). See dispatchKey.
    tag = this.activeTileTag();
    if strcmp(tag, "")
        return;
    end
    tab = findobj(this.PlotsTabGroup.Children, 'flat', 'Tag', tag);
    if isempty(tab) || ~isvalid(tab(1))
        return;
    end
    for viewName = ["SignalView", "EpochView", "TimeFrequencyView", "ScalpDistributionView", "AverageView"]
        view = getappdata(tab(1), char(viewName));
        if ~isempty(view) && isvalid(view)
            view.onWheel(eventData);
            return;
        end
    end
end
