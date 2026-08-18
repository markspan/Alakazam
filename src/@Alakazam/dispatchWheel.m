function dispatchWheel(this, eventData)
%DISPATCHWHEEL  Forward a mouse-wheel event to whichever View
%   (SignalView, EpochView, TimeFrequencyView, ScalpDistributionView,
%   Brain3DView, AverageView, FourierView, SpectralMeasureView or
%   CoherenceView -- the views with wheel navigation) is on the active
%   tile, if any -- see dispatchToActiveView. Wheel events are figure-wide;
%   every open dataset is a uitab on the one shared MainFigure, so they are
%   dispatched centrally here rather than each view wiring its own
%   fig.WindowScrollWheelFcn (see SignalView.buildGraphics and
%   setupMainWindow). See dispatchKey.
    this.dispatchToActiveView(eventData, ["SignalView", "EpochView", "TimeFrequencyView", ...
        "ScalpDistributionView", "Brain3DView", "AverageView", "FourierView", ...
        "SpectralMeasureView", "CoherenceView"], "onWheel");
end
