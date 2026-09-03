classdef TimeFrequencyView < AlakazamView
%TIMEFREQUENCYVIEW  Grid of per-bin ERSP heatmaps, one channel at a time.
%
%   Draws every bin's precomputed EEG.ersp (channels x freqs x time x
%   bins, see TransTools.ComputeErsp, called from TimeFrequency.m) as one
%   imagesc tile per bin, up to 3 per row wrapping to a new row (the same
%   tiling convention AverageView's tick strip and ScalpDistribution's
%   subplot grid both use), with a single shared, symmetric diverging
%   colour scale across every bin (so bins stay visually comparable) and
%   one shared colorbar. Up/down arrow keys step the shown channel;
%   because every channel's ERSP was already computed up front by the
%   transformation, stepping is pure re-slicing of the precomputed array,
%   not a live recompute -- the same "compute once, step is instant"
%   design EpochView/AverageView/FourierView already use.
%
%   Style follows the project standard.
%
%   See also ALAKAZAMPLOTTER, TIMEFREQUENCY, AVERAGEVIEW, FOURIERVIEW.

    properties
    end

    properties (SetAccess = private)
        Figure          % owning uitab
        EEG             % dataset carrying .ersp (nChan x nFreqs x nTime x nBins) and .freqs
        Grid            % (nRows+1) x nCols uigridlayout: row 1 the channel label, rest tiles
        ChannelLabel    % spanning label across row 1
        Axes            % 1 x nBins array of uiaxes, one per bin
        Images          % 1 x nBins array of Image objects (imagesc handles), one per bin
        Channel = 1     % channel currently shown
    end

    methods
        function this = TimeFrequencyView(fig, eeg)
        %TIMEFREQUENCYVIEW  Build the ERSP tile grid for EEG in FIG.
            this.Figure = fig;
            this.EEG    = eeg;

            nBins = size(eeg.ersp, 4);
            nCols = min(3, nBins);
            nRows = ceil(nBins / nCols);

            % Key handling is wired by the shared Alakazam-level dispatcher
            % (Alakazam.dispatchKey), not a per-view fig.KeyPressFcn -- see
            % FourierView's constructor comment for why. One extra,
            % narrow trailing column reserved for the shared colorbar --
            % see the dedicated hidden axes built below for why it needs
            % its own column rather than sharing a tile's.
            this.Grid = uigridlayout(fig, [nRows + 1, nCols + 1], ...
                "RowHeight", [{22}, repmat({'1x'}, 1, nRows)], ...
                "ColumnWidth", [repmat({'1x'}, 1, nCols), {TransTools.ColorbarColumnWidth()}], "Padding", [4 4 4 4]);

            this.ChannelLabel = uilabel(this.Grid, "HorizontalAlignment", "center", "FontWeight", "bold");
            this.ChannelLabel.Layout.Row = 1;
            this.ChannelLabel.Layout.Column = [1, nCols + 1]; % always >1 columns wide, no [1 1] risk here

            cmap = TransTools.DivergingColormap();

            this.Axes   = gobjects(1, nBins);
            this.Images = gobjects(1, nBins);
            for b = 1:nBins
                row = ceil(b / nCols);
                col = mod(b - 1, nCols) + 1;
                ax = uiaxes(this.Grid);
                ax.Layout.Row    = row + 1;
                ax.Layout.Column = col;
                colormap(ax, cmap);
                title(ax, eeg.bindesc(b).label, "Interpreter", "none");
                xlabel(ax, "Time (ms)");
                if col == 1
                    % Every tile shares the same frequency range (one
                    % shared colour scale, one shared colorbar already),
                    % so repeating the y-axis ticks/label on every column
                    % is pure clutter -- only the leftmost tile in each
                    % row keeps it.
                    ylabel(ax, "Frequency (Hz)");
                else
                    ax.YAxis.Visible = "off";
                end
                ax.ButtonDownFcn = @(~, ~) this.notifyActivated();
                img = imagesc(ax, eeg.times, eeg.freqs, zeros(numel(eeg.freqs), numel(eeg.times)));
                img.ButtonDownFcn = @(~, ~) this.notifyActivated();
                set(ax, "YDir", "normal");
                % imagesc does not itself constrain XLim/YLim to the data
                % extent -- axes default to "auto" limits, which round out
                % to the next "nice" tick value (e.g. times spanning -200
                % to 800 ms showing an axis from -400 to 800), so the axes
                % have to be pinned to the real data range explicitly.
                xlim(ax, [eeg.times(1), eeg.times(end)]);
                ylim(ax, [eeg.freqs(1), eeg.freqs(end)]);
                this.Axes(b)   = ax;
                this.Images(b) = img;
            end

            % One shared colorbar: every tile carries the same CLim (see
            % redraw's own climAbs, computed over the WHOLE precomputed
            % ersp tensor, hence identical regardless of the shown
            % channel) -- see TransTools.AddSharedColorbar for why it is a
            % dedicated hidden axes rather than attached to a real tile.
            climAbs = max(abs(eeg.ersp(:)), [], "omitnan");
            if ~isfinite(climAbs) || climAbs == 0
                climAbs = 1;
            end
            if nRows > 1
                cbRow = [2, nRows + 1];
            else
                cbRow = 2;
            end
            TransTools.AddSharedColorbar(this.Grid, cbRow, nCols + 1, cmap, ...
                [-climAbs, climAbs], "Power vs. baseline (dB)");

            this.redraw();
            for b = 1:nBins
                axtoolbar(this.Axes(b), "default");
            end
        end

        function redraw(this)
        %REDRAW  Re-slice EEG.ersp at the current channel and redraw every
        %   bin's tile -- an instant operation, since ERSP power was
        %   already fully computed by TimeFrequency.m.
            ch = this.Channel;
            ersp = this.EEG.ersp;
            climAbs = max(abs(ersp(:)), [], "omitnan");
            if ~isfinite(climAbs) || climAbs == 0
                climAbs = 1;
            end
            for b = 1:numel(this.Axes)
                this.Images(b).CData = squeeze(ersp(ch, :, :, b));
                this.Axes(b).CLim = [-climAbs, climAbs];
            end
            this.ChannelLabel.Text = sprintf('Channel: %s (%d/%d)', ...
                this.EEG.chanlocs(ch).labels, ch, this.EEG.nbchan);
        end

        function onKey(this, event)
        %ONKEY  Up/down arrows step the shown channel. Public (not a
        %   private helper): dispatched by Alakazam.dispatchKey for
        %   whichever tab is currently selected -- see the constructor
        %   comment.
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
        %ONWHEEL  Scroll the mouse wheel to step the shown channel -- the
        %   same direction convention as the up/down arrow keys (positive
        %   VerticalScrollCount, i.e. scrolling down, steps forward
        %   through channels, matching downarrow). Public: dispatched
        %   centrally by Alakazam.dispatchWheel for whichever tab is
        %   currently active, mirroring SignalView's/EpochView's own
        %   onWheel contract.
            if callbackData.VerticalScrollCount > 0
                this.Channel = min(this.EEG.nbchan, this.Channel + 1);
            else
                this.Channel = max(1, this.Channel - 1);
            end
            this.redraw();
            this.notifyActivated();
        end

    end
end
