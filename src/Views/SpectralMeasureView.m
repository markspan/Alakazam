classdef SpectralMeasureView < AlakazamView
%SPECTRALMEASUREVIEW  Keyboard-driven view of a SpectralMeasure result.
%
%   Draws one channel's evoked amplitude spectrum at a time (EEG.spectrum /
%   EEG.specFreqs, computed by SpectralMeasure), with a dashed marker at each
%   named frequency and its measured SNR annotated.
%
%   CHANNEL AND BIN ARE DROPDOWNS ABOVE THE PLOT, as in FourierView,
%   EpochView and TimeFrequencyView, built by the same
%   TransTools.BuildChannelDropdown and BuildBinDropdown, instead of the row
%   of step and pan buttons below the plot it used to have. The bin dropdown
%   is left out when there is one bin. Up/down arrows and the mouse wheel
%   step the channel, left/right the bin, and a focus shared from another
%   view sets both; the dropdowns follow all of them.
%
%   X/y zoom are the sliders below the plot (ZoomSliders, shared with
%   FourierView): a zoom level, once set, survives a channel or bin change
%   instead of resetting, and the axes toolbar pans.
%
%   See also ALAKAZAMPLOTTER, FOURIERVIEW, SPECTRALMEASURE, ZOOMSLIDERS.

    properties
    end

    properties (SetAccess = private)
        Figure
        EEG
        Grid            % 4x1 uigridlayout: dropdowns | axes | x-zoom | y-zoom
        ChannelDropdown % "Channel:" uidropdown (TransTools.BuildChannelDropdown), row 1
        BinDropdown     % "Bin:" uidropdown (TransTools.BuildBinDropdown), row 1;
                        % empty when there is one bin
        Axes
        Zoom            % ZoomSliders, the x/y zoom sliders below the plot
        Channel = 1
        CurrentBin = 1
    end

    methods
        function this = SpectralMeasureView(fig, eeg)
            this.Figure = fig;
            this.EEG    = eeg;
            this.Grid = uigridlayout(fig, [4 1], "RowHeight", {22, '1x', 24, 24}, ...
                "Padding", [2 2 2 2], "RowSpacing", 2);

            % Row 1: the channel and, with more than one, the bin, in
            % EpochView's proportions.
            controls = uigridlayout(this.Grid, [1 3], "ColumnWidth", {'1x', '1x', '1x'}, ...
                "Padding", [0 0 0 0], "ColumnSpacing", 12);
            controls.Layout.Row = 1;
            this.ChannelDropdown = TransTools.BuildChannelDropdown(controls, 1, 1, ...
                {eeg.chanlocs.labels}, @(idx) this.onChannelSelected(idx));
            nBins = size(eeg.spectrum, 3);
            if nBins > 1
                this.BinDropdown = TransTools.BuildBinDropdown(controls, 1, 2, ...
                    arrayfun(@(b) binLabel(eeg, b), 1:nBins, 'UniformOutput', false), ...
                    @(idx) this.onBinSelected(idx));
            end

            this.Axes = uiaxes(this.Grid);
            this.Axes.Layout.Row = 2;
            this.Axes.ButtonDownFcn = @(~, ~) this.notifyActivated();
            this.Zoom = ZoomSliders(this.Grid, [3 4], this.Axes, eeg.srate / 2, ...
                @() this.notifyActivated());
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
            plot(ax, freqs, spec, "Color", "k", "LineWidth", 1, "Tag", "SpectrumLine");

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
                % see FourierView's own titleText for why (unambiguous even
                % when the label text does not obviously change).
                titleStr = sprintf('%s   (Bin %i of %i: %s)', titleStr, ...
                    this.CurrentBin, nbin, binLabel(this.EEG, this.CurrentBin));
            end
            title(ax, titleStr);
            xlabel(ax, "Frequency (Hz)");
            ylabel(ax, "Evoked amplitude");

            % x-limits are owned by this.Zoom (persists zoom across a
            % channel/bin change); y-limits go through applyYZoom so the
            % y-zoom slider's level, not just the absolute range, survives
            % too -- see ZoomSliders' own header comment.
            this.Zoom.applyYZoom(top);

            % The dropdowns show what is drawn, however it was chosen: a key,
            % the wheel, a focus shared from another view, or the dropdown
            % itself. Setting Value does not fire ValueChangedFcn.
            this.ChannelDropdown.Value = this.Channel;
            if ~isempty(this.BinDropdown)
                this.BinDropdown.Value = this.CurrentBin;
            end
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
        function onChannelSelected(this, idx)
        %ONCHANNELSELECTED  The channel dropdown's ValueChangedFcn: jump
        %   straight to the picked electrode, the same effect as stepping
        %   there one channel at a time with the up/down keys (onKey).
            this.notifyActivated();
            this.Channel = idx;
            this.redraw();
        end

        function onBinSelected(this, idx)
        %ONBINSELECTED  The bin dropdown's ValueChangedFcn: show the picked
        %   bin, as the left/right keys step to it (onKey).
            this.notifyActivated();
            this.CurrentBin = idx;
            this.redraw();
        end
    end

    methods
        function focus = currentFocus(this)
        %CURRENTFOCUS  The channel and the bin this view is showing, by
        %   label. See ViewFocus for why the label rather than the index.
            focus = struct();
            if isempty(this.EEG)
                return;
            end
            if isfield(this.EEG, 'chanlocs') && this.Channel >= 1 && ...
                    this.Channel <= numel(this.EEG.chanlocs)
                focus.Channel = char(string(this.EEG.chanlocs(this.Channel).labels));
            end
            if isfield(this.EEG, 'bindesc') && numel(this.EEG.bindesc) >= this.CurrentBin
                focus.Bin = binLabel(this.EEG, this.CurrentBin);
            end
        end

        function applyFocus(this, focus)
        %APPLYFOCUS  Show FOCUS.Channel and FOCUS.Bin where this dataset has
        %   them. A label it does not carry leaves that part of the view on
        %   its own default, the ordinary case when moving between datasets
        %   with different channels or conditions. The bin used to be left
        %   out, so stepping to the next node reset the view to the first
        %   condition while the other views kept theirs.
            if ~isstruct(focus) || isempty(this.EEG)
                return;
            end
            changed = false;
            if isfield(focus, 'Channel') && isfield(this.EEG, 'chanlocs') && ...
                    ~isempty(this.EEG.chanlocs)
                idx = ViewFocus.indexOfLabel({this.EEG.chanlocs.labels}, focus.Channel);
                if ~isempty(idx) && idx ~= this.Channel
                    this.Channel = idx;
                    changed = true;
                end
            end
            if isfield(focus, 'Bin') && isfield(this.EEG, 'bindesc') && ...
                    ~isempty(this.EEG.bindesc)
                labels = arrayfun(@(b) binLabel(this.EEG, b), 1:numel(this.EEG.bindesc), ...
                    'UniformOutput', false);
                k = ViewFocus.indexOfLabel(labels, focus.Bin);
                if ~isempty(k) && k <= size(this.EEG.spectrum, 3) && k ~= this.CurrentBin
                    this.CurrentBin = k;
                    changed = true;
                end
            end
            if changed
                this.redraw();
            end
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
