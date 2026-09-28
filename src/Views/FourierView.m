classdef FourierView < AlakazamView
%FOURIERVIEW  Keyboard-driven view of a frequency-domain dataset.
%
%   FourierView draws one channel's spectra at a time, over the frequency
%   bands shaded in the background (from AlakazamSettings.getBands,
%   user-editable on the Settings dialog's own "Frequency bands" tab -- see
%   drawBandStripes) and, optionally, a light moving-average smoothing over
%   the plotted spectrum (the "Smooth spectrum" checkbox on the Settings
%   dialog's "Graphics" tab -- see magnitudeOf), and steps through channels
%   with the up/down arrow keys -- the same interaction model EpochView and
%   AverageView already use for time-domain data. Replaces the previous
%   grid-of-every-channel-at-once layout with click-to-drill-into-detail,
%   which needed its own rebuild-in-place machinery (captureSlot/
%   buildOuterGrid) that a single persistent axes, redrawn in place like
%   EpochView/AverageView, does not.
%
%   WHAT THE 3RD DIMENSION IS depends on whether the data has been
%   averaged, and that is not the same question as whether it has bins.
%   Fourier.m starts with `output = input;`, so EEG.bindesc survives it
%   either way: on averaged data the 3rd dimension is one spectrum per bin,
%   but on epoched data it is one spectrum per TRIAL and bindesc is merely
%   along for the ride, describing which trials belong to which bin. This
%   view used to key off "bindesc is present", which is true in both cases,
%   and so labelled single-trial spectra "Bin 37 of 197" -- a confident,
%   wrong name for the thing on screen. It asks DataFormat instead
%   (thirdDimIsBins), and the answer decides how the view works:
%
%     * AVERAGED SPECTRA, one per bin, are LINES, as AverageView draws ERPs:
%       a tickbox per bin in a strip right of the plot, each ticked bin a line
%       in its own colour (lineColour, the palette AverageView uses, so a bin
%       keeps its colour from waveform to spectrum), with a legend and, where
%       Average stored one, a band of n standard errors (the ERP plot's own
%       "Show confidence interval" settings).
%     * ONE SPECTRUM PER CHANNEL (a continuous recording, Welch) is a single
%       black line, and the strip appears once something is overlaid on it.
%     * SINGLE-TRIAL SPECTRA are shown one at a time, picked with a
%       "Trial:" dropdown that names each trial's bin, or the left/right
%       keys. Hundreds of single trials laid over each other show nothing;
%       Average them to compare bins. Nothing is overlaid on them.
%
%   OVERLAYS. Other spectra can be drawn on the same axes (addDataset): the
%   tree's Overlay on plot command, or dropping one averaged spectrum onto
%   another, exactly as AverageView overlays ERPs. Each overlaid spectrum
%   keeps its own frequency axis and each channel is found by its label, so
%   a spectrum of another resolution or montage overlays correctly
%   (datasetOverlayProblem says when it cannot). A spectrum in another unit
%   is refused, since the two cannot share an axis, and so are single-trial
%   spectra. Lines are named by what tells their datasets apart in the tree
%   (overlayNames); overlaid spectra are drawn underneath the plot's own and
%   paler, by the Overlay opacity slider, and Remove overlay takes them off.
%
%   DIFFERENCE. With exactly two lines ticked, of one dataset or two,
%   Difference draws the first minus the second (Swap reverses it), or,
%   with "Ratio in dB", their ratio in decibels: 10*log10 for a power and
%   20*log10 for an amplitude, read from the unit Fourier and Welch stamp on
%   the data (EEG.SpectrumUnit, see spectrumUnit). The ratio is how
%   conditions are usually contrasted in a spectrum, since it does not
%   depend on the 1/f level. On complex spectra with the phase shown, the
%   difference is the phase of the first relative to the second,
%   angle(A .* conj(B)). The second is interpolated onto the first's
%   frequencies when the two differ.
%
%   The channel is picked with a dropdown above the plot, as in EpochView
%   and TimeFrequencyView (TransTools.BuildChannelDropdown), and the keys,
%   the wheel and a focus shared from another view move it along.
%
%   LOG SCALE, a checkbox above the plot and off by default, draws the
%   magnitude on a logarithmic axis, where the high frequencies of a 1/f
%   spectrum are not squashed against zero; it reaches down six decades
%   from the largest value shown. It does not apply to a phase, a
%   difference, which can be negative, or a ratio, which is in dB already.
%
%   X/y zoom are sliders below the plot (frequency data commonly needs
%   zooming into a specific band, clamped to [0, srate/2] -- something the
%   generic axtoolbar zoom does not do), styled like SignalView's own
%   zoom/pan/mag rows; a zoom level, once set, survives a channel/trial
%   change instead of resetting (see ZoomPanButtons' own header comment on
%   applyYZoom). ZoomPanButtons is built with its zoom sliders alone; the
%   axes toolbar pans. The mouse wheel also steps the channel, same
%   direction as the arrow keys, matching SpectralMeasureView's own
%   onWheel.
%
%   Style follows the project standard.
%
%   See also ALAKAZAMPLOTTER, EPOCHVIEW, AVERAGEVIEW, SPECTRALMEASUREVIEW,
%   ZOOMPANBUTTONS, LINECOLOUR, DATASETOVERLAYPROBLEM, OVERLAYNAMES.

    properties
    end

    properties (SetAccess = private)
        Figure          % owning figure
        EEG             % the plot's own frequency-domain dataset
        Grid            % 4x1 uigridlayout: controls | plot | x-zoom | y-zoom (built once, never rebuilt)
        ChannelDropdown % "Channel:" uidropdown (see TransTools.BuildChannelDropdown), row 1
        StepDropdown    % "Trial:" uidropdown (TransTools.BuildBinDropdown), row 1, for
                        % single-trial spectra only; empty otherwise
        LogScaleBox     % "Log scale" uicheckbox, row 1
        Axes            % the single axes the spectra are drawn in
        Strip           % uigridlayout right of the axes: tickboxes, Difference, overlay controls
        Zoom            % ZoomPanButtons, the x/y zoom sliders alone (no button row)
        SingleTrials    % true for epoched single-trial spectra, stepped one at a time
        % Cell of line structs (spectrumSeries): the plot's own first, then
        % overlaid ones. An empty CELL for single trials, not [], since every
        % method treats it as a cell (cellfun over [] is an error).
        Series = {}
        Visible = false(1, 0)   % logical row, one per series: is it drawn?
        Channel = 1     % channel currently shown
        CurrentTrial = 1    % single-trial spectrum shown (SingleTrials only)
        ShowPhase = false   % complex data only: plot angle() rather than abs()
        DifferenceOn = false        % drawing the first ticked line against the second?
        DifferenceSwapped = false   % ... or the second against the first
        DifferenceAsRatio = false   % ... as their ratio in dB rather than a difference
        LogScale = false            % magnitude on a logarithmic axis?
        OverlayOpacity = 0.5        % how strongly overlaid spectra are drawn, 0.1 to 1
    end

    properties (Access = private)
        PlotRow         % 1x2 uigridlayout holding the axes and the strip
        HostFile        % the plot's own dataset file (EEG.File), which tells its lines apart
        Paths           % containers.Map: dataset file -> its tree path (cellstr)
    end

    properties (Constant, Access = private)
        LogDecades = 6      % how far a log axis reaches below the largest value
        StripeAlpha = 0.25  % how strongly the frequency bands are shaded
    end

    methods
        function this = FourierView(fig, eeg)
        %FOURIERVIEW  Build the frequency-domain view for EEG in FIG.
            this.Figure = fig;
            this.EEG    = eeg;
            this.HostFile = fileOf(eeg);
            this.Paths = containers.Map('KeyType', 'char', 'ValueType', 'any');
            this.SingleTrials = ~thirdDimIsBins(eeg) && size(eeg.data, 3) > 1;

            % Key handling is wired by the shared Alakazam-level dispatcher
            % (Alakazam.dispatchKey), not a per-view fig.KeyPressFcn here:
            % every open dataset is now a uitab on one shared uifigure, so a
            % per-view KeyPressFcn would be overwritten by whichever view was
            % constructed last, breaking key navigation on every other open
            % tab.
            this.Grid = uigridlayout(fig, [4 1], "RowHeight", {22, '1x', 24, 24}, ...
                "Padding", [2 2 2 2], "RowSpacing", 2);

            % Row 1: the channel, the trial (single-trial spectra only) and
            % the log scale, in EpochView's proportions.
            controls = uigridlayout(this.Grid, [1 3], "ColumnWidth", {'1x', '1x', '1x'}, ...
                "Padding", [0 0 0 0], "ColumnSpacing", 12);
            controls.Layout.Row = 1;
            this.ChannelDropdown = TransTools.BuildChannelDropdown(controls, 1, 1, ...
                {eeg.chanlocs.labels}, @(idx) this.onChannelSelected(idx));
            if this.SingleTrials
                this.StepDropdown = TransTools.BuildBinDropdown(controls, 1, 2, ...
                    trialItems(eeg), @(idx) this.onStepSelected(idx), "Trial:");
            end
            this.LogScaleBox = uicheckbox(controls, "Text", "Log scale", "Value", false, ...
                "Tag", "LogScale", ...
                "ValueChangedFcn", @(src, ~) this.setLogScale(src.Value));
            this.LogScaleBox.Layout.Column = 3;

            % Row 2: the plot, and beside it the strip, in AverageView's
            % proportions while it is shown (see layoutStrip). Nested, so
            % that the rows around it keep a single column.
            this.PlotRow = uigridlayout(this.Grid, [1 2], "ColumnWidth", {'1x', 0}, ...
                "Padding", [0 0 0 0]);
            this.PlotRow.Layout.Row = 2;
            this.Axes = uiaxes(this.PlotRow);
            this.Axes.Layout.Column = 1;
            this.Axes.ButtonDownFcn = @(~, ~) this.notifyActivated();
            this.Strip = uigridlayout(this.PlotRow, [1 1], "Padding", [0 0 0 0]);
            this.Strip.Layout.Column = 2;

            if ~this.SingleTrials
                this.Series = spectrumSeries(eeg, this.HostFile);
                this.Visible = true(1, numel(this.Series));
            end

            this.Zoom = ZoomPanButtons(this.Grid, [3 4], this.Axes, eeg.srate / 2, ...
                @() this.notifyActivated());
            this.redraw();
            axtoolbar(this.Axes, "default");
        end

        function redraw(this)
        %REDRAW  Draw the spectra shown at the current channel: every ticked
        %   line (the plot's own bins or spectrum and anything overlaid), or
        %   the current trial, or the difference or ratio of two ticked
        %   lines; then the axes' scale, limits, labels and title, and the
        %   controls that follow the state.
            ax = this.Axes;
            delete(allchild(ax));

            % COMPLEX DATA MUST NEVER REACH plot() AS-IS. Fourier's
            % 'Complex' output keeps the raw coefficients, and plot() given
            % complex y IGNORES the x argument entirely and draws real
            % against imaginary -- a picture that looks like a plot, is not
            % a spectrum, and carries no frequency axis at all. Every value
            % drawn is made real first (magnitudeOf, angle).
            %
            % PHASE IS SHOWN WRAPPED, in [-pi, pi], and NOT UNWRAPPED
            % ACROSS FREQUENCY. Fourier measures phase from the segment's
            % first sample, so every spectrum carries a ramp of 2*pi*f times
            % the time at which its activity is centred, and unwrap() summed
            % that ramp over every bin: on a five-minute recording it drew a
            % straight line reaching 10^4 to 10^5 rad by 100 Hz, which says
            % how long the segment is and nothing about the EEG. Unwrapping
            % over frequency suits a smooth transfer function, not the phase
            % of a noisy spectrum, whose neighbouring bins are independent.
            phaseMode = this.ShowPhase && ~isreal(this.EEG.data);
            if ~this.canShowDifference()
                this.DifferenceOn = false;
            end
            [unitKind, unitLabel] = spectrumUnit(this.EEG);
            asRatio = this.DifferenceOn && this.DifferenceAsRatio && ~phaseMode && ~isempty(unitKind);
            logScale = this.LogScale && ~phaseMode && ~this.DifferenceOn;
            ax.YScale = ternary(logScale, 'log', 'linear');
            label = this.channelLabel();
            [names, fullNames] = this.seriesNames();

            hold(ax, "on");
            if this.DifferenceOn
                [lo, hi, handles, legendNames, yText] = this.drawDifference(ax, names, label, ...
                    phaseMode, asRatio, unitKind, unitLabel);
            else
                [lo, hi, handles, legendNames] = this.drawSpectra(ax, names, label, phaseMode, logScale);
                yText = ternary(phaseMode, 'phase (rad)', unitLabel);
            end
            if logScale && ~(isfinite(lo) && isfinite(hi) && lo > 0 && hi > lo)
                ax.YScale = 'linear';   % nothing positive to put on a log axis
                lo = 0;
            end
            if ~phaseMode
                this.drawBandStripes(ax, lo, hi);
            end
            if this.DifferenceOn && ~phaseMode
                yline(ax, 0, "Color", "k", "LineStyle", "--", "HandleVisibility", "off");
            end
            hold(ax, "off");

            % The labels and ticks are the axes' own, not its children's, so
            % they survive the delete(allchild) above and have to be set both
            % ways: the phase's must not linger on a magnitude spectrum.
            ylabel(ax, yText);
            if phaseMode
                yticks(ax, (-2:2) * pi / 2);
                yticklabels(ax, {'-\pi', '-\pi/2', '0', '\pi/2', '\pi'});
            else
                yticks(ax, 'auto');
                yticklabels(ax, 'auto');
            end
            if this.showsStrip() && ~isempty(handles)
                legend(handles, cellstr(legendNames), "Location", "northeast", "Interpreter", "none");
            else
                legend(ax, "off");
            end
            title(ax, this.titleText(phaseMode, asRatio));

            % x-limits are owned by this.Zoom (persists zoom across a
            % channel/trial change); y-limits go through applyYZoom so the
            % y-zoom slider's level, not just the absolute range, survives
            % too -- see ZoomPanButtons' own header comment.
            this.Zoom.applyYZoom(hi, lo);

            % The controls show what is drawn, however it was chosen: a key,
            % the wheel, a focus shared from another view, or the control
            % itself. Setting Value does not fire ValueChangedFcn.
            this.ChannelDropdown.Value = this.Channel;
            if ~isempty(this.StepDropdown)
                this.StepDropdown.Value = this.CurrentTrial;
            end
            this.LogScaleBox.Value = this.LogScale;
            this.LogScaleBox.Enable = ~phaseMode && ~this.DifferenceOn;
            this.LogScaleBox.Tooltip = ternary(phaseMode || this.DifferenceOn, ...
                'A log scale applies to a magnitude, not to a phase, a difference or a ratio.', ...
                'Draw the magnitude on a logarithmic axis.');
            this.buildStrip(names, fullNames, label, phaseMode, unitKind);
        end

        function onKey(this, event)
        %ONKEY  Up/down arrows step the channel; left/right step the trial
        %   (single-trial spectra only); P switches between magnitude and
        %   phase when the data is complex. Public (not a private helper):
        %   dispatched by Alakazam.dispatchKey for whichever tab is currently
        %   selected -- see the constructor comment.
            switch lower(event.Key)
                case "uparrow"
                    this.Channel = max(1, this.Channel - 1);
                case "downarrow"
                    this.Channel = min(size(this.EEG.data, 1), this.Channel + 1);
                case {"leftarrow", "rightarrow"}
                    if ~this.SingleTrials
                        return;   % lines are ticked, not stepped
                    end
                    step = 2 * strcmpi(event.Key, "rightarrow") - 1;
                    this.CurrentTrial = min(size(this.EEG.data, 3), max(1, this.CurrentTrial + step));
                case "p"
                    % Only meaningful for Fourier's 'Complex' output; on a
                    % magnitude spectrum there is no phase to show, so the
                    % key does nothing rather than toggling to a blank plot.
                    if isreal(this.EEG.data)
                        return;
                    end
                    this.ShowPhase = ~this.ShowPhase;
                otherwise
                    return;
            end
            this.redraw();
        end

        function onWheel(this, callbackData)
        %ONWHEEL  Scroll the mouse wheel to step the shown channel -- the
        %   same direction convention as the up/down arrow keys, matching
        %   SpectralMeasureView's own onWheel (its near-twin: both views
        %   share the same interaction model, see the class header
        %   comment). Public: dispatched centrally by
        %   Alakazam.dispatchWheel for whichever tab is currently active.
            if callbackData.VerticalScrollCount > 0
                this.Channel = min(size(this.EEG.data, 1), this.Channel + 1);
            else
                this.Channel = max(1, this.Channel - 1);
            end
            this.redraw();
            this.notifyActivated();
        end

        function problem = addDataset(this, eeg, path)
        %ADDDATASET  Overlay another spectrum.
        %   PROBLEM = addDataset(THIS, EEG, PATH) draws EEG's spectra on these
        %   axes and returns '', or leaves the plot as it is and returns why
        %   (overlayProblem), or that it is already here. PATH, optional, is
        %   the dataset's place in the tree (a cellstr of labels), which names
        %   its lines. EEG.File, the dataset's unique cache path, tells its
        %   lines apart from the plot's own.
            problem = this.overlayProblem(eeg);
            if ~isempty(problem)
                return;
            end
            file = fileOf(eeg);
            if any(cellfun(@(s) strcmp(s.file, file), this.Series))
                problem = 'It is already on this plot.';
                return;
            end
            if nargin >= 3 && ~isempty(path)
                this.Paths(file) = cellstr(string(path));
            end
            added = spectrumSeries(eeg, file);
            this.Series = [this.Series, added];
            this.Visible = [this.Visible, true(1, numel(added))];
            this.redraw();
        end

        function problem = overlayProblem(this, eeg)
        %OVERLAYPROBLEM  Why EEG cannot be overlaid here, or '' if it can:
        %   not a spectrum; single trials on either side, which are stepped
        %   through, not overlaid; another unit, which cannot share the axis;
        %   or no channel or frequency in common (datasetOverlayProblem).
            problem = '';
            if this.SingleTrials
                problem = ['This plot shows single trials one at a time. Overlay on an averaged ' ...
                    'spectrum, or on a single one such as Welch''s.'];
                return;
            end
            if ~strcmpi(TransTools.FieldOr(eeg, 'DataType', ''), 'FrequencyDomain')
                problem = 'It is not a spectrum.';
                return;
            end
            if ~thirdDimIsBins(eeg) && size(eeg.data, 3) > 1
                problem = 'It holds single-trial spectra; average them to overlay them.';
                return;
            end
            [~, ~, plotUnit] = spectrumUnit(this.EEG);
            [~, ~, itsUnit] = spectrumUnit(eeg);
            if ~isempty(plotUnit) && ~isempty(itsUnit) && ~strcmp(plotUnit, itsUnit)
                problem = sprintf('It is %s and the plot %s, which cannot share an axis.', ...
                    itsUnit, plotUnit);
                return;
            end
            problem = datasetOverlayProblem({this.EEG.chanlocs.labels}, this.EEG.freqs, ...
                {eeg.chanlocs.labels}, eeg.freqs, 'Hz');
        end

        function setDatasetPath(this, file, path)
        %SETDATASETPATH  Name FILE's lines by PATH, its place in the tree.
            this.Paths(char(string(file))) = cellstr(string(path));
            if this.isOverlaid()
                this.redraw();
            end
        end

        function removeOverlays(this)
        %REMOVEOVERLAYS  Take every overlaid spectrum off the plot, leaving the
        %   plot's own lines as they were (ticked or not).
            own = cellfun(@(s) this.isOwn(s), this.Series);
            for file = unique(cellfun(@(s) string(s.file), this.Series(~own)))
                if isKey(this.Paths, char(file))
                    remove(this.Paths, char(file));
                end
            end
            this.Series = this.Series(own);
            this.Visible = this.Visible(own);
            this.notifyActivated();
            this.redraw();
        end

        function setOverlayOpacity(this, value)
        %SETOVERLAYOPACITY  How strongly overlaid spectra are drawn (0.1 to 1).
            this.OverlayOpacity = min(1, max(0.1, value));
            this.redraw();
        end

        function setLogScale(this, on)
        %SETLOGSCALE  Draw the magnitude on a logarithmic axis, or a linear one.
            this.LogScale = logical(on);
            this.notifyActivated();
            this.redraw();
        end

        function tf = canShowDifference(this)
        %CANSHOWDIFFERENCE  A difference needs exactly two ticked lines.
            tf = ~this.SingleTrials && nnz(this.Visible) == 2;
        end

        function setDifference(this, on)
        %SETDIFFERENCE  Draw the two ticked lines' difference, or the lines.
            this.DifferenceOn = logical(on) && this.canShowDifference();
            this.notifyActivated();
            this.redraw();
        end

        function swapDifference(this)
        %SWAPDIFFERENCE  Compare the other way round.
            this.DifferenceSwapped = ~this.DifferenceSwapped;
            this.notifyActivated();
            this.redraw();
        end

        function setRatio(this, on)
        %SETRATIO  Show the two ticked lines' ratio in dB, or their difference.
            this.DifferenceAsRatio = logical(on);
            this.notifyActivated();
            this.redraw();
        end
    end

    methods (Access = private)
        function [lo, hi, handles, legendNames] = drawSpectra(this, ax, names, label, phaseMode, logScale)
        %DRAWSPECTRA  Every ticked line at the channel called LABEL, each over
        %   its standard-error band where it has one, and the natural y-range
        %   [LO, HI] they need. Overlaid spectra are drawn first, so the
        %   plot's own lie on top of them. A magnitude axis starts at 0 unless
        %   the data dips below it (a combination bin can). On a log axis
        %   values at or below zero are left out, and LO is the smallest value
        %   drawn, but no more than LogDecades below the largest; a band edge
        %   below LO is drawn down to it. A line whose dataset lacks the
        %   channel, or has no phase to show, is left out (its tickbox says so).
            [series, visible] = this.drawnSeries();
            n = numel(series);
            lineOf = gobjects(1, n);
            own = cellfun(@(s) this.isOwn(s), series);
            order = [find(~own & visible), find(own & visible)];

            if phaseMode
                lo = -pi;
                hi = pi;
                for i = order
                    s = series{i};
                    ch = seriesChannel(s, label);
                    if isempty(ch) || isreal(s.data)
                        continue;
                    end
                    % Points, not a line: a wrapped phase jumps between pi
                    % and -pi, and a line would draw each jump as a
                    % vertical stroke.
                    lineOf(i) = plot(ax, s.freqs, angle(s.data(ch, :)), ".", ...
                        "Color", this.seriesColour(i, s), "MarkerSize", 6, ...
                        "Tag", "SpectrumLine", "UserData", i);
                end
            else
                % First every value, to know the range; then the drawing,
                % since on a log axis a band's lower edge is drawn down to it.
                [bandOn, bandN] = errorBandSettings();
                values = cell(1, n);
                tops = cell(1, n);
                bottoms = cell(1, n);
                for i = order
                    s = series{i};
                    ch = seriesChannel(s, label);
                    if isempty(ch)
                        continue;
                    end
                    y = magnitudeOf(s.data(ch, :));
                    band = zeros(size(y));
                    if bandOn && ~isempty(s.stErr)
                        band = bandN * s.stErr(ch, :);
                        band(~isfinite(band)) = 0;
                    end
                    values{i} = y;
                    tops{i} = y + band;
                    bottoms{i} = y - band;
                end
                allValues = [values{:}];
                allTops = [tops{:}];
                allBottoms = [bottoms{:}];
                hi = max([-inf, allTops(~logScale | allTops > 0)], [], "omitnan");
                if logScale
                    positive = [allValues(allValues > 0), allBottoms(allBottoms > 0)];
                    lo = max(min([inf, positive], [], "omitnan"), hi / 10 ^ this.LogDecades);
                else
                    lo = min([0, allBottoms], [], "omitnan");
                end

                for i = order
                    if isempty(values{i})
                        continue;
                    end
                    s = series{i};
                    y = values{i};
                    top = tops{i};
                    bottom = bottoms{i};
                    if logScale
                        y(y <= 0) = NaN;
                        top(top <= 0) = NaN;
                        bottom(~(bottom > lo)) = lo;
                    end
                    colour = this.seriesColour(i, s);
                    if any(top > y)
                        opacity = ternary(this.isOwn(s), 1, this.OverlayOpacity);
                        drawBand(ax, s.freqs, top, bottom, colour, 0.3 * opacity);
                    end
                    lineOf(i) = plot(ax, s.freqs, y, "Color", colour, "LineWidth", 1, ...
                        "Tag", "SpectrumLine", "UserData", i);
                end
            end
            drawn = isgraphics(lineOf);
            handles = lineOf(drawn);
            legendNames = strings(1, 0);
            if numel(names) == n   % single trials have no names, and no legend
                legendNames = names(drawn);
            end
        end

        function [lo, hi, handles, legendNames, yText] = drawDifference(this, ax, names, label, phaseMode, asRatio, unitKind, unitLabel)
        %DRAWDIFFERENCE  The first ticked line against the second at the
        %   channel called LABEL: their difference, their ratio in dB
        %   (10*log10 for a power, 20*log10 for an amplitude), or, with the
        %   phase shown, the phase of the first relative to the second. The
        %   second is interpolated onto the first's frequencies when the two
        %   differ. No band: the standard error of a difference cannot be had
        %   from the two lines' own when they share trials, as AverageView's
        %   difference explains. Nothing is drawn when either line lacks the
        %   channel, or, for a phase, is not complex.
            handles = gobjects(1, 0);
            legendNames = strings(1, 0);
            pair = this.differencePair();
            a = this.Series{pair(1)};
            b = this.Series{pair(2)};
            ca = seriesChannel(a, label);
            cb = seriesChannel(b, label);
            if phaseMode
                yText = 'phase difference (rad)';
                lo = -pi;
                hi = pi;
                if isempty(ca) || isempty(cb) || isreal(a.data) || isreal(b.data)
                    return;
                end
                bOnA = onGrid(b.freqs, b.data(cb, :), a.freqs);
                handles = plot(ax, a.freqs, angle(a.data(ca, :) .* conj(bOnA)), ".", ...
                    "Color", [0 0 0], "MarkerSize", 6, "Tag", "DifferenceLine");
                legendNames = names(pair(1)) + " vs " + names(pair(2));
                return;
            end

            if asRatio
                yText = 'ratio (dB)';
            else
                yText = strtrim(['difference ' unitLabel]);
            end
            lo = 0;
            hi = -inf;
            if isempty(ca) || isempty(cb)
                return;
            end
            ya = magnitudeOf(a.data(ca, :));
            yb = onGrid(b.freqs, magnitudeOf(b.data(cb, :)), a.freqs);
            if asRatio
                y = ternary(strcmp(unitKind, 'power'), 10, 20) * log10(ya ./ yb);
                y(~isfinite(y)) = NaN;
                legendNames = names(pair(1)) + " / " + names(pair(2)) + " (dB)";
            else
                y = ya - yb;
                legendNames = names(pair(1)) + " " + char(8722) + " " + names(pair(2));
            end
            handles = plot(ax, a.freqs, y, "Color", [0 0 0], "LineWidth", 1.5, ...
                "Tag", "DifferenceLine");
            % Both signs, with 0 in view and a margin so the extremes are
            % not drawn on the frame.
            lo = min([0, y], [], "omitnan");
            hi = max([0, y], [], "omitnan");
            margin = 0.05 * max(hi - lo, eps);
            lo = lo - margin;
            hi = hi + margin;
        end

        function drawBandStripes(this, ax, lo, hi)
        %DRAWBANDSTRIPES  Shade each frequency band (AlakazamSettings.getBands,
        %   the "Frequency bands" settings tab) as a pale stripe from LO to
        %   HI, behind whatever is drawn. Stripes rather than the area under
        %   the curve, which is what this view used to shade: with several
        %   spectra there is no one curve to fill under, and on a log axis
        %   an area down to zero cannot be drawn. The y-zoom only ever
        %   narrows the axis inside [LO, HI], so the stripes always fill it.
        %   Read fresh on every redraw, not cached on this view, so editing
        %   the bands in Settings and saving takes effect immediately.
            if ~(isfinite(lo) && isfinite(hi) && hi > lo)
                return;
            end
            freqs = double(this.EEG.freqs);
            fmin = min(freqs);
            fmax = max(freqs);
            bands = AlakazamSettings.getBands();
            stripes = gobjects(1, 0);
            for b = 1:numel(bands)
                x0 = max(bands(b).loFreq, fmin);
                x1 = min(bands(b).hiFreq, fmax);
                if x1 <= x0
                    continue;
                end
                stripes(end + 1) = patch(ax, [x0, x1, x1, x0], [lo, lo, hi, hi], bands(b).color, ...
                    "EdgeColor", "none", "FaceAlpha", FourierView.StripeAlpha, ...
                    "Tag", "BandStripe"); %#ok<AGROW>
            end
            % Behind everything drawn so far. The stripes are ordinary,
            % visible handles because uistack moves an object by reordering
            % its axes' Children, and a hidden handle is not among them.
            if ~isempty(stripes)
                uistack(stripes, "bottom");
            end
        end

        function [series, visible] = drawnSeries(this)
        %DRAWNSERIES  The lines this plot is drawing from, and which are
        %   ticked: the current trial alone for single-trial spectra,
        %   otherwise the plot's own and overlaid series.
            if this.SingleTrials
                series = {sliceSeries(this.EEG, this.CurrentTrial, "", this.HostFile)};
                visible = true;
            else
                series = this.Series;
                visible = this.Visible;
            end
        end

        function tf = showsStrip(this)
        %SHOWSSTRIP  Whether the strip beside the plot has anything to offer:
        %   bins to tick, or an overlay to manage. A single spectrum alone,
        %   and single trials, have neither.
            tf = ~this.SingleTrials && ~isempty(this.Series) ...
                && (this.Series{1}.isBin || numel(this.Series) > 1);
        end

        function tf = isOverlaid(this)
        %ISOVERLAID  Whether another dataset is drawn on this plot.
            tf = any(~cellfun(@(s) this.isOwn(s), this.Series));
        end

        function tf = isOwn(this, s)
        %ISOWN  Whether line S belongs to the plot's own dataset.
            tf = strcmp(s.file, this.HostFile);
        end

        function colour = seriesColour(this, i, s)
        %SERIESCOLOUR  Line I's colour: black when it is the one spectrum
        %   drawn, otherwise its place in the shared palette (lineColour),
        %   paler for an overlaid dataset by the Overlay opacity.
            if ~this.showsStrip()
                colour = [0 0 0];
                return;
            end
            colour = lineColour(i);
            if ~this.isOwn(s)
                colour = paleColour(colour, this.OverlayOpacity, this.Axes.Color);
            end
        end

        function pair = differencePair(this)
        %DIFFERENCEPAIR  The two ticked lines, in the order they are compared.
            pair = find(this.Visible, 2);
            if this.DifferenceSwapped
                pair = fliplr(pair);
            end
        end

        function label = channelLabel(this)
        %CHANNELLABEL  The label of the channel shown, from the plot's own list.
            label = char(string(this.EEG.chanlocs(min(max(this.Channel, 1), ...
                numel(this.EEG.chanlocs))).labels));
        end

        function [names, fullNames] = seriesNames(this)
        %SERIESNAMES  A legend name for every line, and its full tree path.
        %   The plot's own lines are named by their bin, as always. Once
        %   another dataset is overlaid, each name is prefixed with what
        %   tells the datasets apart (overlayNames); a dataset with no known
        %   path is called by its transformation's name, as in AverageView.
            n = numel(this.Series);
            names = strings(1, n);
            for i = 1:n
                names(i) = this.Series{i}.name;
            end
            fullNames = names;
            files = unique(cellfun(@(s) string(s.file), this.Series), 'stable');
            if numel(files) < 2
                return;
            end
            paths = cell(1, numel(files));
            for k = 1:numel(files)
                if isKey(this.Paths, char(files(k)))
                    paths{k} = this.Paths(char(files(k)));
                else
                    first = find(cellfun(@(s) string(s.file) == files(k), this.Series), 1);
                    paths{k} = {char(this.Series{first}.id)};
                end
            end
            [short, full] = overlayNames(paths);
            for i = 1:n
                k = find(files == string(this.Series{i}.file), 1);
                names(i) = short(k) + ": " + this.Series{i}.name;
                fullNames(i) = full(k) + ": " + this.Series{i}.name;
            end
        end

        function text = titleText(this, phaseMode, asRatio)
        %TITLETEXT  The channel, and what else tells this picture apart: the
        %   trial of a single-trial spectrum, with its bin, or the
        %   comparison drawn. The magnitude/phase mode is not named: the
        %   phase's own y label and multiples of pi say which is shown, and
        %   the P key is in the manual's table of keys.
            text = sprintf("Channel %i: %s", this.Channel, this.channelLabel());
            if this.DifferenceOn
                if phaseMode
                    text = text + ", phase difference";
                elseif asRatio
                    text = text + ", ratio";
                else
                    text = text + ", difference";
                end
            elseif this.SingleTrials
                % "i of N" alongside the label/number, not just the label
                % alone: with only a label, stepping to a same- or similarly-
                % named neighbour (or a stale figure that never redrew) reads
                % as "nothing happened" -- the count makes a real step
                % unambiguous even when the label text does not obviously
                % change.
                nseg = size(this.EEG.data, 3);
                where = trialBinPhrase(this.EEG, this.CurrentTrial);
                if isempty(where)
                    text = sprintf('%s   (Trial %i of %i)', text, this.CurrentTrial, nseg);
                else
                    text = sprintf('%s   (Trial %i of %i, %s)', text, this.CurrentTrial, nseg, where);
                end
            end
        end

        function layoutStrip(this)
        %LAYOUTSTRIP  Show the strip in AverageView's proportions, wider while
        %   another dataset is overlaid (its lines carry the dataset's name as
        %   well as the bin's), or give its column no width when it has
        %   nothing to offer.
            if ~this.showsStrip()
                this.PlotRow.ColumnWidth = {'1x', 0};
            elseif this.isOverlaid()
                this.PlotRow.ColumnWidth = {'1x', 200};
            else
                this.PlotRow.ColumnWidth = {'9x', '1x'};
            end
        end

        function buildStrip(this, names, fullNames, label, phaseMode, unitKind)
        %BUILDSTRIP  The strip right of the plot, as AverageView's: one
        %   tickbox per line, reflecting (and toggling) this.Visible; below
        %   them Difference, while it is on Swap and "Ratio in dB", and while
        %   another dataset is overlaid Remove overlay and the overlay
        %   opacity. Rebuilt on every redraw, so it always matches the state.
            delete(this.Strip.Children);
            this.layoutStrip();
            if ~this.showsStrip()
                return;
            end
            n = numel(this.Series);
            overlaid = this.isOverlaid();
            rows = [repmat({22}, 1, n), {24}];                 % tickboxes, Difference
            if this.DifferenceOn;  rows = [rows, {24, 22}];     end   % Swap, Ratio in dB
            if overlaid;           rows = [rows, {24, 16, 24}]; end   % Remove overlay, opacity
            this.Strip.RowHeight = [rows, {'1x'}];

            for i = 1:n
                s = this.Series{i};
                text = names(i);
                if isempty(seriesChannel(s, label))
                    text = sprintf('%s (no %s)', text, label);
                elseif phaseMode && isreal(s.data)
                    text = sprintf('%s (no phase)', text);
                end
                cb = uicheckbox(this.Strip, "Text", char(text), "Tooltip", char(fullNames(i)), ...
                    "Value", this.Visible(i), ...
                    "ValueChangedFcn", @(src, ~) this.onToggle(i, src.Value));
                cb.Layout.Row = i;
            end
            difference = uibutton(this.Strip, "state", "Text", "Difference", ...
                "Value", this.DifferenceOn, "Enable", this.canShowDifference(), ...
                "Tag", "DifferenceButton", ...
                "Tooltip", 'Compare the first ticked line with the second. Tick exactly two lines.', ...
                "ValueChangedFcn", @(src, ~) this.setDifference(src.Value));
            difference.Layout.Row = n + 1;
            row = n + 1;
            if this.DifferenceOn
                row = row + 1;
                swap = uibutton(this.Strip, "Text", "Swap", "Tag", "SwapButton", ...
                    "Tooltip", 'Compare the other way round.', ...
                    "ButtonPushedFcn", @(~, ~) this.swapDifference());
                swap.Layout.Row = row;
                row = row + 1;
                canRatio = ~phaseMode && ~isempty(unitKind);
                ratio = uicheckbox(this.Strip, "Text", "Ratio in dB", "Tag", "RatioCheckbox", ...
                    "Value", this.DifferenceAsRatio && canRatio, "Enable", canRatio, ...
                    "Tooltip", ratioTooltip(phaseMode, unitKind), ...
                    "ValueChangedFcn", @(src, ~) this.setRatio(src.Value));
                ratio.Layout.Row = row;
            end
            if overlaid
                row = row + 1;
                remover = uibutton(this.Strip, "Text", "Remove overlay", ...
                    "Tag", "RemoveOverlayButton", ...
                    "Tooltip", 'Take the overlaid spectra off this plot, keeping its own lines.', ...
                    "ButtonPushedFcn", @(~, ~) this.removeOverlays());
                remover.Layout.Row = row;
                row = row + 1;
                caption = uilabel(this.Strip, "Text", "Overlay opacity", "FontSize", 10);
                caption.Layout.Row = row;
                row = row + 1;
                slider = uislider(this.Strip, "Limits", [0.1 1], ...
                    "Value", this.OverlayOpacity, "MajorTicks", [], "MinorTicks", [], ...
                    "Tag", "OverlayOpacity", ...
                    "Tooltip", 'How strongly the overlaid spectra are drawn, under the plot''s own.', ...
                    "ValueChangedFcn", @(src, ~) this.setOverlayOpacity(src.Value));
                slider.Layout.Row = row;
            end
        end

        function onToggle(this, i, value)
        %ONTOGGLE  A tickbox was (un)checked: draw or drop that line. A
        %   difference needs exactly two lines, so ticking a third (or
        %   unticking one of the two) returns to the lines (see redraw).
            this.Visible(i) = logical(value);
            this.notifyActivated();
            this.redraw();
        end

        function onChannelSelected(this, idx)
        %ONCHANNELSELECTED  The channel dropdown's ValueChangedFcn: jump
        %   straight to the picked electrode, the same effect as stepping
        %   there one channel at a time with the up/down keys (onKey).
            this.notifyActivated();
            this.Channel = idx;
            this.redraw();
        end

        function onStepSelected(this, idx)
        %ONSTEPSELECTED  The trial dropdown's ValueChangedFcn: show the
        %   picked spectrum, as the left/right keys step to it (onKey).
            this.notifyActivated();
            this.CurrentTrial = idx;
            this.redraw();
        end
    end

    methods
        function focus = currentFocus(this)
        %CURRENTFOCUS  The channel this view is showing, by label.
        %   See ViewFocus for why the label rather than the index.
            focus = struct();
            if isempty(this.EEG) || ~isfield(this.EEG, 'chanlocs') || ...
                    this.Channel < 1 || this.Channel > numel(this.EEG.chanlocs)
                return;
            end
            focus.Channel = char(string(this.EEG.chanlocs(this.Channel).labels));
        end

        function applyFocus(this, focus)
        %APPLYFOCUS  Show FOCUS.Channel if this dataset has it.
        %   A label this montage does not carry leaves the view on its own
        %   default, which is the ordinary case when moving between
        %   datasets with different channel sets.
            if ~isstruct(focus) || ~isfield(focus, 'Channel') || isempty(this.EEG) || ...
                    ~isfield(this.EEG, 'chanlocs') || isempty(this.EEG.chanlocs)
                return;
            end
            idx = ViewFocus.indexOfLabel({this.EEG.chanlocs.labels}, focus.Channel);
            if isempty(idx) || idx == this.Channel
                return;
            end
            this.Channel = idx;
            this.redraw();
        end
    end
end

% ======================================================================= %
function series = spectrumSeries(eeg, file)
%SPECTRUMSERIES  EEG's lines: one per bin of an averaged spectrum, else its
%   one spectrum, named by the dataset's transformation (as AverageView
%   names a plain average) or "Spectrum".
    if thirdDimIsBins(eeg)
        series = arrayfun(@(k) sliceSeries(eeg, k, binName(eeg, k), file), ...
            1:size(eeg.data, 3), 'UniformOutput', false);
        return;
    end
    name = string(TransTools.FieldOr(eeg, 'id', ''));
    if strlength(name) == 0
        name = "Spectrum";
    end
    series = {sliceSeries(eeg, 1, name, file)};
end

function s = sliceSeries(eeg, k, name, file)
%SLICESERIES  One line: spectrum K of EEG, with what drawing it needs. Each
%   line carries its own frequencies and channel labels, so a spectrum of
%   another resolution or montage is drawn correctly, and its standard
%   error when Average stored one ([] otherwise).
    se = [];
    if isfield(eeg, 'stErr') && isequal(size(eeg.stErr, 1, 2), size(eeg.data, 1, 2)) ...
            && size(eeg.stErr, 3) >= k
        se = double(real(eeg.stErr(:, :, k)));
    end
    s = struct('file', file, 'id', string(TransTools.FieldOr(eeg, 'id', '')), ...
        'name', string(name), 'freqs', reshape(double(eeg.freqs), 1, []), ...
        'labels', {cellstr(string({eeg.chanlocs.labels}))}, ...
        'data', eeg.data(:, :, k), 'stErr', se, 'isBin', thirdDimIsBins(eeg));
end

function ch = seriesChannel(s, label)
%SERIESCHANNEL  Where the channel called LABEL is in line S, or [] when S
%   does not have it. By label, since an overlaid dataset's channels need
%   not be in the plot's order.
    ch = find(strcmpi(strtrim(s.labels), strtrim(label)), 1);
end

function file = fileOf(eeg)
%FILEOF  A dataset's cache file, its identity on a plot ('' when unknown).
    file = char(string(TransTools.FieldOr(eeg, 'File', '')));
end

function y = magnitudeOf(x)
%MAGNITUDEOF  A spectrum as drawn: its modulus (for complex data) as a real
%   row, smoothed when the Settings say so. A phase is never smoothed, and
%   does not come here: a moving mean over an angle is not a meaningful
%   average (pi and -pi are the same phase).
    y = reshape(double(x), 1, []);
    if ~isreal(y)
        y = abs(y);
    end
    if AlakazamSettings.get('graphics', 'fourierPlot', 'smoothSpectrum')
        y = movmean(y, 5);
    end
end

function yq = onGrid(x, y, xq)
%ONGRID  Y (sampled at frequencies X) at frequencies XQ: itself when the two
%   grids agree, otherwise interpolated, and NaN outside X.
    if numel(x) == numel(xq) && max(abs(x - xq)) < 1e-9
        yq = y;
    else
        yq = interp1(x, y, xq, 'linear', NaN);
    end
end

function colour = paleColour(colour, opacity, background)
%PALECOLOUR  COLOUR as seen at OPACITY over BACKGROUND, mixed by hand as
%   AverageView's paleColour explains (an RGBA line colour is not kept).
    if ~isnumeric(background) || numel(background) ~= 3
        background = [1 1 1];
    end
    colour = opacity * colour + (1 - opacity) * background;
end

function drawBand(ax, freqs, yTop, yBottom, colour, alpha)
%DRAWBAND  The shaded band between YBOTTOM and YTOP, with dotted edges, as
%   AverageView draws its standard-error band. Ordinary visible handles, as
%   there, so that the stripes can be stacked behind them (drawBandStripes);
%   the legend is built from the spectrum lines alone, so they stay out of it.
    ok = isfinite(yTop) & isfinite(yBottom);
    plot(ax, freqs, yTop, "Color", colour, "LineStyle", ":", "Tag", "ErrorBand");
    plot(ax, freqs, yBottom, "Color", colour, "LineStyle", ":", "Tag", "ErrorBand");
    patch(ax, [freqs(ok), fliplr(freqs(ok))], [yTop(ok), fliplr(yBottom(ok))], colour, ...
        "EdgeColor", "none", "FaceAlpha", alpha, "Tag", "ErrorBand");
end

function [kind, label, phrase] = spectrumUnit(EEG)
%SPECTRUMUNIT  What a spectrum holds, from the EEG.SpectrumUnit that Fourier
%   (its Output) and Welch ('PSD') stamp on their result, which Average
%   keeps. KIND is 'power' or 'amplitude', which decides 10*log10 or
%   20*log10 in a ratio in dB; LABEL is the y-axis label; PHRASE says what
%   it is in a sentence, and two spectra with the same PHRASE can share an
%   axis. All three are '' for a spectrum computed before the unit was
%   stamped: the axis is then left unlabelled and the ratio unavailable,
%   rather than guessed.
    kind = '';
    label = '';
    phrase = '';
    if ~isfield(EEG, 'SpectrumUnit') || isempty(EEG.SpectrumUnit)
        return;
    end
    mu = char(181);
    squared = char(178);
    switch lower(char(string(EEG.SpectrumUnit)))
        case {'volt', 'complex'}
            kind = 'amplitude'; label = 'amplitude (\muV)';
            phrase = ['an amplitude (' mu 'V)'];
        case 'voltdens'
            kind = 'amplitude'; label = 'amplitude density (\muV/Hz)';
            phrase = ['an amplitude density (' mu 'V/Hz)'];
        case 'power'
            kind = 'power'; label = 'power (\muV^2)';
            phrase = ['a power (' mu 'V' squared ')'];
        case 'powerdens'
            kind = 'power'; label = 'power density (\muV^2/Hz)';
            phrase = ['a power density (' mu 'V' squared '/Hz)'];
        case 'psd'
            kind = 'power'; label = 'PSD (\muV^2/Hz)';
            phrase = ['a PSD (' mu 'V' squared '/Hz)'];
    end
end

function text = ratioTooltip(phaseMode, unitKind)
%RATIOTOOLTIP  What "Ratio in dB" does here, or why it cannot.
    if phaseMode
        text = 'A phase is compared by its difference.';
    elseif isempty(unitKind)
        text = ['This spectrum does not say whether it is a power or an amplitude; ' ...
            'run its Fourier or Welch step again to compare in dB.'];
    elseif strcmp(unitKind, 'power')
        text = 'The first line over the second in dB: 10*log10 of their ratio, since this is a power.';
    else
        text = 'The first line over the second in dB: 20*log10 of their ratio, since this is an amplitude.';
    end
end

function [on, n] = errorBandSettings()
%ERRORBANDSETTINGS  Whether a standard-error band is drawn, and how many
%   standard errors wide: the ERP plot's own settings (Settings > Graphics),
%   so one choice governs the bands of both kinds of average.
    on = AlakazamSettings.get('graphics', 'erpPlot', 'showConfInt');
    n = AlakazamSettings.get('graphics', 'erpPlot', 'confIntN');
end

function out = ternary(condition, a, b)
%TERNARY  A if CONDITION, else B.
    if condition
        out = a;
    else
        out = b;
    end
end

function name = binName(EEG, b)
%BINNAME  A bin's name in the tickbox and the legend: its label and, where
%   Average recorded it, its trial count, as AverageView names its lines.
    name = string(binLabel(EEG, b));
    if isfield(EEG, 'bindesc') && numel(EEG.bindesc) >= b && isfield(EEG.bindesc, 'n') ...
            && ~isempty(EEG.bindesc(b).n)
        name = name + " (n=" + string(EEG.bindesc(b).n) + ")";
    end
end

function items = trialItems(EEG)
%TRIALITEMS  The trial dropdown's items: each trial's number and, where it
%   belongs to one, its bin, in the words the title uses ('37, in bin
%   "Rare"'), since the number alone says nothing about the condition.
    nseg = size(EEG.data, 3);
    items = cell(1, nseg);
    for t = 1:nseg
        where = trialBinPhrase(EEG, t);
        if isempty(where)
            items{t} = sprintf('%d', t);
        else
            items{t} = sprintf('%d, %s', t, where);
        end
    end
end

function phrase = trialBinPhrase(EEG, t)
%TRIALBINPHRASE  The bin(s) trial T belongs to, as title text ('' if none).
%
%   Membership itself is Support/trialBins; this is only the wording.
%
%   THE LABEL IS QUOTED because bin labels routinely contain commas -- real
%   ones from DefineBins read like 'frequent (c), preceded by rare (c)' --
%   and the phrase is dropped into an already comma-separated title.
%   Unquoted, 'Trial 40 of 197, in bin: frequent (c), preceded by rare (c)'
%   leaves the reader no way to see where the bin name ends, or whether
%   they are looking at one bin or two.
    phrase = '';
    bins = trialBins(EEG, t);
    if isempty(bins)
        return;
    end
    quoted = arrayfun(@(b) sprintf('"%s"', binLabel(EEG, b)), bins, ...
        'UniformOutput', false);
    if isscalar(quoted)
        phrase = sprintf('in bin %s', quoted{1});
    else
        phrase = sprintf('in bins %s', strjoin(quoted, ', '));
    end
end

function label = binLabel(EEG, b)
%BINLABEL  EEG.bindesc(b)'s own label, or the bare bin number as a
%   fallback -- identical to SpectralMeasureView's own local binLabel
%   (its near-twin, see this file's own header comment), not
%   src/Support/csvBinLabel.m: that helper deliberately skips the
%   char(string(...)) normalisation this one needs for direct use in a
%   plot title (see csvBinLabel's own header comment on why the two are
%   kept separate).
    if isfield(EEG, 'bindesc') && numel(EEG.bindesc) >= b && ~isempty(EEG.bindesc(b).label)
        label = char(string(EEG.bindesc(b).label));
    else
        label = num2str(b);
    end
end
