classdef ZoomSliders < handle
%ZOOMSLIDERS  The "x zoom" and "y zoom" sliders under a spectrum plot.
%   FourierView and SpectralMeasureView build this below their plot: two
%   rows, each a small label and a 0..1 slider, styled like SignalView's own
%   zoom/pan/mag rows. Everything else about moving around the plot is the
%   view's own: the channel and bin are dropdowns above it, stepped by the
%   keys too, and the axes toolbar pans.
%
%   It used to be ZoomPanButtons, which also built a row of channel-step,
%   pan and bin-step buttons with a channel dropdown squeezed in at its end.
%   Both views moved their choices into dropdowns above the plot, as the
%   other views have them, which left the sliders alone.
%
%   THE X AXIS IS OWNED HERE. The zoom is a fraction of the frequency range
%   up to Nyquist, fixed for the view's whole life, so it is applied to the
%   axes directly and never touched by the view's own redraw. It is
%   anchored at the LEFT edge of the axes as they are, not their centre: 0
%   Hz is a meaningful reference for a spectrum, not an arbitrary scroll
%   position, so it stays in view unless the axes have been panned away
%   from it with the toolbar, and then the zoom keeps that pan.
%
%   THE Y AXIS IS THE VIEW'S. Each channel and bin has its own natural
%   scale, known only to the view, so the view calls applyYZoom with it at
%   the end of every redraw (in place of a bare ylim), and this applies the
%   CURRENT y-zoom slider value relative to it. That is what keeps "how
%   zoomed in" stable across a channel or bin change, rather than snapping
%   back to fully zoomed out on every redraw.
%
%   AX and NYQUIST are captured once at construction: neither caller ever
%   reassigns its axes or swaps in another dataset.
%
%   See also FOURIERVIEW, SPECTRALMEASUREVIEW, SIGNALVIEW.

    properties (Access = private)
        Axes
        Nyquist         % upper x-limit (EEG.srate / 2)
        ActivatedFcn    % function handle (), or empty
        XZoomValue = 0  % 0..1, x-zoom slider value (0 = the whole range)
        YZoomValue = 0  % 0..1, y-zoom slider value (0 = the natural range)
        YTop = 1        % most recent natural top passed to applyYZoom
        YBottom = 0     % and its natural bottom (0 for a magnitude, -pi for a phase)
    end

    properties (Constant, Access = private)
        MinFraction = 0.01 % narrowest zoom, as a fraction of the full range
        LabelWidthPx = 40
    end

    methods
        function this = ZoomSliders(grid, rows, ax, nyquist, activatedFcn)
        %ZOOMSLIDERS  Build the x-zoom slider into GRID's row ROWS(1) and the
        %   y-zoom slider into ROWS(2), zooming AX, whose frequencies run to
        %   NYQUIST. ACTIVATEDFCN(), if non-empty, is called before every
        %   slider drag and release, mirroring the owning view's own
        %   notifyActivated.
            this.Axes = ax;
            this.Nyquist = nyquist;
            this.ActivatedFcn = activatedFcn;
            this.makeSliderRow(grid, rows(1), "x zoom", "Zoom the frequency axis", ...
                "XZoom", @(v) this.onXZoomChanged(v));
            this.makeSliderRow(grid, rows(2), "y zoom", "Zoom the amplitude axis", ...
                "YZoom", @(v) this.onYZoomChanged(v));
            this.applyXLim(0);
        end

        function applyYZoom(this, naturalTop, naturalBottom)
        %APPLYYZOOM  Set the y-limits to the current y-zoom slider value,
        %   relative to NATURALTOP (the owning view's own auto-scale for
        %   whatever channel/trial/bin is now shown). Call at the end of the
        %   owning view's redraw(), in place of a bare ylim(ax,[0,top]).
        %
        %   NATURALBOTTOM, 0 when omitted, is the lower end of that range,
        %   for a quantity that goes below zero: -pi for a phase in
        %   [-pi, pi]. Zooming scales both ends towards 0, so a magnitude
        %   keeps its 0 at the bottom and a phase stays centred on 0.
        %
        %   ON A LOG AXIS (YScale 'log'), NATURALBOTTOM must be positive, and
        %   zooming keeps it and brings the top down by the same fraction of
        %   the range in decades, which is what zooming in on a magnitude
        %   means there; scaling both ends towards 0 would only slide the
        %   window down.
            if ~isfinite(naturalTop) || naturalTop <= 0
                naturalTop = 1;
            end
            if nargin < 3 || ~isfinite(naturalBottom) || naturalBottom >= naturalTop
                naturalBottom = 0;
            end
            this.YTop = naturalTop;
            this.YBottom = naturalBottom;
            this.applyYLim();
        end
    end

    methods (Access = private)
        function makeSliderRow(this, grid, row, labelText, tip, tag, changedFcn)
        %MAKESLIDERROW  One grid row: a label plus a 0..1 slider, tagged TAG,
        %   that fires CHANGEDFCN(value) while dragging and on release,
        %   matching SignalView's own zoom/pan/mag rows.
            sliderRow = uigridlayout(grid, [1 2], "ColumnWidth", {this.LabelWidthPx, '1x'}, ...
                "Padding", [0 0 0 0]);
            sliderRow.Layout.Row = row;
            label = uilabel(sliderRow, "Text", labelText, "HorizontalAlignment", "right", "FontSize", 8);
            label.Layout.Column = 1;
            slider = uislider(sliderRow, "Limits", [0, 1], "Value", 0, "Tag", tag, ...
                "MajorTicks", [], "MinorTicks", [], "Tooltip", tip, ...
                "ValueChangingFcn", @(src, e) this.onSliderChanging(src, e, changedFcn), ...
                "ValueChangedFcn", @(src, ~) this.onSliderChanged(src, changedFcn));
            slider.Layout.Column = 2;
        end

        function onSliderChanging(this, src, event, changedFcn)
        %ONSLIDERCHANGING  Live-drag: sync the slider's own Value to the
        %   in-progress value (uislider does not update it until the drag
        %   ends), matching SignalView's own onSliderChanging.
            src.Value = event.Value;
            this.notifyOwnerActivated();
            changedFcn(event.Value);
        end

        function onSliderChanged(this, src, changedFcn)
            this.notifyOwnerActivated();
            changedFcn(src.Value);
        end

        function notifyOwnerActivated(this)
            if ~isempty(this.ActivatedFcn)
                this.ActivatedFcn();
            end
        end

        function onXZoomChanged(this, value)
        %ONXZOOMCHANGED  Zoom about the axes' current left edge (see the
        %   class header).
            this.XZoomValue = value;
            this.applyXLim(this.Axes.XLim(1));
        end

        function applyXLim(this, left)
        %APPLYXLIM  Show the zoomed width of the frequency range from LEFT,
        %   moved in where needed so that the window stays inside
        %   [0, Nyquist].
            width = this.Nyquist * this.zoomFraction(this.XZoomValue);
            left = min(max(left, 0), this.Nyquist - width);
            xlim(this.Axes, [left, left + width]);
        end

        function onYZoomChanged(this, value)
            this.YZoomValue = value;
            this.applyYLim();
        end

        function applyYLim(this)
        %APPLYYLIM  Apply the natural y-range, zoomed by the y-zoom slider:
        %   towards 0 on a linear axis, and from the bottom up on a log axis
        %   (see applyYZoom).
            f = this.zoomFraction(this.YZoomValue);
            if strcmp(this.Axes.YScale, 'log') && this.YBottom > 0
                ylim(this.Axes, [this.YBottom, this.YBottom * (this.YTop / this.YBottom) ^ f]);
            else
                ylim(this.Axes, [this.YBottom, this.YTop] * f);
            end
        end

        function f = zoomFraction(this, value)
        %ZOOMFRACTION  Exponential zoom mapping shared by x and y: 0 maps to
        %   the full range, 1 maps to MinFraction of it -- matching
        %   SignalView's own ZoomDecay-based zoom-slider mapping.
            f = this.MinFraction ^ value;
        end
    end
end
