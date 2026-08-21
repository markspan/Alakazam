classdef CoherenceView < handle
%COHERENCEVIEW  Per-bin time x frequency coherence heatmaps, one channel at a
%   time -- the coherence counterpart of TimeFrequencyView.
%
%   Draws every bin's precomputed EEG.coherence (channels x freqs x time x
%   bins, see TransTools.ComputeCoherenceMap, called from CoherenceMap.m) as
%   one imagesc tile per bin, up to 3 per row, with a shared sequential [0,1]
%   colour scale and one shared colorbar. Up/down arrow keys (and the mouse
%   wheel) step the shown channel; because every channel's coherence was
%   computed up front, stepping is pure re-slicing, not a recompute -- the
%   same design TimeFrequencyView uses. The reference channel's own tile is
%   blank (its self-coherence is not computed).
%
%   See also ALAKAZAMPLOTTER, COHERENCEMAP, TIMEFREQUENCYVIEW.

    properties
        ActivatedFcn = function_handle.empty
    end

    properties (SetAccess = private)
        Figure
        EEG             % dataset carrying .coherence / .cohFreqs / .cohTimes / .cohRef
        Grid
        ChannelLabel
        Axes
        Images
        BinIndices      % original coherence 4th-dim index for each drawn tile
        Channel = 1
    end

    methods
        function this = CoherenceView(fig, eeg)
            this.Figure = fig;
            this.EEG    = eeg;

            % Only draw bins that actually have a coherence map. Combination
            % (difference) bins have no trials of their own, so
            % ComputeCoherenceMap leaves their whole slice NaN -- drawing them
            % gave blank tiles. Keep each drawn tile's original bin index for
            % slicing and labelling (see BinIndices).
            nBinsTotal = size(eeg.coherence, 4);
            this.BinIndices = find(arrayfun( ...
                @(b) any(~isnan(reshape(eeg.coherence(:, :, :, b), [], 1))), 1:nBinsTotal));
            if isempty(this.BinIndices)
                this.BinIndices = 1:nBinsTotal; % never show a completely empty view
            end
            nBins = numel(this.BinIndices);
            nCols = min(3, nBins);
            nRows = ceil(nBins / nCols);

            this.Grid = uigridlayout(fig, [nRows + 1, nCols + 1], ...
                "RowHeight", [{22}, repmat({'1x'}, 1, nRows)], ...
                "ColumnWidth", [repmat({'1x'}, 1, nCols), {TransTools.ColorbarColumnWidth()}], "Padding", [4 4 4 4]);

            this.ChannelLabel = uilabel(this.Grid, "HorizontalAlignment", "center", "FontWeight", "bold");
            this.ChannelLabel.Layout.Row = 1;
            this.ChannelLabel.Layout.Column = [1, nCols + 1];

            cmap = parula(256);
            freqs = eeg.cohFreqs;
            times = eeg.cohTimes;

            this.Axes   = gobjects(1, nBins);
            this.Images = gobjects(1, nBins);
            for b = 1:nBins
                row = ceil(b / nCols);
                col = mod(b - 1, nCols) + 1;
                ax = uiaxes(this.Grid);
                ax.Layout.Row    = row + 1;
                ax.Layout.Column = col;
                colormap(ax, cmap);
                title(ax, eeg.bindesc(this.BinIndices(b)).label, "Interpreter", "none");
                xlabel(ax, "Time (ms)");
                if col == 1
                    ylabel(ax, "Frequency (Hz)");
                else
                    ax.YAxis.Visible = "off";
                end
                ax.ButtonDownFcn = @(~, ~) this.notifyActivated();
                img = imagesc(ax, times, freqs, zeros(numel(freqs), numel(times)));
                img.ButtonDownFcn = @(~, ~) this.notifyActivated();
                set(ax, "YDir", "normal");
                xlim(ax, [times(1), times(end)]);
                ylim(ax, [freqs(1), freqs(end)]);
                this.Axes(b)   = ax;
                this.Images(b) = img;
            end

            % Shared 0..max colorbar (coherence is bounded [0,1]; scaled to the
            % data's own max so low-coherence structure still shows contrast).
            if nRows > 1
                cbRow = [2, nRows + 1];
            else
                cbRow = 2;
            end
            TransTools.AddSharedColorbar(this.Grid, cbRow, nCols + 1, cmap, [0, this.climMax()], "Coherence");

            this.redraw();
            for b = 1:nBins
                axtoolbar(this.Axes(b), "default");
            end
        end

        function redraw(this)
        %REDRAW  Re-slice EEG.coherence at the current channel and redraw every
        %   bin's tile (instant -- coherence was fully computed up front).
            ch = this.Channel;
            cmax = this.climMax();
            for b = 1:numel(this.Axes)
                this.Images(b).CData = squeeze(this.EEG.coherence(ch, :, :, this.BinIndices(b)));
                this.Axes(b).CLim = [0, cmax];
            end
            ref = '';
            if isfield(this.EEG, 'cohRef') && ~isempty(this.EEG.cohRef)
                ref = sprintf('  vs %s', char(string(this.EEG.cohRef)));
            end
            this.ChannelLabel.Text = sprintf('Channel: %s (%d/%d)%s', ...
                this.EEG.chanlocs(ch).labels, ch, this.EEG.nbchan, ref);
        end

        function onKey(this, event)
        %ONKEY  Up/down arrows step the shown channel.
            switch lower(event.Key)
                case "uparrow"
                    this.Channel = max(1, this.Channel - 1);
                case "downarrow"
                    this.Channel = min(this.EEG.nbchan, this.Channel + 1);
                otherwise
                    return;
            end
            this.redraw();
        end

        function onWheel(this, callbackData)
        %ONWHEEL  Mouse wheel steps the shown channel (same direction as the
        %   arrow keys), mirroring TimeFrequencyView's onWheel.
            if callbackData.VerticalScrollCount > 0
                this.Channel = min(this.EEG.nbchan, this.Channel + 1);
            else
                this.Channel = max(1, this.Channel - 1);
            end
            this.redraw();
            this.notifyActivated();
        end

        function notifyActivated(this)
            if ~isempty(this.ActivatedFcn)
                this.ActivatedFcn();
            end
        end
    end

    methods (Access = private)
        function m = climMax(this)
        %CLIMMAX  Upper colour limit: the largest coherence in the whole
        %   tensor, floored so an all-low-coherence dataset is not a flat scale.
            m = max(this.EEG.coherence(:), [], "omitnan");
            if ~isfinite(m) || m <= 0
                m = 1;
            end
            m = max(m, 0.2);
        end
    end
end
