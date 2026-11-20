function factor = wheelZoomFactor(scrollCount)
%WHEELZOOMFACTOR  What SCROLLCOUNT notches of the mouse wheel do to a y range.
%   FACTOR = wheelZoomFactor(SCROLLCOUNT) is the factor the visible range of
%   a plot's y axis is multiplied by, for the VerticalScrollCount of a
%   ScrollWheelData event. Turning the wheel away from you (a negative
%   count) gives a factor below 1, which zooms in; towards you, above 1,
%   which zooms out, as in most plotting and map software. A fast turn
%   reports several notches at once and zooms by as many steps.
%
%   ONE STEP IS 1.25: about ten notches zoom ten-fold. Fine enough to settle
%   on a scale, quick enough to cross a decade without many turns. The
%   step is the same in every view that zooms with the wheel (AverageView,
%   and FourierView and SpectralMeasureView through ZoomSliders), which is
%   why it is kept here and nowhere else.
%
%   See also ZOOMSLIDERS, AVERAGEVIEW.
    factor = 1.25 ^ double(scrollCount);
end
