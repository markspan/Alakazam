classdef AverageView < AlakazamView
%AVERAGEVIEW  View of trial-averaged data with error bands, one line per bin.
%
%   AverageView draws the per-channel trial average of an averaged dataset
%   together with a +/- 3 standard-error band. A bin-aware average (produced by
%   Average on a DefineBins dataset) is drawn as one labelled line per bin;
%   a plain average is a single line. It replaces the old
%   Tools.plotEpochedTimeMultiAverage function with a clean stateful class.
%
%   OVERLAYS. Other averages can be drawn on the same axes (addDataset): the
%   tree's Overlay on ERP plot command, or dropping one average onto another.
%   Each line keeps its own time axis and each channel is found by its label,
%   so a resampled or re-referenced average overlays the original, and a
%   montage in another order still shows the same electrode on every line
%   (datasetOverlayProblem says when an overlay is not possible). Lines are named
%   by what tells their datasets apart in the tree (overlayNames). Overlaid
%   datasets are drawn underneath the plot's own and paler, by the Overlay
%   opacity slider, so the plot's own lines stay readable, and Remove
%   overlay takes them all off again.
%
%   DIFFERENCE. With exactly two lines ticked, the Difference button draws
%   the first minus the second instead (Swap reverses it): two bins of one
%   average, or the same bin before and after a step.
%
%   UP AND DOWN ONLY. Dragging the plot, and the axes toolbar's pan and
%   zoom, change the amplitude axis alone (InteractionOptions.
%   LimitsDimensions), the time axis staying as drawn. What they do is kept
%   for every channel and every redraw (keepUserZoom), so electrodes are
%   stepped through at the scale and offset chosen, until Restore view; the
%   difference keeps its own.
%
%   The up / down arrow keys, or the mouse wheel, step the displayed
%   channel for every line at once.
%
%   Style follows the project standard.
%
%   See also ALAKAZAMPLOTTER, EPOCHVIEW, FOURIERVIEW, DATASETOVERLAYPROBLEM,
%   OVERLAYNAMES.

    properties
    end

    properties (SetAccess = private)
        Figure          % owning figure
        Grid            % 2x2 uigridlayout: channel dropdown row, then axes | checkbox strip
        ChannelDropdown % "Channel:" uidropdown (see TransTools.BuildChannelDropdown), row 1
        Axes            % axes the averages are drawn in
        CheckboxGrid    % uigridlayout the tickboxes stack into (right strip)
        Series          % flat cell array of per-line series structs
        Channel = 1     % index, in the plot's own labels, of the channel shown
        Visible         % logical row vector, one per series: line shown?
        DifferenceOn = false       % drawing the first ticked line minus the second?
        DifferenceSwapped = false  % ... or the second minus the first
        OverlayOpacity = 0.5       % how strongly overlaid datasets are drawn, 0.1 to 1
        AmplitudeLabel = "Amplitude (\muV)"   % the y axis: microvolts, or a source estimate's scale
    end

    properties (Access = private)
        Paths           % containers.Map: dataset file -> its tree path (cellstr)
        % A zoom or pan made with the axes toolbar, kept across redraws (see
        % keepUserZoom): the time range, shared by both modes, and the
        % amplitude range per mode, since a difference has its own scale.
        % Empty while the view scales itself.
        ZoomX = []
        ZoomY = struct('lines', [], 'difference', [])
        LastLimits = struct('x', [], 'y', [], 'mode', 'lines')   % what redraw last set
    end

    methods
        function this = AverageView(fig, eeg)
        %AVERAGEVIEW  Build the view for an averaged dataset in FIG.
            this.Figure = fig;
            % Region time courses (SourceRegions) are a source estimate's
            % scale, dSPM or sLORETA, not microvolts, and the axis says so.
            if isstruct(eeg) && isfield(eeg, 'etc') && isstruct(eeg.etc) && isfield(eeg.etc, 'alz') ...
                    && isstruct(eeg.etc.alz) && isfield(eeg.etc.alz, 'sourceRegions') ...
                    && isfield(eeg.etc.alz.sourceRegions, 'scaleLabel') ...
                    && ~isempty(eeg.etc.alz.sourceRegions.scaleLabel)
                this.AmplitudeLabel = string(eeg.etc.alz.sourceRegions.scaleLabel);
            end
            this.Grid   = uigridlayout(fig, [2 2], "RowHeight", {22, '1x'}, ...
                "ColumnWidth", {'9x', '1x'}, "Padding", [4 4 4 4]);
            % Jump straight to an electrode instead of stepping to it one
            % channel at a time with the up/down arrow keys (onKey). Built
            % from EEG.chanlocs directly (not this.Series, prepared just
            % below) since the first series' labels are exactly those.
            this.ChannelDropdown = TransTools.BuildChannelDropdown(this.Grid, 1, [1, 2], ...
                {eeg.chanlocs.labels}, @(idx) this.onChannelSelected(idx));
            this.Axes   = uiaxes(this.Grid);
            this.Axes.Layout.Row = 2;
            this.Axes.Layout.Column = 1;
            this.Axes.ButtonDownFcn = @(~, ~) this.notifyActivated();
            % Every interaction moves or scales the amplitude axis only: an
            % axes property, so other plots in the window are untouched and
            % it goes with the plot when undocked. See the class header.
            this.Axes.InteractionOptions.LimitsDimensions = 'y';
            this.CheckboxGrid = uigridlayout(this.Grid, [1 1], "Padding", [0 0 0 0]);
            this.CheckboxGrid.Layout.Row = 2;
            this.CheckboxGrid.Layout.Column = 2;
            this.Paths   = containers.Map('KeyType', 'char', 'ValueType', 'any');
            this.Series  = this.prepare(eeg);
            this.Visible = true(1, numel(this.Series));
            % Key handling is wired by the shared Alakazam-level dispatcher
            % (Alakazam.dispatchKey), not a per-view fig.KeyPressFcn here:
            % every open dataset is now a uitab on one shared uifigure, so a
            % per-view KeyPressFcn would be overwritten by whichever view was
            % constructed last, breaking key navigation on every other open
            % tab.
            this.redraw();
            % The default tools, but Restore view is the view's own: MATLAB's
            % restores the view saved when zooming began, which after a channel
            % step belongs to another electrode, and the kept zoom (see
            % keepUserZoom) has to be forgotten too.
            toolbar = axtoolbar(this.Axes, {'export', 'brush', 'datacursor', 'pan', 'zoomin', 'zoomout'});
            axtoolbarbtn(toolbar, 'push', 'Icon', 'restoreview', 'Tag', 'RestoreView', ...
                'Tooltip', 'Restore view', 'ButtonPushedFcn', @(~, ~) this.resetZoom());
        end

        function problem = addDataset(this, eeg, path)
        %ADDDATASET  Overlay another averaged dataset.
        %   PROBLEM = addDataset(THIS, EEG, PATH) draws EEG's lines on these
        %   axes and returns '', or leaves the plot as it is and returns why:
        %   no channel or time in common (datasetOverlayProblem), or the dataset
        %   is already here. PATH, optional, is the dataset's place in the
        %   tree (a cellstr of labels), which names its lines. EEG.id is just
        %   the transform name (e.g. "Average" for every averaged dataset in
        %   the tree), so it cannot identify *which* dataset this is;
        %   EEG.File is the unique cache path.
            problem = this.overlayProblem(eeg);
            if ~isempty(problem)
                return;
            end
            newSeries = this.prepare(eeg);
            if isempty(newSeries)
                problem = 'It has no waveform to draw.';
                return;
            end
            existingFiles = cellfun(@(s) string(s.file), this.Series);
            if any(existingFiles == string(newSeries{1}.file))
                problem = 'It is already on this plot.';
                return;
            end
            if nargin >= 3 && ~isempty(path)
                this.setDatasetPath(newSeries{1}.file, path);
            end
            this.Series  = [this.Series, newSeries];
            this.Visible = [this.Visible, true(1, numel(newSeries))];
            this.redraw();
        end

        function problem = overlayProblem(this, eeg)
        %OVERLAYPROBLEM  Why EEG cannot be overlaid here, or '' if it can.
            first = this.Series{1};
            problem = datasetOverlayProblem(first.labels, first.times, ...
                {eeg.chanlocs.labels}, eeg.times);
        end

        function setDatasetPath(this, file, path)
        %SETDATASETPATH  Name FILE's lines by PATH, its place in the tree.
            this.Paths(char(string(file))) = cellstr(string(path));
            if numel(unique(cellfun(@(s) string(s.file), this.Series))) > 1
                this.redraw();
            end
        end

        function tf = canShowDifference(this)
        %CANSHOWDIFFERENCE  A difference needs exactly two ticked lines.
            tf = nnz(this.Visible) == 2;
        end

        function setDifference(this, on)
        %SETDIFFERENCE  Draw the difference of the two ticked lines, or the lines.
            this.DifferenceOn = logical(on) && this.canShowDifference();
            this.notifyActivated();
            this.redraw();
        end

        function swapDifference(this)
        %SWAPDIFFERENCE  Subtract the other way round.
            this.DifferenceSwapped = ~this.DifferenceSwapped;
            this.notifyActivated();
            this.redraw();
        end

        function setOverlayOpacity(this, value)
        %SETOVERLAYOPACITY  How strongly overlaid datasets are drawn (0.1 to 1).
            this.OverlayOpacity = min(1, max(0.1, value));
            this.redraw();
        end

        function resetZoom(this)
        %RESETZOOM  Forget a zoom or pan made with the axes toolbar, and scale
        %   the plot automatically again (the toolbar's Restore view).
            this.ZoomX = [];
            this.ZoomY = struct('lines', [], 'difference', []);
            this.redraw();
        end

        function removeOverlays(this)
        %REMOVEOVERLAYS  Take every overlaid dataset off the plot, leaving the
        %   plot's own lines as they were (ticked or not).
            own = cellfun(@(s) this.isOwn(s), this.Series);
            for file = unique(cellfun(@(s) string(s.file), this.Series(~own)))
                if isKey(this.Paths, char(file))
                    remove(this.Paths, char(file));
                end
            end
            this.Series  = this.Series(own);
            this.Visible = this.Visible(own);
            this.notifyActivated();
            this.redraw();
        end

        function redraw(this)
        %REDRAW  Draw every visible line's channel average and +/- 3 SE band,
        %   or the difference of the two ticked lines, plus the tickbox list
        %   (right of the axes) used to show/hide lines. Checked state lives
        %   in this.Visible, not in the tickboxes themselves, so it survives
        %   the delete+recreate below (e.g. an electrode step via the arrow
        %   keys leaves the ticks untouched).
            ax = this.Axes;
            this.keepUserZoom();
            % Remove ALL prior axes objects, including ones with hidden
            % handles (bands, patches, reference lines). cla only deletes
            % visible-handle children on older MATLAB, which otherwise pile up
            % on each redraw. The tickboxes live in their own grid cell (see
            % the constructor / buildCheckboxes), cleared there.
            delete(allchild(ax));
            hold(ax, "on");

            [names, fullNames] = this.seriesNames();
            label = this.channelLabel();
            if ~this.canShowDifference()
                this.DifferenceOn = false;
            end
            if this.DifferenceOn
                [handles, legendNames, ymin, ymax, xRange] = this.drawDifference(ax, names, label);
                title(ax, "Channel: " + label + ", difference", "Interpreter", "none");
            else
                [handles, legendNames, ymin, ymax, xRange] = this.drawLines(ax, names, label);
                title(ax, "Channel: " + label, "Interpreter", "none");   % a region name is literal, not TeX
            end

            this.ChannelDropdown.Value = this.Channel;
            % Data quality (analytic aSME per bin, at the shown channel) is shown
            % below the bin tickboxes rather than as an axes subtitle -- see
            % buildCheckboxes / asmeText.
            xlabel(ax, "Time (ms)");
            ylabel(ax, this.AmplitudeLabel);
            xline(ax, 0, "Color", "k", "LineStyle", "--");
            yline(ax, 0, "Color", "k", "LineStyle", "--");
            box(ax, "off");
            if all(isfinite(xRange)) && xRange(2) > xRange(1)
                xlim(ax, xRange);
            end
            % Clamp every electrode to the largest range (graphics > erpPlot >
            % clampYAxis) so the amplitude axis stays fixed while stepping
            % electrodes; otherwise rescale to the shown electrode.
            if AlakazamSettings.get('graphics', 'erpPlot', 'clampYAxis')
                if this.DifferenceOn
                    [ymin, ymax] = this.differenceExtent();
                else
                    [ymin, ymax] = this.globalExtent();
                end
            end
            if this.DifferenceOn
                % A bare line has no band to leave room around it, so its
                % extremes would sit on the frame.
                margin = 0.05 * (ymax - ymin);
                ymin = ymin - margin;
                ymax = ymax + margin;
            end
            if isfinite(ymin) && isfinite(ymax) && ymax > ymin
                ylim(ax, [ymin, ymax]);
            end
            % A zoom made with the toolbar wins over the automatic scaling.
            mode = this.limitsMode();
            if ~isempty(this.ZoomX)
                xlim(ax, this.ZoomX);
            end
            if ~isempty(this.ZoomY.(mode))
                ylim(ax, this.ZoomY.(mode));
            end
            this.LastLimits = struct('x', ax.XLim, 'y', ax.YLim, 'mode', mode);
            % Orientation of the amplitude axis (graphics > erpPlot > positiveUp).
            if AlakazamSettings.get('graphics', 'erpPlot', 'positiveUp')
                set(ax, 'YDir', 'normal');
            else
                set(ax, 'YDir', 'reverse');
            end
            % Build the legend from the mean-line handles only, so the bin
            % names always appear and bands/reference lines never leak in.
            if ~isempty(handles)
                legend(handles, cellstr(legendNames), "Location", "northeast", ...
                    "Interpreter", "none");
            else
                legend(ax, "off");
            end
            hold(ax, "off");

            this.buildCheckboxes(names, fullNames, label);
        end

        function onKey(this, event)
        %ONKEY  Up / down arrows step the channel shown for all lines.
        %   Public (not the private helper it used to be): dispatched by
        %   Alakazam.dispatchKey for whichever tab is currently selected --
        %   see the constructor comment.
            switch lower(event.Key)
                case "uparrow"
                    this.Channel = max(1, this.Channel - 1);
                case "downarrow"
                    this.Channel = min(numel(this.channelLabels()), this.Channel + 1);
                otherwise
                    return;
            end
            this.redraw();
            this.notifyActivated();
        end

        function onWheel(this, callbackData)
        %ONWHEEL  Scroll the mouse wheel to step the shown channel -- the
        %   same direction convention as the up/down arrow keys (positive
        %   VerticalScrollCount, i.e. scrolling down, steps forward
        %   through channels, matching downarrow). Public: dispatched
        %   centrally by Alakazam.dispatchWheel for whichever tab is
        %   currently active, mirroring EpochView's/TimeFrequencyView's/
        %   ScalpDistributionView's own onWheel contract.
            if callbackData.VerticalScrollCount > 0
                this.Channel = min(numel(this.channelLabels()), this.Channel + 1);
            else
                this.Channel = max(1, this.Channel - 1);
            end
            this.redraw();
            this.notifyActivated();
        end

    end

    methods (Access = private)
        function onChannelSelected(this, idx)
        %ONCHANNELSELECTED  ChannelDropdown's ValueChangedFcn: jump straight
        %   to the picked electrode for every line, the same effect as
        %   stepping there one channel at a time with the up/down arrow
        %   keys (onKey).
            this.notifyActivated();
            this.Channel = idx;
            this.redraw();
        end

        function [lo, hi] = globalExtent(this)
        %GLOBALEXTENT  Min/max over every channel and series, so a clamped axis
        %   fits the electrode with the largest deflection. Includes the +/- 3 SE
        %   band only when it is being drawn.
            showBand = AlakazamSettings.get('graphics', 'erpPlot', 'showConfInt');
            confN    = AlakazamSettings.get('graphics', 'erpPlot', 'confIntN');
            lo = inf; hi = -inf;
            for i = 1:numel(this.Series)
                if ~this.Visible(i)
                    continue;
                end
                s = this.Series{i};
                if showBand
                    % An unknown error (NaN, see binStErr) adds no band, but
                    % its channel's waveform still counts towards the range.
                    err = s.stErr;
                    err(~isfinite(err)) = 0;
                    loMat = s.data - confN * err;
                    hiMat = s.data + confN * err;
                else
                    loMat = s.data;
                    hiMat = s.data;
                end
                lo = min(lo, min(loMat(:), [], "omitnan"));
                hi = max(hi, max(hiMat(:), [], "omitnan"));
            end
        end

        function drawMeasurements(this, ax, s, ch, colour, meanCh)
        %DRAWMEASUREMENTS  Overlay the Measure results carried by series S
        %   (see prepare) onto the shown channel CH's line, in the series'
        %   own colour so each annotation reads as belonging to its bin:
        %     * Peak         -- a dot at (latency, amplitude) + a label.
        %     * Area         -- the integrated region shaded under the curve:
        %                       a peak-locked band (peak_latency +/- width/2)
        %                       or the whole window, clipped to the measure's
        %                       polarity mode, + a label.
        %     * Mean Amplitude -- a level line at the mean, spanning the
        %                       measurement window, + a label.
        %   Only the window rows that name the shown channel are drawn, so
        %   stepping electrodes moves the annotations with the data. All
        %   annotation objects are HandleVisibility 'off' so they never
        %   leak into the legend (which is built from the mean-line handles
        %   only). A no-op for a series with no measurements (any non-Measure
        %   dataset).
            if ~isfield(s, 'measurements') || isempty(s.measurements)
                return;
            end
            chLabel = s.labels{ch};
            b = s.bin;
            t = reshape(s.times, 1, []);
            for w = 1:numel(s.measurements)
                win = s.measurements{w};
                c = find(strcmpi(win.channels, chLabel), 1);
                if isempty(c) || b > size(win.amplitude, 2)
                    continue;
                end
                switch lower(strtrim(char(string(win.measure))))
                    case 'mean amplitude'
                        amp = win.amplitude(c, b);
                        if isnan(amp); continue; end
                        plot(ax, [win.start, win.stop], [amp, amp], 'Color', colour, ...
                            'LineWidth', 2, 'HandleVisibility', 'off', 'Tag', 'MeasureAnnotation');
                        this.measureLabel(ax, win.start, amp, win.label, colour);

                    case 'peak'
                        lat = win.latency(c, b);
                        amp = win.amplitude(c, b);
                        if isnan(lat) || isnan(amp); continue; end
                        plot(ax, lat, amp, 'o', 'MarkerFaceColor', colour, ...
                            'MarkerEdgeColor', 'k', 'MarkerSize', 6, 'HandleVisibility', 'off', ...
                            'Tag', 'MeasureAnnotation');
                        this.measureLabel(ax, lat, amp, win.label, colour);

                    case {'area', 'peak area', 'integral'}
                        % Shade the integrated region under the curve. A
                        % peak-locked band (scope 'band') spans width/2 each
                        % side of the found peak; a whole-window area (scope
                        % 'window') spans [start, stop]. The fill is clipped
                        % to the contributing polarity so it reads as the
                        % measure: positive keeps only y > 0, negative only
                        % y < 0, signed/rectified keep the whole curve.
                        [isBand, mode] = this.areaScopeMode(win, ...
                            lower(strtrim(char(string(win.measure)))));
                        if isBand
                            lat = win.latency(c, b);
                            if isnan(lat) || ~isfield(win, 'width') || isempty(win.width) ...
                                    || isnan(win.width) || win.width <= 0
                                continue;
                            end
                            half = win.width / 2;
                            mask = t >= (lat - half) & t <= (lat + half);
                            anchorT = lat;
                        else
                            mask = t >= win.start & t <= win.stop;
                            anchorT = (win.start + win.stop) / 2;
                        end
                        tb = t(mask);
                        yb = meanCh(mask);
                        valid = ~isnan(yb);
                        tb = tb(valid);
                        yb = yb(valid);
                        if numel(tb) < 2; continue; end
                        switch mode
                            case 'positive'; yfill = max(yb, 0);
                            case 'negative'; yfill = min(yb, 0);
                            otherwise;       yfill = yb;   % signed, rectified
                        end
                        patch(ax, [tb, fliplr(tb)], [yfill, zeros(1, numel(yfill))], colour, ...
                            'EdgeColor', 'none', 'FaceAlpha', 0.25, 'HandleVisibility', 'off', ...
                            'Tag', 'MeasureAnnotation');
                        [~, ai] = min(abs(t - anchorT));
                        this.measureLabel(ax, anchorT, meanCh(ai), win.label, colour);

                    case {'fractional peak latency', 'fractional area latency'}
                        % Mark the located latency: a dashed drop line from
                        % the curve to the 0-uV baseline, a dot on the curve,
                        % and the label.
                        lat = win.latency(c, b);
                        if isnan(lat); continue; end
                        yv = interp1(t, meanCh, lat, 'linear', NaN);
                        if isnan(yv)
                            [~, ni] = min(abs(t - lat));
                            yv = meanCh(ni);
                        end
                        plot(ax, [lat, lat], [0, yv], '--', 'Color', colour, ...
                            'LineWidth', 1.2, 'HandleVisibility', 'off', 'Tag', 'MeasureAnnotation');
                        plot(ax, lat, yv, 'o', 'MarkerFaceColor', colour, ...
                            'MarkerEdgeColor', 'k', 'MarkerSize', 5, 'HandleVisibility', 'off', ...
                            'Tag', 'MeasureAnnotation');
                        this.measureLabel(ax, lat, yv, win.label, colour);
                end
            end
        end

        function [isBand, mode] = areaScopeMode(~, win, measureName)
        %AREASCOPEMODE  Whether an Area window shades a peak-locked band
        %   (true) or its whole [start, stop] window (false), and its area
        %   mode ('signed'/'rectified'/'positive'/'negative', default
        %   'signed'). Tolerates a measurement stored before the Area family
        %   was unified (Peak Area -> band, Integral -> window; no scope or
        %   areaMode field).
            if isfield(win, 'scope') && ~isempty(win.scope)
                isBand = strcmpi(strtrim(char(string(win.scope))), 'band');
            else
                isBand = strcmp(measureName, 'peak area');
            end
            mode = 'signed';
            if isfield(win, 'areaMode') && ~isempty(win.areaMode)
                cand = lower(strtrim(char(string(win.areaMode))));
                if ismember(cand, {'signed', 'rectified', 'positive', 'negative'})
                    mode = cand;
                end
            end
        end

        function measureLabel(~, ax, x, y, label, colour)
        %MEASURELABEL  A small, legend-invisible text tag for one measure
        %   annotation, offset just right of its anchor point. Interpreter
        %   'none' so a label with underscores/brackets renders literally.
            if isnan(x) || isnan(y)
                return;
            end
            text(ax, x, y, ['  ' char(string(label))], 'Color', colour, ...
                'FontSize', 8, 'FontWeight', 'bold', 'VerticalAlignment', 'middle', ...
                'HorizontalAlignment', 'left', 'Clipping', 'on', ...
                'Interpreter', 'none', 'HandleVisibility', 'off', 'Tag', 'MeasureAnnotation');
        end

        function [handles, names, ymin, ymax, xRange] = drawLines(this, ax, allNames, label)
        %DRAWLINES  Every visible line at the channel called LABEL, with its
        %   band and Measure annotations. Overlaid datasets are drawn first,
        %   so the plot's own lines lie on top of them, and paler (see
        %   paleColour). A dataset without that channel is skipped, and its
        %   tickbox says so.
            showBand = AlakazamSettings.get('graphics', 'erpPlot', 'showConfInt');
            confN    = AlakazamSettings.get('graphics', 'erpPlot', 'confIntN');
            ymin = inf; ymax = -inf; xRange = [inf, -inf];
            n = numel(this.Series);
            lineOf = gobjects(1, n);
            own = cellfun(@(s) this.isOwn(s), this.Series);
            for i = [find(~own), find(own)]
                if ~this.Visible(i)
                    continue;
                end
                s = this.Series{i};
                ch = this.seriesChannel(s, label);
                if isempty(ch)
                    continue;
                end
                opacity = 1;
                if ~own(i)
                    opacity = this.OverlayOpacity;
                end
                % The palette is shared with FourierView (lineColour), so a
                % bin has the same colour in the ERP and in the spectrum.
                colour = this.paleColour(lineColour(i), opacity);
                t = reshape(double(s.times), 1, []);

                % Force row vectors so the band arithmetic is unambiguous.
                meanCh = reshape(s.data(ch, :), 1, []);
                band   = confN * reshape(s.stErr(ch, :), 1, []);
                lineOf(i) = plot(ax, t, meanCh, "Color", colour, "LineWidth", 1.5, ...
                    "Tag", "ErpLine", "UserData", i);
                % No band where the error is not known (a derived channel,
                % see binStErr), rather than a patch with holes in it.
                if showBand && all(isfinite(band))
                    plot(ax, t, meanCh + band, "Color", colour, "LineStyle", ":");
                    plot(ax, t, meanCh - band, "Color", colour, "LineStyle", ":");
                    patch(ax, [t, fliplr(t)], [meanCh + band, fliplr(meanCh - band)], ...
                        colour, "EdgeColor", "none", "FaceAlpha", 0.3 * opacity);
                    lo = meanCh - band; hi = meanCh + band;
                else
                    lo = meanCh; hi = meanCh;
                end
                ymin = min(ymin, min(lo, [], "omitnan"));
                ymax = max(ymax, max(hi, [], "omitnan"));
                xRange = [min(xRange(1), min(t)), max(xRange(2), max(t))];

                % Overlay this series' Measure annotations for the shown
                % channel (a no-op unless this dataset is a Measure result).
                this.drawMeasurements(ax, s, ch, colour, meanCh);
            end
            drawn = isgraphics(lineOf);
            handles = lineOf(drawn);
            names = allNames(drawn);
        end

        function [handles, names, ymin, ymax, xRange] = drawDifference(this, ax, allNames, label)
        %DRAWDIFFERENCE  The first ticked line minus the second at LABEL.
        %   No band: the two lines may share their trials (the same bin
        %   before and after a filter), and then the standard error of their
        %   difference cannot be had from the two standard errors.
            handles = gobjects(1, 0); names = strings(1, 0);
            ymin = inf; ymax = -inf; xRange = [inf, -inf];
            pair = this.differencePair();
            a = this.Series{pair(1)};
            b = this.Series{pair(2)};
            ca = this.seriesChannel(a, label);
            cb = this.seriesChannel(b, label);
            if isempty(ca) || isempty(cb)
                return;   % a line lacking this channel: nothing to subtract
            end
            [t, d] = this.differenceOf(a, b, ca, cb);
            handles = plot(ax, t, d, "Color", [0 0 0], "LineWidth", 1.5, "Tag", "DifferenceLine");
            names = allNames(pair(1)) + " " + char(8722) + " " + allNames(pair(2));
            ymin = min(d, [], "omitnan");
            ymax = max(d, [], "omitnan");
            xRange = [min(t), max(t)];
        end

        function keepUserZoom(this)
        %KEEPUSERZOOM  Remember a zoom or pan made since the last redraw.
        %   Redraw deletes and redraws everything, and sets the limits, on
        %   every channel step, tick or setting, which would throw away what
        %   the axes toolbar did. Limits that are no longer the ones redraw
        %   set were changed by the user, so they are kept (ZoomX/ZoomY) and
        %   put back after drawing, until Restore view (resetZoom).
            ax = this.Axes;
            last = this.LastLimits;
            if isempty(last.x)
                return;   % nothing drawn yet
            end
            if differs(ax.XLim, last.x)
                this.ZoomX = ax.XLim;
            end
            if differs(ax.YLim, last.y)
                this.ZoomY.(last.mode) = ax.YLim;
            end
        end

        function mode = limitsMode(this)
        %LIMITSMODE  Which amplitude zoom applies: the lines' or the difference's.
            mode = 'lines';
            if this.DifferenceOn
                mode = 'difference';
            end
        end

        function pair = differencePair(this)
        %DIFFERENCEPAIR  The two ticked lines, in the order they subtract.
            pair = find(this.Visible, 2);
            if this.DifferenceSwapped
                pair = fliplr(pair);
            end
        end

        function [t, d] = differenceOf(~, a, b, ca, cb)
        %DIFFERENCEOF  Line A at channel CA minus line B at channel CB, on
        %   A's time points. B is interpolated onto them when the two were
        %   sampled differently, and the difference is NaN where only one of
        %   them has data.
            t = reshape(double(a.times), 1, []);
            ya = reshape(double(a.data(ca, :)), 1, []);
            tb = reshape(double(b.times), 1, []);
            yb = reshape(double(b.data(cb, :)), 1, []);
            if numel(tb) == numel(t) && max(abs(tb - t)) < 1e-3
                d = ya - yb;
            else
                d = ya - interp1(tb, yb, t, 'linear', NaN);
            end
        end

        function [lo, hi] = differenceExtent(this)
        %DIFFERENCEEXTENT  Min/max of the difference over every channel both
        %   lines have, for a clamped amplitude axis (see redraw).
            lo = inf; hi = -inf;
            pair = this.differencePair();
            a = this.Series{pair(1)};
            b = this.Series{pair(2)};
            for label = this.channelLabels()
                ca = this.seriesChannel(a, label{1});
                cb = this.seriesChannel(b, label{1});
                if isempty(ca) || isempty(cb)
                    continue;
                end
                [~, d] = this.differenceOf(a, b, ca, cb);
                lo = min(lo, min(d, [], "omitnan"));
                hi = max(hi, max(d, [], "omitnan"));
            end
        end

        function colour = paleColour(this, colour, opacity)
        %PALECOLOUR  COLOUR as seen at OPACITY over the axes' background.
        %   Mixed by hand rather than given as an RGBA colour: MATLAB takes a
        %   fourth colour component for a line without complaint but does not
        %   keep it (R2026a reads the colour back without it), and exported
        %   figures drop it. A line drawn under the plot's own lines looks
        %   the same either way.
            background = this.Axes.Color;
            if ~isnumeric(background) || numel(background) ~= 3
                background = [1 1 1];
            end
            colour = opacity * colour + (1 - opacity) * background;
        end

        function tf = isOwn(this, s)
        %ISOWN  Whether series S belongs to the plot's own dataset.
            tf = strcmp(s.file, this.Series{1}.file);
        end

        function label = channelLabel(this)
        %CHANNELLABEL  The label of the channel shown, from the plot's own list.
            labels = this.channelLabels();
            label = '';
            if ~isempty(labels)
                label = char(string(labels{min(max(this.Channel, 1), numel(labels))}));
            end
        end

        function ch = seriesChannel(~, s, label)
        %SERIESCHANNEL  Where the channel called LABEL is in series S, or []
        %   when S does not have it. By label, since an overlaid dataset's
        %   channels need not be in the plot's order.
            ch = find(strcmpi(strtrim(s.labels), strtrim(label)), 1);
        end

        function [names, fullNames] = seriesNames(this)
        %SERIESNAMES  A legend name for every line, and its full tree path.
        %   A single dataset's lines are named by their bin, as always. Once
        %   another dataset is overlaid, each name is prefixed with what
        %   tells the datasets apart (overlayNames); a dataset with no known
        %   path is called by its transformation's name.
            n = numel(this.Series);
            names = strings(1, n);
            fullNames = strings(1, n);
            files = unique(cellfun(@(s) string(s.file), this.Series), 'stable');
            for i = 1:n
                names(i) = this.Series{i}.name;
                fullNames(i) = this.Series{i}.name;
            end
            if numel(files) < 2
                return;
            end
            paths = cell(1, numel(files));
            for k = 1:numel(files)
                if isKey(this.Paths, char(files(k)))
                    paths{k} = this.Paths(char(files(k)));
                else
                    first = find(cellfun(@(s) string(s.file) == files(k), this.Series), 1);
                    paths{k} = {char(string(this.Series{first}.id))};
                end
            end
            [short, full] = overlayNames(paths);
            for i = 1:n
                k = find(files == string(this.Series{i}.file), 1);
                names(i) = short(k) + ": " + this.Series{i}.name;
                fullNames(i) = full(k) + ": " + this.Series{i}.name;
            end
        end

        function buildCheckboxes(this, names, fullNames, label)
        %BUILDCHECKBOXES  One tickbox per series, stacked down the right-hand
        %   grid strip (this.CheckboxGrid), reflecting (and toggling)
        %   this.Visible; below them the Difference and Swap buttons, the
        %   overlay opacity once another dataset is overlaid, and the per-bin
        %   analytic aSME data-quality readout for the shown channel (visible
        %   bins only, and not for a difference).
            delete(this.CheckboxGrid.Children);
            n = numel(this.Series);
            if n == 0
                this.CheckboxGrid.RowHeight = {'1x'};
                return;
            end
            overlaid = numel(unique(cellfun(@(s) string(s.file), this.Series))) > 1;
            % Overlaid lines carry their dataset's name as well as their bin's,
            % too long for a tenth of the width; give the strip room while
            % there is an overlay.
            if overlaid
                this.Grid.ColumnWidth = {'1x', 200};
            else
                this.Grid.ColumnWidth = {'9x', '1x'};
            end
            smeText = strings(0, 1);
            if ~this.DifferenceOn
                smeText = this.asmeText(label);
            end
            rows = [repmat({22}, 1, n), {24}];              % tickboxes, Difference
            if this.DifferenceOn;      rows = [rows, {24}];     end   % Swap
            if overlaid;               rows = [rows, {24, 16, 24}]; end   % Remove overlay, opacity
            if ~isempty(smeText);      rows = [rows, {'fit'}];  end   % aSME block
            this.CheckboxGrid.RowHeight = [rows, {'1x'}];

            for i = 1:n
                text = names(i);
                if isempty(this.seriesChannel(this.Series{i}, label))
                    text = sprintf('%s (no %s)', text, label);
                end
                cb = uicheckbox(this.CheckboxGrid, ...
                    "Text", char(text), ...
                    "Tooltip", char(fullNames(i)), ...
                    "Value", this.Visible(i), ...
                    "ValueChangedFcn", @(src, ~) this.onToggle(i, src.Value));
                cb.Layout.Row = i;
            end
            row = n + 1;
            difference = uibutton(this.CheckboxGrid, "state", "Text", "Difference", ...
                "Value", this.DifferenceOn, "Enable", this.canShowDifference(), ...
                "Tag", "DifferenceButton", ...
                "Tooltip", 'Show the first ticked line minus the second. Tick exactly two lines.', ...
                "ValueChangedFcn", @(src, ~) this.setDifference(src.Value));
            difference.Layout.Row = row;
            if this.DifferenceOn
                row = row + 1;
                swap = uibutton(this.CheckboxGrid, "Text", "Swap", "Tag", "SwapButton", ...
                    "Tooltip", 'Subtract the other way round.', ...
                    "ButtonPushedFcn", @(~, ~) this.swapDifference());
                swap.Layout.Row = row;
            end
            if overlaid
                row = row + 1;
                remover = uibutton(this.CheckboxGrid, "Text", "Remove overlay", ...
                    "Tag", "RemoveOverlayButton", ...
                    "Tooltip", 'Take the overlaid datasets off this plot, keeping its own lines.', ...
                    "ButtonPushedFcn", @(~, ~) this.removeOverlays());
                remover.Layout.Row = row;
                row = row + 1;
                caption = uilabel(this.CheckboxGrid, "Text", "Overlay opacity", "FontSize", 10);
                caption.Layout.Row = row;
                row = row + 1;
                slider = uislider(this.CheckboxGrid, "Limits", [0.1 1], ...
                    "Value", this.OverlayOpacity, "MajorTicks", [], "MinorTicks", [], ...
                    "Tag", "OverlayOpacity", ...
                    "Tooltip", 'How strongly the overlaid datasets are drawn, under the plot''s own.', ...
                    "ValueChangedFcn", @(src, ~) this.setOverlayOpacity(src.Value));
                slider.Layout.Row = row;
            end
            if ~isempty(smeText)
                lbl = uilabel(this.CheckboxGrid, "Text", smeText, "FontSize", 10, ...
                    "VerticalAlignment", "top", "WordWrap", "on");
                lbl.Layout.Row = row + 1;
            end
        end

        function txt = asmeText(this, label)
        %ASMETEXT  Per-bin analytic aSME (uV) at the channel called LABEL, one
        %   line per visible bin, as a string array (each element a line) for
        %   a uilabel. Empty when no visible bin carries an aSME (e.g. an
        %   averaged dataset made before aSME existed).
            txt = strings(0, 1);
            if isempty(this.Series); return; end
            lines = strings(0, 1);
            for i = 1:numel(this.Series)
                if ~this.Visible(i); continue; end
                s = this.Series{i};
                ch = this.seriesChannel(s, label);
                if ~isempty(ch) && isfield(s, 'aSME') && numel(s.aSME) >= ch && isfinite(s.aSME(ch))
                    lines(end + 1, 1) = sprintf('%s  %.2f', s.name, s.aSME(ch)); %#ok<AGROW>
                end
            end
            if isempty(lines); return; end
            txt = ["aSME (" + char(181) + "V)"; lines];
        end

        function onToggle(this, idx, value)
        %ONTOGGLE  A tickbox was (un)checked: show/hide that line and redraw.
        %   A difference needs exactly two lines, so ticking a third (or
        %   unticking one of the two) returns to the lines (see redraw).
            this.Visible(idx) = logical(value);
            this.notifyActivated();
            this.redraw();
        end

        function series = prepare(~, eeg)
        %PREPARE  Expand an averaged dataset into one plot series per line:
        %   one per bin for a bin-aware average, otherwise a single series.
        %   Each series also carries its own bin index and the dataset's
        %   EEG.measurements (empty unless this is a Measure result), so
        %   drawMeasurements can annotate the right line for the right bin
        %   even when several datasets are overlaid on one axes.
            labels = {eeg.chanlocs.labels};
            if isfield(eeg, "id") && ~isempty(eeg.id); id = char(string(eeg.id)); else; id = ""; end
            file = char(string(eeg.File));   % unique per dataset; id is not
            if isfield(eeg, "measurements"); meas = eeg.measurements; else; meas = {}; end
            series = {};

            isBinned = ndims(eeg.data) == 3 && isfield(eeg, "bindesc") ...
                && ~isempty(eeg.bindesc);

            if isBinned
                for b = 1:size(eeg.data, 3)
                    name = char(string(eeg.bindesc(b).label));
                    if isfield(eeg.bindesc, "n") && ~isempty(eeg.bindesc(b).n)
                        % A regular bin's n is numeric (trial count); a
                        % combination bin's is a string built from its
                        % constituents' counts (e.g. "68-74"), since it has
                        % no trials of its own.
                        name = sprintf('%s (n=%s)', name, string(eeg.bindesc(b).n));
                    end
                    s.id     = id;
                    s.file   = file;
                    s.name   = name;
                    s.times  = eeg.times;
                    s.data   = eeg.data(:, :, b);
                    s.stErr  = binStErr(eeg, b);
                    s.aSME   = binASME(eeg, b);
                    s.labels = labels;
                    s.bin    = b;
                    s.measurements = meas;
                    series{end + 1} = s; %#ok<AGROW>
                end
            else
                s.id    = id;
                s.file  = file;
                s.name  = id;
                s.times = eeg.times;
                s.data  = reshape(eeg.data, size(eeg.data, 1), size(eeg.data, 2));
                s.stErr = binStErr(eeg, 1);
                s.aSME  = binASME(eeg, 1);
                s.labels = labels;
                s.bin    = 1;
                s.measurements = meas;
                series{end + 1} = s;
            end
        end
    end

    methods
        function focus = currentFocus(this)
        %CURRENTFOCUS  The channel every line is drawn for, by label.
        %   The labels live on the series rather than on a chanlocs of this
        %   view's own, since an AverageView draws several datasets at once.
            focus = struct();
            labels = this.channelLabels();
            if this.Channel >= 1 && this.Channel <= numel(labels)
                focus.Channel = char(string(labels{this.Channel}));
            end
        end

        function applyFocus(this, focus)
        %APPLYFOCUS  Show FOCUS.Channel if these series carry it.
            if ~isstruct(focus) || ~isfield(focus, 'Channel')
                return;
            end
            idx = ViewFocus.indexOfLabel(this.channelLabels(), focus.Channel);
            if isempty(idx) || idx == this.Channel
                return;
            end
            this.Channel = idx;
            this.redraw();
        end
    end

    methods (Access = private)
        function labels = channelLabels(this)
        %CHANNELLABELS  The first series' labels, which is what redraw and
        %   the title already index with this.Channel.
            labels = {};
            if isempty(this.Series)
                return;
            end
            first = this.Series{1};
            if isstruct(first) && isfield(first, 'labels')
                labels = first.labels;
            end
        end
    end
