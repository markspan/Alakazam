classdef SpectralMeasureView < AlakazamView
%SPECTRALMEASUREVIEW  Keyboard-driven view of a SpectralMeasure result.
%
%   Draws one channel's evoked amplitude spectrum at a time (EEG.spectrum /
%   EEG.specFreqs, computed by SpectralMeasure), with a dashed marker at each
%   named frequency and its measured SNR annotated. Up/down arrows step the
%   channel; left/right step the bin (for multi-bin data) -- the same
%   interaction model FourierView/EpochView/AverageView use. Every step also
%   has a visible, clickable button (channel and bin alike, not just
%   keyboard/wheel), plus x/y zoom sliders (a zoom level, once set, survives
%   a channel/bin change instead of resetting), pan and mouse-wheel channel
%   stepping: see ZoomPanButtons/onWheel, shared with FourierView.
%
%   See also ALAKAZAMPLOTTER, FOURIERVIEW, SPECTRALMEASURE, ZOOMPANBUTTONS.

    properties
    end

    properties (SetAccess = private)
        Figure
        EEG
        Grid
        Axes
        Buttons     % ZoomPanButtons, the zoom/pan/bin-step row + sliders
        Channel = 1
        CurrentBin = 1
    end

    methods
        function this = SpectralMeasureView(fig, eeg)
            this.Figure = fig;
            this.EEG    = eeg;
            this.Grid = uigridlayout(fig, [4 1], "RowHeight", {'1x', 30, 24, 24}, ...
                "Padding", [2 2 2 2], "RowSpacing", 2);
            this.Axes = uiaxes(this.Grid);
            this.Axes.Layout.Row = 1;
            this.Axes.ButtonDownFcn = @(~, ~) this.notifyActivated();
            stepFcn = [];
            if size(eeg.spectrum, 3) > 1
                stepFcn = @(delta) this.binStep(delta);
            end
            channelStepFcn = [];
            if size(eeg.spectrum, 1) > 1
                channelStepFcn = @(delta) this.channelStep(delta);
            end
            this.Buttons = ZoomPanButtons(this.Grid, [2 3 4], this.Axes, eeg.srate / 2, ...
                @() this.notifyActivated(), stepFcn, channelStepFcn, 'Bin');
            this.redraw();
            axtoolbar(this.Axes, "default");
        end

        function redraw(this)
        %REDRAW  Draw the current channel/bin spectrum with frequency markers.
            ax = this.Axes;
            delete(allchild(ax));
            freqs = reshape(this.EEG.specFreqs, 1, []);
            spec  = reshape(this.EEG.spectrum(this.Channel, :, this.CurrentBin), 1, []);

            hold(ax, "on");
            plot(ax, freqs, spec, "Color", "k", "LineWidth", 1);

            top = max(spec, [], "omitnan");
            if ~isfinite(top) || top <= 0; top = 1; end
            curLabel = this.EEG.chanlocs(this.Channel).labels;
            for w = 1:numel(this.EEG.spectralMeasures)
                m = this.EEG.spectralMeasures{w};
                fmark = abs(m.freq);
                xline(ax, fmark, "--", "Color", [0.25 0.42 0.63], ...
                    "LineWidth", 1, "Alpha", 0.9);
                c = find(strcmpi(m.channels, curLabel), 1);
                if isempty(c)
                    txt = char(string(m.label));
                else
                    txt = sprintf('%s\\newlineSNR %.2g', char(string(m.label)), m.snr(c, this.CurrentBin));
                end
                text(ax, fmark, top, ['  ' txt], "Color", [0.25 0.42 0.63], ...
                    "FontSize", 8, "FontWeight", "bold", "VerticalAlignment", "top", ...
                    "HorizontalAlignment", "left", "Clipping", "on", "Interpreter", "tex");
            end
            hold(ax, "off");

            titleStr = sprintf("Channel %i: %s", this.Channel, curLabel);
            nbin = size(this.EEG.spectrum, 3);
            if nbin > 1
                % "i of N" alongside the label, not just the label alone --
                % see FourierView's own redraw() for why (unambiguous even
                % when the label text does not obviously change).
                titleStr = sprintf('%s   (Bin %i of %i: %s)', titleStr, ...
                    this.CurrentBin, nbin, binLabel(this.EEG, this.CurrentBin));
            end
            title(ax, titleStr);
            xlabel(ax, "Frequency (Hz)");
            ylabel(ax, "Evoked amplitude");

            % x-limits are owned by this.Buttons (persists zoom/pan across a
            % channel/bin change); y-limits go through applyYZoom so the
            % y-zoom slider's level, not just the absolute range, survives
            % too -- see ZoomPanButtons' own header comment.
            this.Buttons.applyYZoom(top);
        end

        function onKey(this, event)
        %ONKEY  Up/down step the channel; left/right step the bin.
            switch lower(event.Key)
                case "uparrow";    this.Channel = max(1, this.Channel - 1);
                case "downarrow";  this.Channel = min(size(this.EEG.spectrum, 1), this.Channel + 1);
                case "leftarrow";  this.CurrentBin = max(1, this.CurrentBin - 1);
                case "rightarrow"; this.CurrentBin = min(size(this.EEG.spectrum, 3), this.CurrentBin + 1);
                otherwise;         return;
            end
            this.redraw();
        end

        function onWheel(this, callbackData)
        %ONWHEEL  Mouse wheel steps the shown channel (same direction as the
        %   arrow keys), dispatched centrally by Alakazam.dispatchWheel.
            if callbackData.VerticalScrollCount > 0
                this.Channel = min(size(this.EEG.spectrum, 1), this.Channel + 1);
            else
                this.Channel = max(1, this.Channel - 1);
            end
            this.redraw();
            this.notifyActivated();
        end

    end

    methods (Access = private)
        function binStep(this, delta)
            nBins = size(this.EEG.spectrum, 3);
            this.CurrentBin = min(nBins, max(1, this.CurrentBin + delta));
            this.redraw();
        end

        function channelStep(this, delta)
        %CHANNELSTEP  Button-row equivalent of the up/down arrow keys (see
        %   onKey), for the "C^"/"Cv" pair ZoomPanButtons builds when given
        %   a non-empty channelStepFcn.
            nchan = size(this.EEG.spectrum, 1);
            this.Channel = min(nchan, max(1, this.Channel - delta));
            this.redraw();
        end
    end
end

function label = binLabel(EEG, b)
    if isfield(EEG, 'bindesc') && numel(EEG.bindesc) >= b && ~isempty(EEG.bindesc(b).label)
        label = char(string(EEG.bindesc(b).label));
    else
        label = num2str(b);
    end
end
