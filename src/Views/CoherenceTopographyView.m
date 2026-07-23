classdef CoherenceTopographyView < handle
%COHERENCETOPOGRAPHYVIEW  Grid of per-bin scalp coherence topographies.
%
%   Draws one head-map tile per bin (up to 3 per row, the tiling convention
%   ScalpDistributionView/TimeFrequencyView use) of every scalp channel's
%   magnitude-squared coherence to the reference, at the frequency
%   CoherenceTopography detected (or was told to use) for that bin. Each tile
%   is titled with its bin label and that frequency. Unlike ScalpDistribution
%   there is no time scrubbing: a coherence topography is one map per bin.
%
%   Uses TransTools.DrawScalpMap for the head/interpolation, then overrides its
%   (signed, diverging) colour scale with a sequential 0..max map, since
%   coherence is a non-negative [0,1] quantity. One shared colorbar.
%
%   See also ALAKAZAMPLOTTER, COHERENCETOPOGRAPHY, TRANSTOOLS.DRAWSCALPMAP,
%   SCALPDISTRIBUTIONVIEW.

    properties
        ActivatedFcn = function_handle.empty
    end

    properties (SetAccess = private)
        Figure
        EEG
        Grid
        Axes            % 1 x nBins uiaxes
    end

    methods
        function this = CoherenceTopographyView(fig, eeg)
            this.Figure = fig;
            this.EEG    = eeg;

            nBins  = size(eeg.CohTopoValues, 2);
            labels = eeg.CohTopoBinLabels;

            nCols = min(3, max(1, nBins));
            nRows = ceil(nBins / nCols);

            % One extra, narrow trailing column for the shared colorbar.
            this.Grid = uigridlayout(fig, [nRows, nCols + 1], ...
                'ColumnWidth', [repmat({'1x'}, 1, nCols), {60}], ...
                'RowHeight', repmat({'1x'}, 1, nRows), 'Padding', [4 4 4 4]);

            this.Axes = gobjects(1, nBins);
            for b = 1:nBins
                ax = uiaxes(this.Grid);
                ax.Layout.Row    = floor((b - 1) / nCols) + 1;
                ax.Layout.Column = mod(b - 1, nCols) + 1;
                ax.ButtonDownFcn = @(~, ~) this.notifyActivated();
                this.Axes(b) = ax;
                this.drawTile(ax, b, char(string(labels{b})));
            end

            this.addColorbar(nRows, nCols);
        end

        function notifyActivated(this)
            if ~isempty(this.ActivatedFcn)
                this.ActivatedFcn();
            end
        end
    end

    methods (Access = private)
        function drawTile(this, ax, b, label)
        %DRAWTILE  One bin's coherence head-map.
            eeg    = this.EEG;
            values = eeg.CohTopoValues(eeg.CohTopoDrawn, b);
            lim    = eeg.CohTopoLimit;
            try
                TransTools.DrawScalpMap(ax, values, eeg.CohTopoChanlocs, lim);
                % Coherence is non-negative: replace DrawScalpMap's symmetric
                % diverging scale with a sequential 0..max one.
                colormap(ax, parula);
                ax.CLim = [0, lim];
            catch err
                cla(ax); axis(ax, 'off');
                title(ax, sprintf('%s (no map: %s)', label, err.message));
                return;
            end
            f = eeg.CohTopoFreqs(b);
            if isfinite(f)
                title(ax, sprintf('%s  (%.1f Hz)', label, f));
            else
                title(ax, label);
            end
        end

        function addColorbar(this, nRows, nCols)
        %ADDCOLORBAR  One shared 0..max colorbar in the reserved last column.
            cax = uiaxes(this.Grid);
            cax.Layout.Column = nCols + 1;
            if nRows > 1
                cax.Layout.Row = [1, nRows];
            else
                cax.Layout.Row = 1;
            end
            cax.Visible = 'off';
            colormap(cax, parula);
            cax.CLim = [0, this.EEG.CohTopoLimit];
            cb = colorbar(cax);
            cb.Label.String = sprintf('Coherence to %s', this.EEG.CohTopoRef);
        end
    end
end
