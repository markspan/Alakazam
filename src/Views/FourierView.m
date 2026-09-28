classdef FourierView < AlakazamView
%FOURIERVIEW  Keyboard-driven view of a frequency-domain dataset.
%
%   FourierView draws one channel's spectrum at a time, over the frequency
%   bands shaded in the background (from AlakazamSettings.getBands,
%   user-editable on the Settings dialog's own "Frequency bands" tab -- see
%   drawBandStripes) and, optionally, a light moving-average smoothing over
%   the plotted spectrum (the "Smooth spectrum" checkbox on the Settings
%   dialog's "Graphics" tab -- see spectrumValues), and steps through
%   channels with the up/down arrow keys -- the same interaction model
%   EpochView and AverageView already use for time-domain data. Replaces the
%   previous grid-of-every-channel-at-once layout with
%   click-to-drill-into-detail, which needed its own rebuild-in-place
%   machinery (captureSlot/buildOuterGrid) that a single persistent axes,
%   redrawn in place like EpochView/AverageView, does not.
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
%     * AVERAGED SPECTRA, one per bin, are OVERLAID, as AverageView overlays
%       ERPs: a tickbox per bin in a strip right of the plot, each ticked bin
%       a line in its own colour (lineColour, the palette AverageView uses,
%       so a bin keeps its colour from waveform to spectrum), with a legend
%       and, where Average stored one, a band of n standard errors (the ERP
%       plot's own "Show confidence interval" settings). With exactly two
%       bins ticked, Difference draws the first minus the second (Swap
%       reverses it), or, with "Ratio in dB", their ratio in decibels:
%       10*log10 for a power and 20*log10 for an amplitude, read from the
%       unit Fourier and Welch stamp on the data (EEG.SpectrumUnit, see
%       spectrumUnit). The ratio is how conditions are usually contrasted in
%       a spectrum, since it does not depend on the 1/f level. On a complex
%       spectrum with the phase shown, the difference is the phase of A
%       relative to B, angle(A .* conj(B)).
%     * SINGLE-TRIAL SPECTRA are shown one at a time, picked with a
%       "Trial:" dropdown that names each trial's bin, or the left/right
%       keys. Hundreds of single trials laid over each other show nothing;
%       Average them to compare bins.
%     * ONE SPECTRUM PER CHANNEL (a continuous recording, Welch) is a single
%       line.
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
%   ZOOMPANBUTTONS, LINECOLOUR.

    properties
    end

    properties (SetAccess = private)
        Figure          % owning figure
        EEG             % frequency-domain dataset (channels x freqs x trials or bins)
        Grid            % 4x1 uigridlayout: controls | plot | x-zoom | y-zoom (built once, never rebuilt)
        ChannelDropdown % "Channel:" uidropdown (see TransTools.BuildChannelDropdown), row 1
        StepDropdown    % "Trial:" uidropdown (TransTools.BuildBinDropdown), row 1, for
                        % single-trial spectra only; empty otherwise
        LogScaleBox     % "Log scale" uicheckbox, row 1
        Axes            % the single axes the spectra are drawn in
        Strip           % uigridlayout right of the axes for the bin tickboxes and
                        % Difference controls; empty unless Overlay
        Zoom            % ZoomPanButtons, the x/y zoom sliders alone (no button row)
        Overlay         % true for averaged spectra: every ticked bin drawn at once
        Channel = 1     % channel currently shown
        CurrentTrial = 1    % single-trial spectrum shown (not used when Overlay)
        ShowPhase = false   % complex data only: plot angle() rather than abs()
        Visible             % Overlay only: logical row, one per bin, is it drawn?
        DifferenceOn = false        % drawing the first ticked bin against the second?
        DifferenceSwapped = false   % ... or the second against the first
        DifferenceAsRatio = false   % ... as their ratio in dB rather than a difference
        LogScale = false            % magnitude on a logarithmic axis?
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
            this.Overlay = thirdDimIsBins(eeg);

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
            if ~this.Overlay && size(eeg.data, 3) > 1
                this.StepDropdown = TransTools.BuildBinDropdown(controls, 1, 2, ...
                    trialItems(eeg), @(idx) this.onStepSelected(idx), "Trial:");
            end
            this.LogScaleBox = uicheckbox(controls, "Text", "Log scale", "Value", false, ...
                "Tag", "LogScale", ...
                "ValueChangedFcn", @(src, ~) this.setLogScale(src.Value));
            this.LogScaleBox.Layout.Column = 3;

            % Row 2: the plot, and for averaged spectra the tickbox strip
            % beside it, in AverageView's proportions. Nested, so that the
            % rows around it keep a single column.
            if this.Overlay
                plotRow = uigridlayout(this.Grid, [1 2], "ColumnWidth", {'9x', '1x'}, ...
                    "Padding", [0 0 0 0]);
                plotRow.Layout.Row = 2;
                this.Axes = uiaxes(plotRow);
                this.Axes.Layout.Column = 1;
                this.Strip = uigridlayout(plotRow, [1 1], "Padding", [0 0 0 0]);
                this.Strip.Layout.Column = 2;
                this.Visible = true(1, size(eeg.data, 3));
            else
                this.Axes = uiaxes(this.Grid);
                this.Axes.Layout.Row = 2;
            end
            this.Axes.ButtonDownFcn = @(~, ~) this.notifyActivated();

            this.Zoom = ZoomPanButtons(this.Grid, [3 4], this.Axes, eeg.srate / 2, ...
                @() this.notifyActivated());
            this.redraw();
            axtoolbar(this.Axes, "default");
        end

        function redraw(this)
        %REDRAW  Draw the spectra shown at the current channel: every ticked
        %   bin (averaged spectra), or the current trial, or the one spectrum,
        %   or the difference or ratio of two ticked bins; then the axes'
        %   scale, limits, labels and title, and the controls that follow
        %   the state.
            ax = this.Axes;
            delete(allchild(ax));
            freqs = reshape(double(this.EEG.freqs), 1, []);

            % COMPLEX DATA MUST NEVER REACH plot() AS-IS. Fourier's
            % 'Complex' output keeps the raw coefficients, and plot() given
            % complex y IGNORES the x argument entirely and draws real
            % against imaginary -- a picture that looks like a plot, is not
            % a spectrum, and carries no frequency axis at all. Every value
            % drawn is made real first (spectrumValues, drawDifference).
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

            hold(ax, "on");
            if this.DifferenceOn
                [lo, hi, handles, names, yText] = this.drawDifference(ax, freqs, phaseMode, asRatio, unitKind, unitLabel);
            else
                [lo, hi, handles, names] = this.drawSpectra(ax, freqs, phaseMode, logScale);
                yText = ternary(phaseMode, 'phase (rad)', unitLabel);
            end
            if logScale && ~(isfinite(lo) && isfinite(hi) && lo > 0 && hi > lo)
                ax.YScale = 'linear';   % nothing positive to put on a log axis
                lo = 0;
            end
            if ~phaseMode
                this.drawBandStripes(ax, freqs, lo, hi);
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
            if this.Overlay && ~isempty(handles)
                legend(handles, cellstr(names), "Location", "northeast", "Interpreter", "none");
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
            if this.Overlay
                this.buildStrip(phaseMode, unitKind);
            end
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
                    if isempty(this.StepDropdown)
                        return;   % bins are ticked, not stepped
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

        function setLogScale(this, on)
        %SETLOGSCALE  Draw the magnitude on a logarithmic axis, or a linear one.
            this.LogScale = logical(on);
            this.notifyActivated();
            this.redraw();
        end

        function tf = canShowDifference(this)
        %CANSHOWDIFFERENCE  A difference needs averaged spectra with exactly
        %   two bins ticked.
            tf = this.Overlay && nnz(this.Visible) == 2;
        end

        function setDifference(this, on)
        %SETDIFFERENCE  Draw the two ticked bins' difference, or the bins.
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
        %SETRATIO  Show the two ticked bins' ratio in dB, or their difference.
            this.DifferenceAsRatio = logical(on);
            this.notifyActivated();
            this.redraw();
        end
    end

    methods (Access = private)
        function [lo, hi, handles, names] = drawSpectra(this, ax, freqs, phaseMode, logScale)
        %DRAWSPECTRA  Every spectrum shown (shownSpectra) at the current
        %   channel, each over its standard-error band where there is one,
        %   and the natural y-range [LO, HI] they need. A magnitude axis
        %   starts at 0 unless the data dips below it (a combination bin can).
        %   On a log axis values at or below zero are left out, and LO is
        %   the smallest value drawn, but no more than LogDecades below the
        %   largest; a band edge below LO is drawn down to it.
            shown = this.shownSpectra();
            handles = gobjects(1, 0);
            names = strings(1, 0);
            if phaseMode
                lo = -pi;
                hi = pi;
                for k = shown
                    % Points, not a line: a wrapped phase jumps between pi
                    % and -pi, and a line would draw each jump as a
                    % vertical stroke.
                    handles(end + 1) = plot(ax, freqs, this.spectrumValues(k, true), ".", ...
                        "Color", this.colourOf(k), "MarkerSize", 6, ...
                        "Tag", "SpectrumLine", "UserData", k); %#ok<AGROW>
                    names(end + 1) = binName(this.EEG, k); %#ok<AGROW>
                end
                return;
            end

            % First every value, to know the range; then the drawing, since
            % on a log axis a band's lower edge is drawn down to that range.
            [bandOn, bandN] = errorBandSettings();
            n = numel(shown);
            values = nan(n, numel(freqs));
            tops = values;
            bottoms = values;
            for i = 1:n
                y = this.spectrumValues(shown(i), false);
                band = zeros(size(y));
                if this.Overlay && bandOn
                    band = bandN * this.standardError(shown(i));
                end
                values(i, :) = y;
                tops(i, :) = y + band;
                bottoms(i, :) = y - band;
            end
            if logScale
                values(values <= 0) = NaN;
                tops(tops <= 0) = NaN;
                hi = max([-inf; tops(:)], [], "omitnan");
                positive = [values(values > 0); bottoms(bottoms > 0)];
                lo = max(min([inf; positive], [], "omitnan"), hi / 10 ^ this.LogDecades);
                bottoms(~(bottoms > lo)) = lo;
            else
                hi = max([-inf; tops(:)], [], "omitnan");
                lo = min([0; bottoms(:)], [], "omitnan");
            end

            for i = 1:n
                k = shown(i);
                colour = this.colourOf(k);
                if any(tops(i, :) > values(i, :))
                    drawBand(ax, freqs, tops(i, :), bottoms(i, :), colour);
                end
                handles(end + 1) = plot(ax, freqs, values(i, :), "Color", colour, ...
                    "LineWidth", 1, "Tag", "SpectrumLine", "UserData", k); %#ok<AGROW>
                names(end + 1) = binName(this.EEG, k); %#ok<AGROW>
            end
        end

        function colour = colourOf(this, k)
        %COLOUROF  Spectrum K's colour: its bin's (lineColour) when bins are
        %   overlaid, black when there is one spectrum to draw.
            colour = [0 0 0];
            if this.Overlay
                colour = lineColour(k);
            end
        end

        function [lo, hi, handles, names, yText] = drawDifference(this, ax, freqs, phaseMode, asRatio, unitKind, unitLabel)
        %DRAWDIFFERENCE  The first ticked bin against the second: their
        %   difference, their ratio in dB (10*log10 for a power, 20*log10
        %   for an amplitude), or, with the phase shown, the phase of the
        %   first relative to the second. No band: the standard error of a
        %   difference cannot be had from the two bins' own when they share
        %   trials, as AverageView's difference explains.
            pair = this.differencePair();
            [a, b] = deal(pair(1), pair(2));
            names = binName(this.EEG, a);
            if phaseMode
                y = angle(this.rawSpectrum(a) .* conj(this.rawSpectrum(b)));
                handles = plot(ax, freqs, y, ".", "Color", [0 0 0], "MarkerSize", 6, ...
                    "Tag", "DifferenceLine");
                names = names + " vs " + binName(this.EEG, b);
                yText = 'phase difference (rad)';
                lo = -pi; hi = pi;
                return;
            end
            ya = this.spectrumValues(a, false);
            yb = this.spectrumValues(b, false);
            if asRatio
                y = ternary(strcmp(unitKind, 'power'), 10, 20) * log10(ya ./ yb);
                y(~isfinite(y)) = NaN;
                names = names + " / " + binName(this.EEG, b) + " (dB)";
                yText = 'ratio (dB)';
            else
                y = ya - yb;
                names = names + " " + char(8722) + " " + binName(this.EEG, b);
                yText = strtrim(['difference ' unitLabel]);
            end
            handles = plot(ax, freqs, y, "Color", [0 0 0], "LineWidth", 1.5, ...
                "Tag", "DifferenceLine");
            % Both signs, with 0 in view and a margin so the extremes are
            % not drawn on the frame.
            lo = min([0, y], [], "omitnan");
            hi = max([0, y], [], "omitnan");
            margin = 0.05 * max(hi - lo, eps);
            lo = lo - margin;
            hi = hi + margin;
        end

        function drawBandStripes(~, ax, freqs, lo, hi)
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
            bands = AlakazamSettings.getBands();
            fmin = min(freqs);
            fmax = max(freqs);
            for b = 1:numel(bands)
                x0 = max(bands(b).loFreq, fmin);
                x1 = min(bands(b).hiFreq, fmax);
                if x1 <= x0
                    continue;
                end
                stripe = patch(ax, [x0, x1, x1, x0], [lo, lo, hi, hi], bands(b).color, ...
                    "EdgeColor", "none", "FaceAlpha", FourierView.StripeAlpha, ...
                    "HandleVisibility", "off", "Tag", "BandStripe");
                uistack(stripe, "bottom");
            end
        end

        function shown = shownSpectra(this)
        %SHOWNSPECTRA  Which spectra of the third dimension are drawn: the
        %   ticked bins of averaged spectra, otherwise the current trial (or
        %   the only spectrum).
            if this.Overlay
                shown = find(this.Visible);
            else
                shown = this.CurrentTrial;
            end
        end

        function pair = differencePair(this)
        %DIFFERENCEPAIR  The two ticked bins, in the order they are compared.
            pair = find(this.Visible, 2);
            if this.DifferenceSwapped
                pair = fliplr(pair);
            end
        end

        function x = rawSpectrum(this, k)
        %RAWSPECTRUM  Spectrum K at the current channel as stored: complex for
        %   Fourier's Complex output.
            x = reshape(this.EEG.data(this.Channel, :, k), 1, []);
        end

        function y = spectrumValues(this, k, phaseMode)
        %SPECTRUMVALUES  Spectrum K at the current channel as drawn: its
        %   wrapped phase, or its magnitude (the modulus, for complex data),
        %   smoothed when the Settings say so. A phase is never smoothed: a
        %   moving mean over an angle is not a meaningful average (pi and -pi
        %   are the same phase).
            x = double(this.rawSpectrum(k));
            if phaseMode
                y = angle(x);
                return;
            end
            y = x;
            if ~isreal(x)
                y = abs(x);
            end
            if AlakazamSettings.get('graphics', 'fourierPlot', 'smoothSpectrum')
                y = movmean(y, 5);
            end
        end

        function se = standardError(this, k)
        %STANDARDERROR  Average's standard error of spectrum K at the current
        %   channel, or zeros when the dataset carries none.
            se = zeros(1, size(this.EEG.data, 2));
            if isfield(this.EEG, 'stErr') && isequal(size(this.EEG.stErr, 1, 2), size(this.EEG.data, 1, 2)) ...
                    && size(this.EEG.stErr, 3) >= k
                se = reshape(double(real(this.EEG.stErr(this.Channel, :, k))), 1, []);
                se(~isfinite(se)) = 0;
            end
        end

        function text = titleText(this, phaseMode, asRatio)
        %TITLETEXT  The channel, and what else tells this picture apart: the
        %   trial of a single-trial spectrum, with its bin, or the
        %   comparison drawn. The magnitude/phase mode is not named: the
        %   phase's own y label and multiples of pi say which is shown, and
        %   the P key is in the manual's table of keys.
            text = sprintf("Channel %i: %s", this.Channel, this.EEG.chanlocs(this.Channel).labels);
            nseg = size(this.EEG.data, 3);
            if this.DifferenceOn
                if phaseMode
                    text = text + ", phase difference";
                elseif asRatio
                    text = text + ", ratio";
                else
                    text = text + ", difference";
                end
            elseif ~this.Overlay && nseg > 1
                % "i of N" alongside the label/number, not just the label
                % alone: with only a label, stepping to a same- or similarly-
                % named neighbour (or a stale figure that never redrew) reads
                % as "nothing happened" -- the count makes a real step
                % unambiguous even when the label text does not obviously
                % change.
                where = trialBinPhrase(this.EEG, this.CurrentTrial);
                if isempty(where)
                    text = sprintf('%s   (Trial %i of %i)', text, this.CurrentTrial, nseg);
                else
                    text = sprintf('%s   (Trial %i of %i, %s)', text, this.CurrentTrial, nseg, where);
                end
            end
        end

        function buildStrip(this, phaseMode, unitKind)
        %BUILDSTRIP  The strip right of the plot, as AverageView's: one
        %   tickbox per bin, reflecting (and toggling) this.Visible; below
        %   them Difference, and while it is on, Swap and "Ratio in dB".
        %   Rebuilt on every redraw, so it always matches the state.
            delete(this.Strip.Children);
            n = numel(this.Visible);
            rows = [repmat({22}, 1, n), {24}];
            if this.DifferenceOn
                rows = [rows, {24, 22}];
            end
            this.Strip.RowHeight = [rows, {'1x'}];

            for k = 1:n
                cb = uicheckbox(this.Strip, "Text", char(binName(this.EEG, k)), ...
                    "Tooltip", char(binName(this.EEG, k)), "Value", this.Visible(k), ...
                    "ValueChangedFcn", @(src, ~) this.onToggle(k, src.Value));
                cb.Layout.Row = k;
            end
            difference = uibutton(this.Strip, "state", "Text", "Difference", ...
                "Value", this.DifferenceOn, "Enable", this.canShowDifference(), ...
                "Tag", "DifferenceButton", ...
                "Tooltip", 'Compare the first ticked bin with the second. Tick exactly two bins.', ...
                "ValueChangedFcn", @(src, ~) this.setDifference(src.Value));
            difference.Layout.Row = n + 1;
            if ~this.DifferenceOn
                return;
            end
            swap = uibutton(this.Strip, "Text", "Swap", "Tag", "SwapButton", ...
                "Tooltip", 'Compare the other way round.', ...
                "ButtonPushedFcn", @(~, ~) this.swapDifference());
            swap.Layout.Row = n + 2;
            canRatio = ~phaseMode && ~isempty(unitKind);
            ratio = uicheckbox(this.Strip, "Text", "Ratio in dB", "Tag", "RatioCheckbox", ...
                "Value", this.DifferenceAsRatio && canRatio, "Enable", canRatio, ...
                "ValueChangedFcn", @(src, ~) this.setRatio(src.Value));
            ratio.Layout.Row = n + 3;
            if phaseMode
                ratio.Tooltip = 'A phase is compared by its difference.';
            elseif isempty(unitKind)
                ratio.Tooltip = ['This spectrum does not say whether it is a power or an ' ...
                    'amplitude; run its Fourier or Welch step again to compare in dB.'];
            else
                isPower = strcmp(unitKind, 'power');
                ratio.Tooltip = sprintf(['The first bin over the second in dB: %s of their ' ...
                    'ratio, since this spectrum is %s.'], ...
                    ternary(isPower, '10*log10', '20*log10'), ternary(isPower, 'a power', 'an amplitude'));
            end
        end

        function onToggle(this, k, value)
        %ONTOGGLE  A tickbox was (un)checked: draw or drop that bin. A
        %   difference needs exactly two bins, so ticking a third (or
        %   unticking one of the two) returns to the bins (see redraw).
            this.Visible(k) = logical(value);
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

function [kind, label] = spectrumUnit(EEG)
%SPECTRUMUNIT  What a spectrum holds, from the EEG.SpectrumUnit that Fourier
%   (its Output) and Welch ('PSD') stamp on their result, which Average
%   keeps. KIND is 'power' or 'amplitude', which decides 10*log10 or
%   20*log10 in a ratio in dB; LABEL is the y-axis label. Both are '' for a
%   spectrum computed before the unit was stamped: the axis is then left
%   unlabelled and the ratio unavailable, rather than guessed.
    kind = '';
    label = '';
    if ~isfield(EEG, 'SpectrumUnit') || isempty(EEG.SpectrumUnit)
        return;
    end
    switch lower(char(string(EEG.SpectrumUnit)))
        case {'volt', 'complex'}
            kind = 'amplitude'; label = 'amplitude (\muV)';
        case 'voltdens'
            kind = 'amplitude'; label = 'amplitude density (\muV/Hz)';
        case 'power'
            kind = 'power'; label = 'power (\muV^2)';
        case 'powerdens'
            kind = 'power'; label = 'power density (\muV^2/Hz)';
        case 'psd'
            kind = 'power'; label = 'PSD (\muV^2/Hz)';
    end
end

function drawBand(ax, freqs, yTop, yBottom, colour)
%DRAWBAND  The shaded band between YBOTTOM and YTOP, with dotted edges, as
%   AverageView draws its standard-error band.
    ok = isfinite(yTop) & isfinite(yBottom);
    plot(ax, freqs, yTop, "Color", colour, "LineStyle", ":", "HandleVisibility", "off");
    plot(ax, freqs, yBottom, "Color", colour, "LineStyle", ":", "HandleVisibility", "off");
    patch(ax, [freqs(ok), fliplr(freqs(ok))], [yTop(ok), fliplr(yBottom(ok))], colour, ...
        "EdgeColor", "none", "FaceAlpha", 0.3, "HandleVisibility", "off");
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
