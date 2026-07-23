classdef FourierView < handle
%FOURIERVIEW  Keyboard-driven view of a frequency-domain dataset.
%
%   FourierView draws one channel's power spectrum at a time, with the
%   classic EEG frequency bands shaded, and steps through channels with the
%   up/down arrow keys -- left/right step the trial, for multi-trial data --
%   the same interaction model EpochView and AverageView already use for
%   time-domain data. Replaces the previous grid-of-every-channel-at-once
%   layout with click-to-drill-into-detail, which needed its own rebuild-in-
%   place machinery (captureSlot/buildOuterGrid) that a single persistent
%   axes, redrawn in place like EpochView/AverageView, does not.
%
%   Zoom/pan push-buttons remain (frequency data commonly needs zooming into
%   a specific band, clamped to [0, srate/2] -- something the generic
%   axtoolbar zoom does not do), as do the trial-step buttons alongside the
%   new left/right arrow keys.
%
%   Style follows the project standard.
%
%   See also ALAKAZAMPLOTTER, EPOCHVIEW, AVERAGEVIEW.

    properties
        % Called (no args) when the user clicks this view's axes or presses
        % a zoom/pan/trial button. Wired by AlakazamPlotter to
        % Alakazam.registerTileClick, so keyboard shortcuts route to
        % whichever tile was last clicked while several are visible at once
        % in Grid/Stack mode -- see Alakazam.dispatchKey and migration.md.
        ActivatedFcn = function_handle.empty
    end

    properties (SetAccess = private)
        Figure          % owning figure
        EEG             % frequency-domain dataset (channels x freqs x trials)
        Grid            % 2x1 uigridlayout: axes | buttons (built once, never rebuilt)
        Axes            % the single axes the current channel's spectrum is drawn in
        Channel = 1     % channel currently shown
        CurrentTrial = 1
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

            % Key handling is wired by the shared Alakazam-level dispatcher
            % (Alakazam.dispatchKey), not a per-view fig.KeyPressFcn here:
            % every open dataset is now a uitab on one shared uifigure, so a
            % per-view KeyPressFcn would be overwritten by whichever view was
            % constructed last, breaking key navigation on every other open
            % tab.
            this.Grid = uigridlayout(fig, [2 1], "RowHeight", {'1x', 32}, ...
                "Padding", [2 2 2 2], "RowSpacing", 2);
            this.Axes = uiaxes(this.Grid);
            this.Axes.Layout.Row = 1;
            this.Axes.ButtonDownFcn = @(~, ~) this.notifyActivated();

            this.addButtons(size(eeg.data, 3) > 1);
            this.redraw();
            axtoolbar(this.Axes, "default");
        end

        function redraw(this)
        %REDRAW  Draw the current channel's spectrum (current trial, for
        %   multi-trial data), with band shading.
            ax = this.Axes;
            delete(allchild(ax));
            freqs    = this.EEG.freqs;
            spectrum = reshape(this.EEG.data(this.Channel, :, this.CurrentTrial), 1, []);

            hold(ax, "on");
            this.drawBands(ax, freqs, spectrum);
            plot(ax, freqs, spectrum, "Color", "k", "LineWidth", 1);
            hold(ax, "off");

            titleStr = sprintf("Channel %i: %s", this.Channel, this.EEG.chanlocs(this.Channel).labels);
            if size(this.EEG.data, 3) > 1
                titleStr = sprintf('%s   (Trial %i)', titleStr, this.CurrentTrial);
            end
            title(ax, titleStr);

            xlim(ax, [0, floor(this.EEG.srate / 2)]);
            top = max(spectrum, [], "omitnan");
            if isfinite(top) && top > 0
                ylim(ax, [0, top]);
            end
        end

        function onKey(this, event)
        %ONKEY  Up/down arrows step the channel; left/right step the trial
        %   (multi-trial data only). Public (not a private helper): dispatched
        %   by Alakazam.dispatchKey for whichever tab is currently selected --
        %   see the constructor comment.
            switch lower(event.Key)
                case "uparrow"
                    this.Channel = max(1, this.Channel - 1);
                case "downarrow"
                    this.Channel = min(size(this.EEG.data, 1), this.Channel + 1);
                case "leftarrow"
                    this.CurrentTrial = max(1, this.CurrentTrial - 1);
                case "rightarrow"
                    this.CurrentTrial = min(size(this.EEG.data, 3), this.CurrentTrial + 1);
                otherwise
                    return;
            end
            this.redraw();
        end

        function notifyActivated(this)
        %NOTIFYACTIVATED  Call ActivatedFcn, if set, guarding the usual
        %   empty-function_handle case.
            if ~isempty(this.ActivatedFcn)
                this.ActivatedFcn();
            end
        end
    end

    methods (Access = private)
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
        %ADDBUTTONS  Zoom / pan (and optionally trial) push-buttons, in the
        %   bottom row (row 2) of this.Grid, built once in the constructor.
            labels    = {"+", "-", "^", "v", "<", ">"};
            callbacks = {@() this.zoomX(0.5), @() this.zoomX(2), @() this.zoomY(0.5), ...
                         @() this.zoomY(2), @() this.panX(-1), @() this.panX(1)};
            if includeTrial
                labels    = [labels, {"<<", ">>"}];
                callbacks = [callbacks, {@() this.trialStep(-1), @() this.trialStep(1)}];
            end
            n = numel(labels);
            btnGrid = uigridlayout(this.Grid, [1, n + 1], "Padding", [0 0 0 0], ...
                "ColumnWidth", [repmat({30}, 1, n), {'1x'}], "ColumnSpacing", 4);
            btnGrid.Layout.Row = 2;
            for i = 1:n
                b = uibutton(btnGrid, "Text", labels{i}, ...
                    "ButtonPushedFcn", @(~, ~) this.onButtonPushed(callbacks{i}));
                b.Layout.Column = i;
            end
        end

        function onButtonPushed(this, callback)
        %ONBUTTONPUSHED  A zoom/pan/trial button was pushed: mark this view
        %   activated (see ActivatedFcn) before running its callback.
            this.notifyActivated();
            callback();
        end

        function zoomX(this, factor)
        %ZOOMX  Scale the x range about its left edge (factor < 1 zooms in).
            span = xlim(this.Axes);
            newHigh = span(1) + (span(2) - span(1)) * factor;
            if factor > 1
                newHigh = min(newHigh, this.EEG.srate / 2);
            end
            xlim(this.Axes, [span(1), newHigh]);
        end

        function zoomY(this, factor)
        %ZOOMY  Scale the y range about its bottom edge.
            span = ylim(this.Axes);
            ylim(this.Axes, [span(1), span(1) + (span(2) - span(1)) * factor]);
        end

        function panX(this, direction)
        %PANX  Shift the x range by a tenth of its width, clamped to [0, fs/2].
            span = xlim(this.Axes);
            shifted = span + direction * (span(2) - span(1)) / 10;
            if shifted(1) < 0
                shifted = shifted - shifted(1);
            end
            if shifted(2) > this.EEG.srate / 2
                shifted = shifted - (shifted(2) - this.EEG.srate / 2);
            end
            xlim(this.Axes, shifted);
        end

        function trialStep(this, delta)
        %TRIALSTEP  Move to the previous / next trial and redraw.
            nseg = size(this.EEG.data, 3);
            this.CurrentTrial = min(nseg, max(1, this.CurrentTrial + delta));
            this.redraw();
        end
    end
end
