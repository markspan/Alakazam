classdef FourierView < handle
%FOURIERVIEW  Frequency-domain view with band shading and zoom/pan controls.
%
%   FourierView draws a power spectrum per channel in a subplot grid, with the
%   classic EEG frequency bands shaded, and provides push-button zoom, pan and
%   (for multi-trial data) trial navigation. Clicking a channel opens a larger
%   single-channel detail view. It replaces the old Tools.plotFourier function
%   with a clean stateful class.
%
%   Differences from the original: the super-title over the grid uses the
%   built-in sgtitle instead of the third-party mtit (which was never bundled),
%   and the detail view is drawn in its own axes rather than over a subplot.
%
%   Style follows the project standard.
%
%   See also ALAKAZAMPLOTTER, EPOCHVIEW, AVERAGEVIEW.

    properties (SetAccess = private)
        Figure          % owning figure
        EEG             % frequency-domain dataset (channels x freqs x trials)
        CurrentTrial = 1
        Axes            % array of grid axes, or the single detail axes
        Mode = "grid"   % "grid" or "detail"
    end

    properties (Constant, Access = private)
        % Name, low edge, high edge, colour for each shaded band.
        Bands = { ...
            "Sub-Delta", 0,    0.5,  [119 136 153] / 255; ...
            "Delta",     0.5,  3.5,  [255 165 0]   / 255; ...
            "Theta",     3.5,  7.5,  [1 0 0]; ...
            "Alpha",     7.5,  12.5, [0 1 0]; ...
            "Beta",      12.5, 30,   [0 0 1]; ...
            "",          30,   1000, [0 0 0]}
    end

    methods
        function this = FourierView(fig, eeg)
        %FOURIERVIEW  Build the frequency-domain view for EEG in FIG.
            this.Figure = fig;
            this.EEG    = eeg;
            this.drawGrid();
        end
    end

    methods (Access = private)
        function drawGrid(this)
        %DRAWGRID  One shaded spectrum per channel in a tight subplot grid.
            clf(this.Figure);
            data  = this.EEG.data;
            freqs = this.EEG.freqs;
            lims  = [0, floor(this.EEG.srate / 2), 0, max(data(:))];
            [nchan, ~, nseg] = size(data);

            rows = max(1, floor(sqrt(nchan)));
            cols = ceil(nchan / rows);
            grid = gobjects(1, nchan);
            for p = 1:nchan
                grid(p) = uiextras.subplot_tight(cols, rows, p, [0.035, 0.03]);
                cla(grid(p));
                hold(grid(p), "on");
                this.drawBands(grid(p), freqs, data(p, :, this.CurrentTrial));
                hold(grid(p), "off");
                title(grid(p), sprintf("Channel %i: %s", p, this.EEG.chanlocs(p).labels));
                axis(grid(p), lims);
                set(grid(p), "ButtonDownFcn", @(~, ~) this.showDetail(p));
            end
            linkaxes(grid);

            this.Axes = grid;
            this.Mode = "grid";
            this.addButtons(nseg > 1);
            if nseg > 1
                sgtitle(this.Figure, sprintf("Trial: %i", this.CurrentTrial));
            end
        end

        function showDetail(this, channel)
        %SHOWDETAIL  Larger single-channel spectrum (band shading plus line).
            clf(this.Figure);
            freqs = this.EEG.freqs;
            data1d = reshape(this.EEG.data(channel, :, this.CurrentTrial), 1, []);
            ax = axes("Parent", this.Figure);
            hold(ax, "on");
            this.drawBands(ax, freqs, data1d);
            plot(ax, freqs, data1d);
            hold(ax, "off");
            title(ax, sprintf("Channel %i: %s", channel, this.EEG.chanlocs(channel).labels));
            axis(ax, [0, max(freqs), 0, max(data1d)]);

            this.Axes = ax;
            this.Mode = "detail";
            this.addButtons(false);
        end

        function drawBands(this, ax, freqs, spectrum)
        %DRAWBANDS  Shade each frequency band under the spectrum in AX.
            spectrum = reshape(spectrum, 1, []);
            for b = 1:6
                lo = this.Bands{b, 2};
                hi = this.Bands{b, 3};
                colour = this.Bands{b, 4};
                idx = find(freqs > lo & freqs <= hi);
                if isempty(idx)
                    continue;
                end
                % Frequencies are sorted, so the band is a contiguous range;
                % include the leading edge sample for a clean fill.
                sel = max(1, idx(1) - 1):idx(end);
                area(ax, freqs(sel), spectrum(sel), ...
                    "EdgeColor", "k", "EdgeAlpha", 0.33, "FaceColor", colour);
            end
        end

        function addButtons(this, includeTrial)
        %ADDBUTTONS  Zoom / pan (and optionally trial) push-buttons.
            make = @(str, x, cb) uicontrol("Parent", this.Figure, "Style", "pushbutton", ...
                "String", str, "Position", [x, 5, 20, 20], "Callback", cb);
            make("+", 20,  @(~, ~) this.zoomX(0.5));   % zoom in (x)
            make("-", 50,  @(~, ~) this.zoomX(2));     % zoom out (x)
            make("^", 80,  @(~, ~) this.zoomY(0.5));   % magnify (y)
            make("v", 110, @(~, ~) this.zoomY(2));     % shrink (y)
            make("<", 140, @(~, ~) this.panX(-1));     % pan left
            make(">", 170, @(~, ~) this.panX(1));      % pan right
            if includeTrial
                make("<<", 230, @(~, ~) this.trialStep(-1));
                make(">>", 260, @(~, ~) this.trialStep(1));
            end
        end

        function zoomX(this, factor)
        %ZOOMX  Scale the x range about its left edge (factor < 1 zooms in).
            ax = this.Axes(1);
            span = xlim(ax);
            newHigh = span(1) + (span(2) - span(1)) * factor;
            if factor > 1
                newHigh = min(newHigh, this.EEG.srate / 2);
            end
            xlim(ax, [span(1), newHigh]);
        end

        function zoomY(this, factor)
        %ZOOMY  Scale the y range about its bottom edge.
            ax = this.Axes(1);
            span = ylim(ax);
            ylim(ax, [span(1), span(1) + (span(2) - span(1)) * factor]);
        end

        function panX(this, direction)
        %PANX  Shift the x range by a tenth of its width, clamped to [0, fs/2].
            ax = this.Axes(1);
            span = xlim(ax);
            shifted = span + direction * (span(2) - span(1)) / 10;
            if shifted(1) < 0
                shifted = shifted - shifted(1);
            end
            if shifted(2) > this.EEG.srate / 2
                shifted = shifted - (shifted(2) - this.EEG.srate / 2);
            end
            xlim(ax, shifted);
        end

        function trialStep(this, delta)
        %TRIALSTEP  Move to the previous / next trial and redraw the grid.
            nseg = size(this.EEG.data, 3);
            this.CurrentTrial = min(nseg, max(1, this.CurrentTrial + delta));
            this.drawGrid();
        end
    end
end
