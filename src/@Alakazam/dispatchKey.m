function dispatchKey(this, eventData, tab)
%DISPATCHKEY  Forward a key-press event to whichever View (EpochView,
%   AverageView, FourierView, TimeFrequencyView, SpectralMeasureView or
%   CoherenceView -- the views with keyboard navigation) is on the active
%   tile, if any -- see dispatchToActiveView. With TAB given, deliver to
%   that tab's own view instead: an undocked plot's window has its own key
%   handler, since key events are figure-wide (see undockTab). See
%   dispatchWheel.
    if nargin < 3
        tab = matlab.ui.container.Tab.empty;
    end
    this.dispatchToActiveView(eventData, ["EpochView", "AverageView", "FourierView", ...
        "TimeFrequencyView", "SpectralMeasureView", "CoherenceView"], "onKey", tab);
end
