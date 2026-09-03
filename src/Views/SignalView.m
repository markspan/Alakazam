classdef SignalView < AlakazamView
%SIGNALVIEW  Fast scrolling view of a continuous multichannel signal.
%
%   SignalView draws a continuous EEGLAB dataset into a scrollable, zoomable
%   axes with scroll / zoom / scale sliders and mouse-wheel scrolling
%   (channel stacking, fixed or dynamic y-limits, and event / area overlays
%   taken from the EEG structure), plus a vertical scrollbar that pages
%   through the channels once there are more than fit legibly at once,
%   driving the decimation from a precomputed
%   MinMaxPyramid, so each redraw costs O(pixels) instead of O(visible
%   samples). This is what lets long recordings scroll and zoom without lag.
%
%   Construction (name-value options via an arguments block):
%     SignalView(parent, times, eeg)
%     SignalView(parent, times, eeg, "YLimMode", "fixed", "MmPerSec", 25, ...)
%
%   The dataset is EEGLAB-oriented (channels x samples); times is the sample
%   time vector. Sampling is assumed uniform (as it is for EEGLAB continuous
%   data). Overlays are read from eeg.event when present.
%
%   Style follows the project standard: UpperCamelCase class and properties,
%   lowerCamelCase methods, double quotes except where a char array is required
%   by a graphics API (HG property names in some legacy calls, cursor/label).
%
%   See also MINMAXPYRAMID, ALAKAZAMPLOTTER.

    properties
    end

    properties (SetAccess = private)
        Parent          % figure or container the view is drawn into
        Grid            % 4x1 uigridlayout: axes | zoom row | pan row | mag row
        Axes            % axes the signal is drawn in
        Lines           % 1 x nchan array of line handles (one per channel)
        ScrollSlider    % uislider, horizontal position (pan)
        ZoomSlider      % uislider, time span shown (zoom)
        ScaleSlider     % uislider, amplitude gain (magnify y)
        ChannelSlider   % uislider (vertical), pages through channels when
                        % there are more than MaxVisibleChannels; empty otherwise
        PanLabel        % uilabel, "pan" label left of the scroll slider
        ZoomLabel       % uilabel, "zoom" label left of the zoom slider
        MagLabel        % uilabel, "mag" label left of the scale slider
        ScrollStep = 0.01 % wheel-scroll step, as a fraction of the slider's
                          % range (uislider has no SliderStep/major-step
                          % concept the way a classic uicontrol slider did;
                          % updateScrollStep keeps this sized to the visible
                          % window fraction instead)

        Pyramid         % MinMaxPyramid over the signal, the decimation engine
        Time            % NumSamples x 1 double, sample times
        Y               % NumSamples x nchan double, signal (columns are channels)
        NumSamples      % double
        Period          % double, sample period (seconds)

        Options         % struct of resolved name-value options
        StackOffset     % 1 x nchan, vertical offset per channel (stacking)
        StackTick       % 1 x nchan, y-tick position per channel
        LaneSpacing = 0 % double, per-channel lane height in stacked mode
        ChannelScroll = false % logical, whether the channel scrollbar is active
        FixedYLim       % 1 x 2, y-limits used in "fixed" mode
        Overlay         % struct of parsed event / area overlay data

        AxWidthPx = 100 % axes width in pixels, refreshed every redraw
        AxWidthCm = 100 % axes width in centimetres, refreshed every redraw
        ZoomDecay       % double, maps the zoom slider to a visible sample count
        MmPerSecDone = false % whether the initial mmPerSec zoom has been applied
    end

    properties (Constant, Access = private)
        LabelWidthPx = 40  % slider row's label column width, pixels
        SliderRowPx  = 24  % each slider row's height, pixels
        MaxVisibleChannels = 40 % above this many channels a vertical scrollbar
                                % pages through them, showing this many at a time
        ChannelSliderPx = 18    % width of that scrollbar's column, pixels
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
                opts.MaxEvents (1,1) double = 100
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
            % A first redraw happens before the grid has laid out the axes
            % to its real size (AxWidthPx/AxWidthCm read a placeholder), so
            % the initial mmPerSec zoom (applied inside redraw once a real
            % width is seen) is deferred to this second pass, after drawnow
            % lets layout settle.
            drawnow;
            this.redraw();
        end

        function redraw(this)
        %REDRAW  Redraw the visible window at the current scroll/zoom/scale.
        %   Reads about one min/max column per pixel from the pyramid (or the
        %   raw samples when the window already fits the axis), applies the
        %   amplitude gain and channel stacking, and refreshes the overlays.
            if isempty(this.Lines) || ~all(isgraphics(this.Lines))
                return;
            end

            % uiaxes.Position is always in pixels (no Units toggling needed,
            % unlike the classic axes/uipanel this replaced). Refreshed here
            % rather than from a SizeChangedFcn: a uigridlayout manages the
            % axes' size on its own, and this is cheap enough to redo on
            % every redraw (already called on every slider interaction).
            axPos = this.Axes.Position;
            this.AxWidthPx = max(1, round(axPos(3)));
            pxPerInch = get(0, "ScreenPixelsPerInch");
            this.AxWidthCm = this.AxWidthPx / pxPerInch * 2.54;

            % Apply the requested mmPerSec once, by converting it to a zoom
            % value -- but only once the grid has actually laid the axes out
            % to a real size (a first call, right after construction, still
            % sees the figure's placeholder pre-layout size).
            if ~this.MmPerSecDone && this.Options.MmPerSec > 0 && this.AxWidthPx > 1
                numPoints = this.AxWidthCm * 10 / (this.Options.MmPerSec * this.Period);
                zoomValue = log(numPoints / this.NumSamples) / this.ZoomDecay;
                this.ZoomSlider.Value = min(1, max(0, zoomValue));
                this.MmPerSecDone = true;
            end

            scrollValue = this.ScrollSlider.Value;
            zoomValue   = this.ZoomSlider.Value;
            scaleValue  = this.ScaleSlider.Value;

            % Visible sample window from scroll and zoom: zoom 0 shows all N,
            % zoom 1 shows about 7.
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

        function onWheel(this, callbackData)
        %ONWHEEL  Scroll horizontally with the mouse wheel.
        %   Public (not the private helper it used to be): every open
        %   dataset is now a uitab on one shared uifigure, so wheel events
        %   are dispatched centrally by Alakazam.dispatchWheel, which looks
        %   up the SignalView for the currently selected tab and calls this
        %   directly, rather than each view wiring its own
        %   fig.WindowScrollWheelFcn (see buildGraphics).
            limits = this.ScrollSlider.Limits;
            val = this.ScrollSlider.Value + callbackData.VerticalScrollCount * this.ScrollStep;
            val = min(limits(2), max(limits(1), val));
            this.ScrollSlider.Value = val;
            this.redraw();
            this.notifyActivated();
        end

    end

    methods (Access = private)
        function buildGraphics(this, lineSpec, eeg)
        %BUILDGRAPHICS  Create the grid, axes, per-channel lines and sliders.
            % Wheel scrolling is wired by the shared Alakazam-level dispatcher
            % (Alakazam.dispatchWheel), not here: every open dataset is now a
            % uitab on one shared uifigure, so a per-view
            % fig.WindowScrollWheelFcn would be overwritten by whichever
            % SignalView was constructed last, breaking wheel-scroll on every
            % other open tab.

            % Row 1 (the axes) gets the remaining space; rows 2-4 are the
            % zoom/pan/mag slider rows, matching the old bottom-up ordering
            % (uipanel's own Position, normalized with y growing upward, put
            % zoom first, then pan, then mag, with the axes above them all).
            % Column 2 (row 1 only) holds the vertical channel scrollbar when
            % there are more channels than fit legibly at once; its width
            % collapses to 0 otherwise, so the layout is unchanged in the
            % common case.
            nchan = size(this.Y, 2);
            stacked = ~isempty(this.Options.AutoStackSignals) && strcmp(this.Options.YLimMode, "fixed");
            this.ChannelScroll = stacked && nchan > this.MaxVisibleChannels;
            channelSliderCol = 0;
            if this.ChannelScroll
                channelSliderCol = this.ChannelSliderPx;
            end
            this.Grid = uigridlayout(this.Parent, [4 2], ...
                "RowHeight", {'1x', this.SliderRowPx, this.SliderRowPx, this.SliderRowPx}, ...
                "ColumnWidth", {'1x', channelSliderCol}, ...
                "Padding", [2 2 2 2], "RowSpacing", 2, "ColumnSpacing", 2);
            this.Axes = uiaxes(this.Grid, "TickLabelInterpreter", "none");
            this.Axes.Layout.Row = 1;
            this.Axes.Layout.Column = 1;
            % Custom wheel scrolling needs uiaxes' own built-in scroll/drag
            % interactions disabled so they do not fight it.
            disableDefaultInteractivity(this.Axes);
            this.Axes.ButtonDownFcn = @(~, ~) this.notifyActivated();

            % Vertical channel scrollbar (only when there are too many channels
            % to read at once). Value 1 = top of the stack, 0 = bottom; it just
            % pans the y-limit window over the fixed stack (see onChannelScroll
            % / channelWindowYLim), leaving the stacking itself untouched.
            if this.ChannelScroll
                this.ChannelSlider = uislider(this.Grid, "Orientation", "vertical", ...
                    "Limits", [0, 1], "Value", 1, "MajorTicks", [], "MinorTicks", [], ...
                    "Tooltip", "Scroll through channels", ...
                    "ValueChangingFcn", @(src, e) this.onChannelScrollChanging(src, e), ...
                    "ValueChangedFcn", @(~, ~) this.onChannelScroll());
                this.ChannelSlider.Layout.Row = 1;
                this.ChannelSlider.Layout.Column = 2;
            end

            nchan = size(this.Y, 2);
            this.Lines = gobjects(1, nchan);
            hold(this.Axes, "on");
            for c = 1:nchan
                this.Lines(c) = plot(this.Axes, nan, nan, lineSpec);
            end
            hold(this.Axes, "off");
            this.Axes.XAxis.Exponent = 0;
            this.Axes.YAxis.Exponent = 0;

            [this.ZoomLabel, this.ZoomSlider]   = this.makeSliderRow(2, 0, 1, 0.5, "Zoom the time axis");
            [this.PanLabel, this.ScrollSlider]  = this.makeSliderRow(3, 0, 1, 0,   "Pan the signal in time");
            [this.MagLabel, this.ScaleSlider]   = this.makeSliderRow(4, 0.001, 100, 1, "Magnify the y-axis");
            this.ZoomLabel.Text = "zoom";
            this.PanLabel.Text  = "pan";
            this.MagLabel.Text  = "mag";

            this.applyAxisLabels(eeg);
        end

        function [lbl, s] = makeSliderRow(this, row, lo, hi, val, tip)
        %MAKESLIDERROW  One grid row: a label plus a slider that redraws
        %   while dragging (ValueChangingFcn) and on release (ValueChangedFcn).
            row2 = uigridlayout(this.Grid, [1 2], ...
                "ColumnWidth", {this.LabelWidthPx, '1x'}, "Padding", [0 0 0 0]);
            row2.Layout.Row = row;
            row2.Layout.Column = [1, 2]; % full width, under both the axes and the channel scrollbar
            lbl = uilabel(row2, "HorizontalAlignment", "right", "FontSize", 8);
            lbl.Layout.Column = 1;
            s = uislider(row2, "Limits", [lo, hi], "Value", val, ...
                "MajorTicks", [], "MinorTicks", [], "Tooltip", tip, ...
                "ValueChangingFcn", @(src, e) this.onSliderChanging(src, e), ...
                "ValueChangedFcn", @(~, ~) this.redraw());
            s.Layout.Column = 2;
        end

        function onSliderChanging(this, src, event)
        %ONSLIDERCHANGING  Live-drag redraw: sync the slider's own Value to
        %   the in-progress value (uislider does not update it until the
        %   drag ends) before reusing the same redraw() the rest of the view
        %   already relies on.
            src.Value = event.Value;
            this.redraw();
            this.notifyActivated();
        end

        function onChannelScrollChanging(this, src, event)
        %ONCHANNELSCROLLCHANGING  Live-drag of the channel scrollbar. Only the
        %   y-limit window moves, so this repositions it directly rather than
        %   going through the full redraw() the time sliders use.
            src.Value = event.Value;
            this.onChannelScroll();
        end

        function onChannelScroll(this)
        %ONCHANNELSCROLL  Slide the visible y-window over the channel stack.
            yl = this.channelWindowYLim();
            if all(isfinite(yl)) && yl(2) > yl(1)
                set(this.Axes, "YLim", yl);
            end
            this.notifyActivated();
        end

        function yl = channelWindowYLim(this)
        %CHANNELWINDOWYLIM  Y-limits showing MaxVisibleChannels lanes, panned by
        %   the vertical scrollbar (Value 1 = top of the stack, 0 = bottom).
            tick = this.StackTick;
            spacing = this.LaneSpacing;
            fullHi = max(tick) + spacing / 2;
            fullLo = min(tick) - spacing / 2;
            windowHeight = this.MaxVisibleChannels * spacing;
            travel = max(0, (fullHi - fullLo) - windowHeight);
            s = this.ChannelSlider.Value;
            winHi = fullLo + windowHeight + s * travel;
            winLo = winHi - windowHeight;
            % A small margin, same idea as computeStacking's own FixedYLim
            % margin: without it, the window fits the visible lanes exactly,
            % so an event label anchored to the bottom (drawPointEvents) lands
            % right on top of the lowest visible channel's own trace instead
            % of in a clear gap below it -- easy to miss on a montage with
            % more than MaxVisibleChannels channels (this path is only taken
            % once channel scrolling kicks in).
            margin = windowHeight / 50;
            yl = [winLo - margin, winHi + margin];
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
                [this.StackTick, this.StackOffset, spacing] = this.autoStackNoOverlap(this.Y);
                this.LaneSpacing = spacing;
                this.applyStackTicks();
                % Y-limits span the evenly spaced channel lanes (each baseline
                % +/- half a lane), NOT the full excursion of the largest
                % channel: a channel far bigger than the rest overflows its own
                % lane and is clipped at the axis edge, instead of the axis
                % growing to contain its whole swing and squashing every other
                % channel into a near-flat line bunched in the middle (see
                % autoStackNoOverlap). The mag slider scales the traces against
                % these fixed lanes, so turning it up clips the big channels more.
                lo = min(this.StackTick) - spacing / 2;
                hi = max(this.StackTick) + spacing / 2;
                margin = (hi - lo) / 50;
                this.FixedYLim = [lo - margin, hi + margin];
            else
                this.StackTick   = zeros(1, nchan);
                this.StackOffset = zeros(1, nchan);
                % Non-stacked (single-channel) view: fixed y-limits from the
                % whole-signal range, with a small margin. Nothing is clipped.
                yPos = this.Y + this.StackOffset;
                lo = min(yPos(:));
                hi = max(yPos(:));
                margin = (hi - lo) / 50;
                this.FixedYLim = [lo - margin, hi + margin];
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
                % With more channels than fit legibly, show only a window of
                % them, positioned by the vertical channel scrollbar.
                if this.ChannelScroll
                    yl = this.channelWindowYLim();
                    if all(isfinite(yl)) && yl(2) > yl(1)
                        set(this.Axes, "YLim", yl);
                    end
                    return;
                end
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
        %UPDATESCROLLSTEP  Size the wheel-scroll step to the visible fraction
        %   (uislider has no SliderStep/major-step of its own -- see
        %   ScrollStep).
            if this.NumSamples <= numPoints
                this.ScrollStep = 0.1;
            else
                this.ScrollStep = max(1e-6, numPoints / (this.NumSamples - numPoints));
            end
        end

        function overlay = parseOverlays(~, eeg)
        %PARSEOVERLAYS  Extract point events and area events from eeg.event.
        %   Point events are those with duration < 1 and area events those
        %   with a longer duration. Missing fields degrade gracefully to
        %   empty overlays.
            overlay = struct( ...
                "EventTime", [], "EventLabel", string.empty, ...
                "AreaTime", [], "AreaDur", [], "AreaLabel", string.empty);

            if ~isfield(eeg, "event") || isempty(eeg.event)
                return;
            end
            try
                latency = [eeg.event.latency];
                dur = zeros(1, numel(eeg.event));
                if isfield(eeg.event, "duration")
                    filled = ~cellfun(@isempty, {eeg.event.duration});
                    dur(filled) = [eeg.event.duration];
                end
                types = string({eeg.event.type});

                isPoint = dur < 1;
                overlay.EventLabel = types(isPoint);
                overlay.EventTime  = eeg.times(max(1, round(latency(isPoint))));

                isArea = dur > 0;
                overlay.AreaLabel = types(isArea);
                overlay.AreaTime  = eeg.times(max(1, floor(latency(isArea))));
                overlay.AreaDur   = dur(isArea) / eeg.srate;
            catch
                % Leave overlays empty if the event structure is malformed.
            end
        end

        function drawOverlays(this, startTime, endTime)
        %DRAWOVERLAYS  Redraw the event / area markers within the window.
        %   Bounded by the Max* options so a dense window never floods the axes
        %   with cursors. Previous markers are cleared first.
            delete(findobj(this.Axes, "Tag", "event"));

            this.drawPointEvents(startTime, endTime);
            this.drawAreaEvents(startTime, endTime);
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
                    'Interpreter', 'none', ... % event codes are literal text, not TeX markup (a code with an underscore, e.g. "S_112", would otherwise render as a subscript, or vanish entirely for other TeX-special characters)
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
        function [tickPos, addVec, spacing] = autoStackNoOverlap(y)
        %AUTOSTACKNOOVERLAP  Evenly spaced channel lanes for fixed-mode stacking.
        %   Every channel gets an equal share of the y-axis, spaced by a single
        %   lane height derived from the TYPICAL (median-across-channels)
        %   channel scale, not the largest. A channel far bigger than the rest
        %   therefore overflows its lane and is clipped by the fixed y-limits
        %   (see computeStacking), rather than forcing the axis to grow to fit
        %   its full swing -- which used to squash every other channel into a
        %   near-flat line bunched in the middle (the whole signal made to "fit
        %   in the range"). Returns the per-channel tick positions, the offset
        %   added to each channel's samples (centred on its lane), and the lane
        %   height SPACING (used for the y-limits).
            n = size(y, 2);
            signalMed = median(y, 1, "omitnan");
            % Robust typical channel scale: the median across channels of each
            % channel's standard deviation, so one big channel does not move it.
            % std is base MATLAB (no Statistics Toolbox needed).
            sd = std(y, 0, 1, "omitnan");
            sd(~isfinite(sd)) = 0;
            scale = median(sd(sd > 0), "omitnan");
            if isempty(scale) || ~isfinite(scale) || scale <= 0
                scale = 1;
            end
            % One lane spans roughly +/-4 SD of a typical channel: typical
            % channels sit comfortably within their lane, while a channel
            % several times larger spills over and clips.
            spacing = 8 * scale;
            tickPos = -(0:n - 1) * spacing;   % evenly distributed baselines
            addVec  = tickPos - signalMed;    % centre each channel on its lane
        end

        function [tickPos, addVec] = autoStack(y)
        %AUTOSTACK  Compact vertical offsets per channel for dynamic mode.
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
