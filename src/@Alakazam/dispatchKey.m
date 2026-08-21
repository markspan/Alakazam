function dispatchKey(this, eventData)
%DISPATCHKEY  Forward a key-press event to whichever View (EpochView,
%   AverageView, FourierView, TimeFrequencyView, SpectralMeasureView or
%   CoherenceView -- the views with keyboard navigation) is on the active
%   tile, if any -- see dispatchToActiveView. See dispatchWheel.
    this.dispatchToActiveView(eventData, ["EpochView", "AverageView", "FourierView", ...
        "TimeFrequencyView", "SpectralMeasureView", "CoherenceView"], "onKey");
end
