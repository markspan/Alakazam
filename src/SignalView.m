classdef SignalView < handle
%SIGNALVIEW  Fast scrolling view of a continuous multichannel signal.
%
%   SignalView draws a continuous EEGLAB dataset into a scrollable, zoomable
%   axes with scroll / zoom / scale sliders and mouse-wheel scrolling. It is
%   the clean replacement for the old Tools.plotECG, keeping the same on-screen
%   behaviour (channel stacking, fixed or dynamic y-limits, and the interbeat
%   interval / event / area overlays taken from the EEG structure) but driving
%   the decimation from a precomputed MinMaxPyramid, so each redraw costs
%   O(pixels) instead of O(visible samples). This is what lets long recordings
%   scroll and zoom without lag.
%
%   Construction (name-value options via an arguments block):
%     SignalView(parent, times, eeg)
%     SignalView(parent, times, eeg, "YLimMode", "fixed", "MmPerSec", 25, ...)
%
%   The dataset is EEGLAB-oriented (channels x samples); times is the sample
%   time vector. Sampling is assumed uniform (as it is for EEGLAB continuous
%   data). Overlays are read from eeg.IBIevent and eeg.event when present.
%
%   Style follows the project standard: UpperCamelCase class and properties,
%   lowerCamelCase methods, double quotes except where a char array is required
%   by a graphics API (HG property names in some legacy calls, cursor/label).
%
%   See also MINMAXPYRAMID, ALAKAZAMPLOTTER.

    properties (SetAccess = private)
        Parent          % figure or container the view is drawn into
        Panel           % uipanel holding the axes and sliders
        Axes            % axes the signal is drawn in
        Lines           % 1 x nchan array of line handles (one per channel)
        ScrollSlider    % uicontrol slider, horizontal position (pan)
        ZoomSlider      % uicontrol slider, time span shown (zoom)
        ScaleSlider     % uicontrol slider, amplitude gain (magnify y)
        PanLabel        % uicontrol text, "pan" label left of the scroll slider
        ZoomLabel       % uicontrol text, "zoom" label left of the zoom slider
        MagLabel        % uicontrol text, "mag" label left of the scale slider

        Pyramid         % MinMaxPyramid over the signal, the decimation engine
        Time            % NumSamples x 1 double, sample times
        Y               % NumSamples x nchan double, signal (columns are channels)
        NumSamples      % double
        Period          % double, sample period (seconds)

        Options         % struct of resolved name-value options
        StackOffset     % 1 x nchan, vertical offset per channel (stacking)
        StackTick       % 1 x nchan, y-tick position per channel
        FixedYLim       % 1 x 2, y-limits used in "fixed" mode
        Overlay         % struct of parsed IBI / event / area overlay data

        AxWidthPx = 100 % axes width in pixels, refreshed on resize
        AxWidthCm = 100 % axes width in centimetres, refreshed on resize
        ZoomDecay       % double, maps the zoom slider to a visible sample count
        MmPerSecDone = false % whether the initial mmPerSec zoom has been applied
    end

    properties (Constant, Access = private)
        Space = 0.05         % layout gap, centimetres
        SliderHeight = 0.35  % slider height, centimetres
        IbiColors = dictionary( ...
            ["N" "L" "S" "T" "1" "2" "i"], ...
            ["blue" "red" "red" "yellow" "green" "green" "magenta"])
    end

    methods
        function this = SignalView(parent, times, eeg, opts)
        %SIGNALVIEW  Build the view for one continuous dataset.
            arguments
                parent
                times double
                eeg struct
                opts.LineSpec (1,:) char = '-'
                opts.ShowAxisTicks (1,1) logical = true
                opts.YLimMode (1,1) string = "fixed"
                opts.MmPerSec (1,1) double = 25
                opts.AutoStackSignals string = string.empty
                opts.MaxIBIs (1,1) double = 175
                opts.MaxEvents (1,1) double = 30
                opts.MaxAreas (1,1) double = 20
            end
            this.Parent  = parent;
            this.Options = opts;

            % Orient the signal as samples x channels (EEG.data is channels x
            % samples) and keep the matching time vector.
            y = double(eeg.data);
            if size(y, 1) ~= numel(times)
                y = y.';
            end
            this.Y          = y;
            this.Time       = times(:);
            this.NumSamples = size(y, 1);
            this.Period     = median(diff(this.Time), "omitnan");
            this.ZoomDecay  = -log(this.NumSamples / 7); % zoom 0 -> N, zoom 1 -> ~7

            % Decimation engine and overlay data.
            this.Pyramid = MinMaxPyramid(this.Y);
            this.Overlay = this.parseOverlays(eeg);

            this.buildGraphics(opts.LineSpec, eeg);
            this.computeStacking();
            this.redraw();
            this.resize();
        end

        function redraw(this)
        %REDRAW  Redraw the visible window at the current scroll/zoom/scale.
        %   Reads about one min/max column per pixel from the pyramid (or the
        %   raw samples when the window already fits the axis), applies the
        %   amplitude gain and channel stacking, and refreshes the overlays.
            if isempty(this.Lines) || ~all(isgraphics(this.Lines))
                return;
            end
            scrollValue = this.ScrollSlider.Value;
            zoomValue   = this.ZoomSlider.Value;
            scaleValue  = this.ScaleSlider.Value;

            % Visible sample window from scroll and zoom (same mapping as the
            % original plotECG: zoom 0 shows all N, zoom 1 shows about 7).
            numPoints  = max(2, round(this.NumSamples * exp(this.ZoomDecay * zoomValue)));
            startIndex = max(1, round((this.NumSamples - numPoints) * scrollValue + 1));
            endIndex   = min(this.NumSamples, startIndex + numPoints);

            % Decimate: raw samples when the window already fits the axis,
            % otherwise a min/max envelope of about one column per pixel.
            targetColumns = max(1, this.AxWidthPx);
            if (endIndex - startIndex + 1) <= 2 * targetColumns
                idx  = (startIndex:endIndex)';
                xVis = this.Time(idx);
                yVis = this.Y(idx, :);
            else
                [sampleIdx, yEnv] = this.Pyramid.queryInterleaved(startIndex, endIndex, targetColumns);
                xVis = this.Time(sampleIdx);
                yVis = double(yEnv);
            end

            % Amplitude gain, then channel stacking offsets.
            yVis = yVis * scaleValue;
            if strcmp(this.Options.YLimMode, "dynamic") && ~isempty(this.Options.AutoStackSignals)
                [this.StackTick, this.StackOffset] = this.autoStack(yVis);
                this.applyStackTicks();
            end
            yVis = yVis + this.StackOffset;

            % Push data into the existing line objects (no re-creation).
            set(this.Lines, "XData", xVis);
            for c = 1:size(yVis, 2)
                set(this.Lines(c), "YData", yVis(:, c));
            end

            startTime = xVis(1);
            endTime   = xVis(end);
            if endTime > startTime
                set(this.Axes, "XLim", [startTime, endTime]);
            end
            this.applyYLim(yVis);
            this.updateScrollStep(numPoints);
            this.drawOverlays(startTime, endTime);
        end
    end

    methods (Access = private)
        function buildGraphics(this, lineSpec, eeg)
        %BUILDGRAPHICS  Create the panel, axes, per-channel lines and sliders.
            fig = ancestor(this.Parent, "figure");
            % Custom wheel scrolling needs the interactive modes disabled.
            rotate3d(fig, "off");
            zoom(fig, "off");
            pan(fig, "off");
            fig.WindowScrollWheelFcn = @(~, e) this.onWheel(e);

            this.Panel = uipanel("Parent", this.Parent, "BorderWidth", 0, ...
                "Units", "normalized", "Position", [0 0 1 1], ...
                "SizeChangedFcn", @(~, ~) this.resize());
            this.Axes = axes("Parent", this.Panel, "TickLabelInterpreter", "none");

            nchan = size(this.Y, 2);
            this.Lines = gobjects(1, nchan);
            hold(this.Axes, "on");
            for c = 1:nchan
                this.Lines(c) = plot(this.Axes, nan, nan, lineSpec);
            end
            hold(this.Axes, "off");
            this.Axes.XAxis.Exponent = 0;
            this.Axes.YAxis.Exponent = 0;

            this.ScrollSlider = this.makeSlider(0, 1, 0,   "Pan the signal in time");
            this.ZoomSlider   = this.makeSlider(0, 1, 0.5, "Zoom the time axis");
            this.ScaleSlider  = this.makeSlider(0.001, 100, 1, "Magnify the y-axis");
            this.PanLabel  = this.makeLabel("pan");
            this.ZoomLabel = this.makeLabel("zoom");
            this.MagLabel  = this.makeLabel("mag");

            this.applyAxisLabels(eeg);
        end

        function s = makeSlider(this, lo, hi, val, tip)
        %MAKESLIDER  Create one slider that triggers a redraw while dragging.
            s = uicontrol("Parent", this.Panel, "Style", "slider", ...
                "Min", lo, "Max", hi, "Value", val, ...
                "SliderStep", [1e-4, 0.07], "TooltipString", tip, ...
                "Interruptible", "on", "Callback", @(~, ~) this.redraw());
            listener = addlistener(s, "ContinuousValueChange", @(~, ~) this.redraw());
            setappdata(s, "sliderListener", listener);
        end

        function t = makeLabel(this, text)
        %MAKELABEL  Create a static text label shown to the left of a slider.
            t = uicontrol("Parent", this.Panel, "Style", "text", ...
                "String", text, "HorizontalAlignment", "right", "FontSize", 8);
        end

        function applyAxisLabels(this, eeg)
        %APPLYAXISLABELS  Set axis ticks and labels per the ShowAxisTicks option.
            if ~this.Options.ShowAxisTicks
                set(this.Axes, "XTick", [], "YTick", []);
                return;
            end
            this.Axes.XLabel.String = "Time in s";
            this.Axes.TickLength = [0.001, 0.001];
            this.Axes.XMinorGrid = "on";
            if isempty(this.Options.AutoStackSignals)
                if isfield(eeg, "YLabel") && (ischar(eeg.YLabel) || isstring(eeg.YLabel))
                    this.Axes.YLabel.String = eeg.YLabel;
                else
                    this.Axes.YLabel.String = "Voltage in mV";
                end
            else
                this.Axes.YLabel.String = "Channel";
            end
        end

        function computeStacking(this)
        %COMPUTESTACKING  Fixed-mode channel offsets and y-limits (computed once).
            nchan = size(this.Y, 2);
            if ~isempty(this.Options.AutoStackSignals) && strcmp(this.Options.YLimMode, "fixed")
                [this.StackTick, this.StackOffset] = this.autoStackNoOverlap(this.Y);
                this.applyStackTicks();
            else
                this.StackTick   = zeros(1, nchan);
                this.StackOffset = zeros(1, nchan);
            end

            % Fixed y-limits from the whole-signal (unscaled) stacked range, with
            % a small margin, matching the original behaviour.
            yPos = this.Y + this.StackOffset;
            lo = min(yPos(:));
            hi = max(yPos(:));
            margin = (hi - lo) / 50;
            this.FixedYLim = [lo - margin, hi + margin];
            if nnz(this.StackTick) > 1
                this.FixedYLim(1) = min([this.FixedYLim(1), this.StackTick(:)']);
                this.FixedYLim(2) = max([this.FixedYLim(2), this.StackTick(:)']);
            end
        end

        function applyStackTicks(this)
        %APPLYSTACKTICKS  Label the y-axis with the (flipped) channel names.
            this.Axes.YTick = flip(this.StackTick);
            this.Axes.YTickLabel = flip(cellstr(this.Options.AutoStackSignals(:)));
            this.Axes.TickLabelInterpreter = "none";
        end

        function applyYLim(this, yVis)
        %APPLYYLIM  Fixed y-limits, or a padded data range in dynamic mode.
            if strcmp(this.Options.YLimMode, "fixed")
                if all(isfinite(this.FixedYLim)) && this.FixedYLim(2) > this.FixedYLim(1)
                    set(this.Axes, "YLim", this.FixedYLim);
                end
                return;
            end
            lo = min(yVis(:));
            hi = max(yVis(:));
            margin = (hi - lo) / 50;
            lo = lo - margin;
            hi = hi + margin;
            if nnz(this.StackTick) > 1
                lo = min([lo; this.StackTick(:)]);
                hi = max([hi; this.StackTick(:)]);
            end
            if isfinite(lo) && isfinite(hi) && hi > lo
                set(this.Axes, "YLim", [lo, hi]);
            end
        end

        function updateScrollStep(this, numPoints)
        %UPDATESCROLLSTEP  Size the scroll thumb to the visible fraction.
            if this.NumSamples <= numPoints
                step = [0.1, Inf];
            else
                major = max(1e-6, numPoints / (this.NumSamples - numPoints));
                minor = max(1e-6, numPoints / (100 * this.NumSamples));
                step = [minor, major];
            end
            set(this.ScrollSlider, "SliderStep", step);
        end

        function onWheel(this, callbackData)
        %ONWHEEL  Scroll horizontally with the mouse wheel.
            step = this.ScrollSlider.SliderStep(2);
            val = this.ScrollSlider.Value + callbackData.VerticalScrollCount * step;
            val = min(this.ScrollSlider.Max, max(this.ScrollSlider.Min, val));
            this.ScrollSlider.Value = val;
            this.redraw();
        end

        function resize(this)
        %RESIZE  Lay out the axes and sliders and refresh the axis pixel width.
            if isempty(this.Panel) || ~isgraphics(this.Panel)
                return;
            end
            oldUnits = this.Panel.Units;
            set([this.Panel, this.Axes, this.ScaleSlider, this.ScrollSlider, this.ZoomSlider, ...
                 this.ZoomLabel, this.PanLabel, this.MagLabel], "Units", "centimeters");
            width  = this.Panel.Position(3);
            height = this.Panel.Position(4);
            sp = this.Space;
            hgt = this.SliderHeight;

            % Each slider row is a small text label on the left plus the slider.
            labelW  = 1.4;                                 % label column width (cm)
            sliderX = sp + labelW;
            sliderW = max(0, width - 2 * sp - labelW);

            y = sp;
            set(this.ZoomLabel,    "Position", [sp, y, labelW, hgt]);
            set(this.ZoomSlider,   "Position", [sliderX, y, sliderW, hgt]); y = y + hgt + sp;
            set(this.PanLabel,     "Position", [sp, y, labelW, hgt]);
            set(this.ScrollSlider, "Position", [sliderX, y, sliderW, hgt]); y = y + hgt + sp;
            set(this.MagLabel,     "Position", [sp, y, labelW, hgt]);
            set(this.ScaleSlider,  "Position", [sliderX, y, sliderW, hgt]); y = y + hgt + sp;

            if this.Options.ShowAxisTicks
                insets = get(this.Axes, "TightInset");
            else
                insets = [0 0 0 0];
            end
            pos = [sp + insets(1), y + insets(2), ...
                   max(1, width - 3 * sp) - insets(1) - insets(3), ...
                   max(1, height - 1.6 * y) - insets(2) - insets(4)];
            set(this.Axes, "Position", max(pos, [0 0 0 0]));

            % Refresh cached axis width in centimetres and pixels.
            w = get(this.Axes, "Position"); this.AxWidthCm = max(0, w(3));
            set(this.Axes, "Units", "pixels");
            w = get(this.Axes, "Position"); this.AxWidthPx = max(1, round(w(3)));
            set(this.Panel, "Units", oldUnits);

            % Apply the requested mmPerSec once, by converting it to a zoom value.
            if ~this.MmPerSecDone && this.Options.MmPerSec > 0 && this.AxWidthCm > 0
                numPoints = this.AxWidthCm * 10 / (this.Options.MmPerSec * this.Period);
                zoomValue = log(numPoints / this.NumSamples) / this.ZoomDecay;
                this.ZoomSlider.Value = min(1, max(0, zoomValue));
                this.MmPerSecDone = true;
            end
            this.redraw();
        end

        function overlay = parseOverlays(~, eeg)
        %PARSEOVERLAYS  Extract IBI markers, point events and area events.
        %   Ported from plotECG: point events are those with duration < 1 and
        %   area events those with a longer duration. Missing fields degrade
        %   gracefully to empty overlays.
            overlay = struct("IbiEvents", {{}}, ...
                "EventTime", [], "EventLabel", string.empty, ...
                "AreaTime", [], "AreaDur", [], "AreaLabel", string.empty);

            if isfield(eeg, "IBIevent")
                overlay.IbiEvents = eeg.IBIevent;
            end

            if ~isfield(eeg, "event") || isempty(eeg.event)
                return;
            end
            try
                latency = [eeg.event.latency];
                dur = ones(1, numel(eeg.event));
                if isfield(eeg.event, "duration")
                    filled = ~cellfun(@isempty, {eeg.event.duration});
                    dur(filled) = [eeg.event.duration];
                end
                types = string({eeg.event.type});

                isPoint = dur < 1;
                overlay.EventLabel = types(isPoint);
                overlay.EventTime  = eeg.times(latency(isPoint));

                isArea = dur > 0;
                codes = repmat("-", 1, numel(eeg.event));
                if isfield(eeg.event, "code")
                    codes = string({eeg.event.code});
                end
                overlay.AreaLabel = codes(isArea) + " - " + types(isArea);
                overlay.AreaTime  = eeg.times(max(1, floor(latency(isArea))));
                overlay.AreaDur   = dur(isArea) / eeg.srate;
            catch
                % Leave overlays empty if the event structure is malformed.
            end
        end

        function drawOverlays(this, startTime, endTime)
        %DRAWOVERLAYS  Redraw the IBI / event / area markers within the window.
        %   Bounded by the Max* options so a dense window never floods the axes
        %   with cursors. Previous markers are cleared first.
            delete(findobj(this.Axes, "Tag", "ibi"));
            delete(findobj(this.Axes, "Tag", "event"));

            this.drawIbiMarkers(startTime, endTime);
            this.drawPointEvents(startTime, endTime);
            this.drawAreaEvents(startTime, endTime);
        end

        function drawIbiMarkers(this, startTime, endTime)
        %DRAWIBIMARKERS  Colour-coded interbeat-interval cursors in the window.
            for i = 1:numel(this.Overlay.IbiEvents)
                ibi = this.Overlay.IbiEvents{i};
                rTop = ibi.RTopTime;
                visible = (rTop > startTime) & (rTop < endTime);
                visible = visible(1:numel(ibi.ibis));
                times = rTop(visible);
                labels = ibi.ibis(visible);
                classes = ibi.classID(visible);
                if numel(times) >= this.Options.MaxIBIs
                    continue;
                end
                for r = 1:numel(times)
                    if i == 1 && isKey(this.IbiColors, classes(r))
                        colour = this.IbiColors(classes(r));
                    else
                        colour = "blue";
                    end
                    cursor(this.Axes, times(r), [], @uiextras.delCursor, ...
                        'Color', colour, 'LineStyle', '-.', ...
                        'Label', strcat(classes(r), " - ", num2str(labels(r))), ...
                        'LabelVerticalAlignment', 'top', ...
                        'LabelHorizontalAlignment', 'right', ...
                        'Tag', 'ibi', 'ID', [i r]);
                end
            end
        end

        function drawPointEvents(this, startTime, endTime)
        %DRAWPOINTEVENTS  Blue cursors for zero-duration events in the window.
            visible = (this.Overlay.EventTime > startTime) & (this.Overlay.EventTime < endTime);
            times = this.Overlay.EventTime(visible);
            labels = this.Overlay.EventLabel(visible);
            if numel(times) >= this.Options.MaxEvents
                return;
            end
            for r = 1:numel(times)
                cursor(this.Axes, times(r), [], [], ...
                    'Color', [.1 .3 .8 .5], 'LineStyle', ':', ...
                    'Label', labels(r), ...
                    'LabelVerticalAlignment', 'bottom', ...
                    'LabelHorizontalAlignment', 'center', ...
                    'LabelOrientation', 'horizontal', 'FontSize', 8, ...
                    'Tag', 'event', 'UserData', r);
            end
        end

        function drawAreaEvents(this, startTime, endTime)
        %DRAWAREAEVENTS  Shaded labelled areas whose start is in the window.
            visible = (this.Overlay.AreaTime > startTime) & (this.Overlay.AreaTime < endTime);
            times = this.Overlay.AreaTime(visible);
            durs = this.Overlay.AreaDur(visible);
            labels = this.Overlay.AreaLabel(visible);
            if numel(times) >= this.Options.MaxAreas
                return;
            end
            for r = 1:numel(times)
                label(this.Axes, times(r), durs(r), labels(r), [.1 .8 .7], [], [], ...
                    'EdgeColor', [.1 .8 .5], 'FaceAlpha', .15, 'EdgeAlpha', .25, ...
                    'Tag', 'event', 'UserData', r);
            end
        end
    end

    methods (Access = private, Static)
        function [tickPos, addVec] = autoStackNoOverlap(y)
        %AUTOSTACKNOOVERLAP  Even, non-overlapping vertical offsets per channel.
        %   Ported from plotECG's fixed-mode stacking (evenly spaced channels).
            signalMed = median(y, 1, "omitnan");
            centred = y - signalMed;
            overlap = min(centred(:, 1:end-1), [], 1) - max(centred(:, 2:end), [], 1);
            overlap(isnan(overlap)) = 0;
            overlap(isinf(overlap)) = 1e5;
            spacing = -overlap * 1.01;
            spacing = max(spacing, max(spacing) / 1000 * ones(size(spacing)));
            spacing = max(eps, spacing);
            addVec = -(0:numel(signalMed) - 1) * mean(spacing);
            tickPos = addVec;
        end

        function [tickPos, addVec] = autoStack(y)
        %AUTOSTACK  Compact vertical offsets per channel for dynamic mode.
        %   Ported from plotECG's dynamic-mode stacking.
            signalMed = median(y, 1, "omitnan");
            centred = y - signalMed;
            overlap = diff(centred, 1, 2);
            overlap(isnan(overlap)) = 0;
            overlapSorted = sort(overlap, 1, "descend");
            index = max(1, round(size(overlapSorted, 1) * 0.007));
            spacing = overlapSorted(index, :) * 1.1;
            stdd = std(centred, 1, 1);
            stdd = min(stdd(1:end-1), stdd(2:end));
            spacing = max(spacing, median(spacing, "omitnan") * 0.5);
            spacing = max(spacing, stdd * 4);
            spacing = max(spacing, max(spacing) / 1000 * ones(size(spacing)));
            spacing = max(eps, spacing);
            tickPos = -cumsum([0 spacing]);
            addVec = tickPos - signalMed;
        end
    end
end
