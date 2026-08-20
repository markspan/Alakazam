classdef ZoomPanButtons < handle
%ZOOMPANBUTTONS  Axes zoom/pan controls: button row + zoom sliders.
%   FourierView and SpectralMeasureView both build this at the bottom of
%   their grid: an optional leading "C^"/"Cv" button pair that steps the
%   CHANNEL (via CHANNELSTEPFCN), pan buttons "<"/">" that shift the
%   frequency axis, an optional trailing "<<"/">>" pair that steps
%   whatever secondary dimension the owning view has (trial for
%   FourierView, bin for SpectralMeasureView) via STEPFCN -- plus an
%   "x zoom"/"y zoom" slider pair below the button row, styled like
%   SignalView's own zoom/pan/mag slider rows (see its makeSliderRow). The
%   x-zoom slider anchors at the LEFT edge of the current window (0 Hz
%   stays at 0 Hz unless the user has explicitly panned away from it, see
%   onXZoomChanged), not the window's centre: 0 Hz is a meaningful
%   reference for a spectrum, not an arbitrary scroll position, so zooming
%   in should not drift away from it on its own.
%   Every button carries a Tooltip naming what it does and its keyboard
%   equivalent, since a 1-2 character button label alone does not carry
%   that on its own.
%
%   ZoomPanButtons owns the x-axis range outright: Nyquist is fixed for
%   the owning view's whole life, so pan and x-zoom are both self
%   contained here, applied to AX directly, and never touched by the
%   owning view's own redraw. The y-axis range is different -- each
%   channel/trial/bin has its own natural amplitude scale, known only to
%   the owning view -- so the owning view calls APPLYYZOOM(naturalTop) at
%   the end of its own redraw() (in place of a bare ylim(ax,[0,top])),
%   which applies the CURRENT y-zoom slider value relative to that fresh
%   natural top. This is what keeps "how zoomed in" stable across a
%   channel/trial/bin change, rather than snapping back to fully-zoomed-
%   out on every redraw the way a plain ylim(ax,[0,top]) used to.
%
%   AX and NYQUIST are captured once at construction, not read live from
%   the owning view on every interaction: both are fixed for the whole
%   life of either current caller (neither ever reassigns its own Axes or
%   swaps in a different EEG after construction).
%
%   See also FOURIERVIEW, SPECTRALMEASUREVIEW, SIGNALVIEW.

    properties (Access = private)
        Axes
        Nyquist        % upper x-limit clamp (EEG.srate / 2)
        ActivatedFcn   % function handle (), or empty

        XStart = 0     % Hz, left edge of the visible x-window
        XZoomValue = 0 % 0..1, x-zoom slider value (0 = full range)
        YZoomValue = 0 % 0..1, y-zoom slider value (0 = full natural range)
        YTop = 1       % most recent natural top passed to applyYZoom
    end

    properties (Constant, Access = private)
        MinFraction = 0.01 % narrowest zoom, as a fraction of the full range
        LabelWidthPx = 40
    end

    methods
        function this = ZoomPanButtons(grid, rows, ax, nyquist, activatedFcn, stepFcn, channelStepFcn, stepLabel)
        %ZOOMPANBUTTONS  Build the button row into GRID's ROWS(1), the
        %   x-zoom slider into ROWS(2) and the y-zoom slider into ROWS(3).
        %   ACTIVATEDFCN(), if non-empty, is called before every button's
        %   own action, and before every slider drag/release (mirroring the
        %   owning view's own notifyActivated). STEPFCN(delta), if given and
        %   non-empty, adds a trailing step-button pair calling
        %   STEPFCN(-1)/STEPFCN(1), labelled with the first letter of
        %   STEPLABEL (e.g. 'Bin' -> "B<"/"B>"; defaults to "Trial" if
        %   omitted); omit STEPFCN (or pass empty) to skip the pair
        %   entirely. CHANNELSTEPFCN(delta), if given and non-empty, adds
        %   the leading "C^"/"Cv" pair calling CHANNELSTEPFCN(-1)/
        %   CHANNELSTEPFCN(1); omit (or pass empty) to skip it too, so a
        %   caller with only one navigable dimension (or none) is not
        %   forced to pass both.
            if nargin < 8 || isempty(stepLabel)
                stepLabel = 'Trial';
            end
            this.Axes = ax;
            this.Nyquist = nyquist;
            this.ActivatedFcn = activatedFcn;

            this.buildButtonRow(grid, rows(1), stepFcn, channelStepFcn, char(stepLabel));
            this.makeSliderRow(grid, rows(2), "x zoom", "Zoom the frequency axis", @(v) this.onXZoomChanged(v));
            this.makeSliderRow(grid, rows(3), "y zoom", "Zoom the amplitude axis", @(v) this.onYZoomChanged(v));

            this.applyXLim();
        end

        function applyYZoom(this, naturalTop)
        %APPLYYZOOM  Set the y-limits to the current y-zoom slider value,
        %   relative to NATURALTOP (the owning view's own auto-scale for
        %   whatever channel/trial/bin is now shown). Call at the end of the
        %   owning view's redraw(), in place of a bare ylim(ax,[0,top]).
            if ~isfinite(naturalTop) || naturalTop <= 0
                naturalTop = 1;
            end
            this.YTop = naturalTop;
            ylim(this.Axes, [0, naturalTop * this.zoomFraction(this.YZoomValue)]);
        end
    end

    methods (Access = private)
        function buildButtonRow(this, grid, row, stepFcn, channelStepFcn, stepLabel)
        %BUILDBUTTONROW  Channel-step / pan / trial-or-bin-step buttons
        %   (zoom moved to the slider rows below -- see the class header
        %   comment). Every button carries a one-letter prefix naming what
        %   it moves (C = channel, P = pan the view, the step pair's own
        %   initial, e.g. B = bin): a bare "<"/">" for BOTH pan and step
        %   used to read as the same control, which is exactly what made a
        %   pan click look like "the bin/trial never changes" -- it moves
        %   the visible x-range, not which bin/trial is shown, so nothing
        %   about panning was ever going to change a bin label.
            labels    = {"P<", "P>"};
            tooltips  = {"Pan left (shifts the visible frequency range)", ...
                         "Pan right (shifts the visible frequency range)"};
            callbacks = {@() this.panX(-1), @() this.panX(1)};
            if ~isempty(channelStepFcn)
                labels    = [{"C^", "Cv"}, labels];
                tooltips  = [{"Previous channel (Up arrow)", "Next channel (Down arrow)"}, tooltips];
                callbacks = [{@() channelStepFcn(-1), @() channelStepFcn(1)}, callbacks];
            end
            if ~isempty(stepFcn)
                letter = upper(stepLabel(1));
                labels    = [labels, {[letter '<'], [letter '>']}];
                tooltips  = [tooltips, {sprintf('Previous %s (Left arrow)', lower(stepLabel)), ...
                                        sprintf('Next %s (Right arrow)', lower(stepLabel))}];
                callbacks = [callbacks, {@() stepFcn(-1), @() stepFcn(1)}];
            end
            n = numel(labels);
            btnGrid = uigridlayout(grid, [1, n + 1], "Padding", [0 0 0 0], ...
                "ColumnWidth", [repmat({30}, 1, n), {'1x'}], "ColumnSpacing", 4);
            btnGrid.Layout.Row = row;
            for i = 1:n
                b = uibutton(btnGrid, "Text", labels{i}, "Tooltip", tooltips{i}, ...
                    "ButtonPushedFcn", @(~, ~) this.onButtonPushed(callbacks{i}));
                b.Layout.Column = i;
            end
        end

        function makeSliderRow(this, grid, row, labelText, tip, changedFcn)
        %MAKESLIDERROW  One grid row: a label plus a 0..1 slider that fires
        %   CHANGEDFCN(value) while dragging and on release, matching
        %   SignalView's own zoom/pan/mag rows.
            row2 = uigridlayout(grid, [1 2], "ColumnWidth", {this.LabelWidthPx, '1x'}, "Padding", [0 0 0 0]);
            row2.Layout.Row = row;
            lbl = uilabel(row2, "Text", labelText, "HorizontalAlignment", "right", "FontSize", 8);
            lbl.Layout.Column = 1;
            s = uislider(row2, "Limits", [0, 1], "Value", 0, ...
                "MajorTicks", [], "MinorTicks", [], "Tooltip", tip, ...
                "ValueChangingFcn", @(src, e) this.onSliderChanging(src, e, changedFcn), ...
                "ValueChangedFcn", @(src, ~) this.onSliderChanged(src, changedFcn));
            s.Layout.Column = 2;
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

        function onXZoomChanged(this, value)
        %ONXZOOMCHANGED  Zoom about the LEFT edge (XStart unchanged), not the
        %   window's centre: 0 Hz is a meaningful anchor for a spectrum, not
        %   an arbitrary scroll position, so it stays at 0 Hz across a zoom
        %   change unless the user has explicitly panned away from it.
            this.XZoomValue = value;
            this.applyXLim();
        end

        function onYZoomChanged(this, value)
            this.YZoomValue = value;
            ylim(this.Axes, [0, this.YTop * this.zoomFraction(value)]);
        end

        function onButtonPushed(this, callback)
        %ONBUTTONPUSHED  A pan/step button was pushed: mark the owning view
        %   activated (via ActivatedFcn) before running its callback.
            this.notifyOwnerActivated();
            callback();
        end

        function notifyOwnerActivated(this)
            if ~isempty(this.ActivatedFcn)
                this.ActivatedFcn();
            end
        end

        function panX(this, direction)
        %PANX  Shift the visible x-window by a tenth of its width, clamped
        %   to [0, Nyquist].
            this.XStart = this.XStart + direction * this.currentWidth() / 10;
            this.applyXLim();
        end

        function applyXLim(this)
        %APPLYXLIM  Recompute and apply xlim from XStart/XZoomValue,
        %   clamping XStart so the window never runs past [0, Nyquist].
            width = this.currentWidth();
            this.XStart = min(max(this.XStart, 0), this.Nyquist - width);
            xlim(this.Axes, [this.XStart, this.XStart + width]);
        end

        function width = currentWidth(this)
            width = this.Nyquist * this.zoomFraction(this.XZoomValue);
        end

        function f = zoomFraction(this, value)
        %ZOOMFRACTION  Exponential zoom mapping shared by x and y: 0 maps to
        %   the full range, 1 maps to MinFraction of it -- matching
        %   SignalView's own ZoomDecay-based zoom-slider mapping.
            f = this.MinFraction ^ value;
        end
    end
end