end

function se = binStErr(eeg, b)
%BINSTERR  The standard error of bin B, channels x samples: zeros when the
%   dataset carries none (no band is drawn), NaN where it is not known.
%
%   NOT KNOWN covers two cases. A channel derived from others on an average
%   has NaN by design (see TransTools.AlignChannelCompanions). And a node
%   saved before that alignment existed can hold an error with a row per
%   channel of its PARENT, one short after a derived channel was added;
%   reading it row by row put the wrong error on the wrong channel, and
%   the band arithmetic failed with "Arrays have incompatible sizes". Such
%   an error is not used at all rather than guessed at.
    shape = [size(eeg.data, 1), size(eeg.data, 2)];
    if ~isfield(eeg, 'stErr') || isempty(eeg.stErr)
        se = zeros(shape);
    elseif size(eeg.stErr, 1) == shape(1) && size(eeg.stErr, 2) == shape(2) ...
            && size(eeg.stErr, 3) == size(eeg.data, 3)
        se = eeg.stErr(:, :, b);
    else
        se = nan(shape);
    end
end

function sme = binASME(eeg, b)
%BINASME  Per-channel analytic SME (uV) for bin B (a column vector), or [] when
%   the dataset carries none (e.g. an averaged dataset made before aSME
%   existed) or carries one that does not have a row per channel (see
%   binStErr for how that happens).
    sme = [];
    if isfield(eeg, 'aSME') && ~isempty(eeg.aSME) && size(eeg.aSME, 2) >= b ...
            && size(eeg.aSME, 1) == size(eeg.data, 1)
        sme = eeg.aSME(:, b);
    end
end

function tf = differs(a, b)
%DIFFERS  Whether two axis ranges are not the same, allowing for rounding.
    tf = numel(a) ~= numel(b) || any(abs(a - b) > 1e-9 * max(1, max(abs([a, b]))));
end
