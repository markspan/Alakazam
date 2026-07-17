classdef SpectralMeasureView < handle
%SPECTRALMEASUREVIEW  Keyboard-driven view of a SpectralMeasure result.
%
%   Draws one channel's evoked amplitude spectrum at a time (EEG.spectrum /
%   EEG.specFreqs, computed by SpectralMeasure), with a dashed marker at each
%   named frequency and its measured SNR annotated. Up/down arrows step the
%   channel; left/right step the bin (for multi-bin data) -- the same
%   interaction model FourierView/EpochView/AverageView use.
%
%   See also ALAKAZAMPLOTTER, FOURIERVIEW, SPECTRALMEASURE.

    properties
        ActivatedFcn = function_handle.empty
    end

    properties (SetAccess = private)
        Figure
        EEG
        Grid
        Axes
        Channel = 1
        CurrentBin = 1
    end

    methods
        function this = SpectralMeasureView(fig, eeg)
            this.Figure = fig;
            this.EEG    = eeg;
            this.Grid = uigridlayout(fig, [2 1], "RowHeight", {'1x', 32}, ...
                "Padding", [2 2 2 2], "RowSpacing", 2);
            this.Axes = uiaxes(this.Grid);
            this.Axes.Layout.Row = 1;
            this.Axes.ButtonDownFcn = @(~, ~) this.notifyActivated();
            this.addButtons(size(eeg.spectrum, 3) > 1);
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
            if size(this.EEG.spectrum, 3) > 1
                titleStr = sprintf('%s   (Bin: %s)', titleStr, binLabel(this.EEG, this.CurrentBin));
            end
            title(ax, titleStr);
            xlabel(ax, "Frequency (Hz)");
            ylabel(ax, "Evoked amplitude");
            xlim(ax, [0, floor(this.EEG.srate / 2)]);
            ylim(ax, [0, top]);
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

        function notifyActivated(this)
            if ~isempty(this.ActivatedFcn)
                this.ActivatedFcn();
            end
        end
    end

    methods (Access = private)
        function addButtons(this, includeBin)
        %ADDBUTTONS  Zoom / pan (and optionally bin-step) push-buttons.
            labels    = {"+", "-", "^", "v", "<", ">"};
            callbacks = {@() this.zoomX(0.5), @() this.zoomX(2), @() this.zoomY(0.5), ...
                         @() this.zoomY(2), @() this.panX(-1), @() this.panX(1)};
            if includeBin
                labels    = [labels, {"<<", ">>"}];
                callbacks = [callbacks, {@() this.binStep(-1), @() this.binStep(1)}];
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
            this.notifyActivated();
            callback();
        end

        function zoomX(this, factor)
            span = xlim(this.Axes);
            newHigh = span(1) + (span(2) - span(1)) * factor;
            if factor > 1; newHigh = min(newHigh, this.EEG.srate / 2); end
            xlim(this.Axes, [span(1), newHigh]);
        end

        function zoomY(this, factor)
            span = ylim(this.Axes);
            ylim(this.Axes, [span(1), span(1) + (span(2) - span(1)) * factor]);
        end

        function panX(this, direction)
            span = xlim(this.Axes);
            shifted = span + direction * (span(2) - span(1)) / 10;
            if shifted(1) < 0; shifted = shifted - shifted(1); end
            if shifted(2) > this.EEG.srate / 2; shifted = shifted - (shifted(2) - this.EEG.srate / 2); end
            xlim(this.Axes, shifted);
        end

        function binStep(this, delta)
            nBins = size(this.EEG.spectrum, 3);
            this.CurrentBin = min(nBins, max(1, this.CurrentBin + delta));
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
