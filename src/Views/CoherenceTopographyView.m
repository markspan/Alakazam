classdef CoherenceTopographyView < AlakazamView
%COHERENCETOPOGRAPHYVIEW  One scalp coherence topography, with a bin
%   dropdown when there is more than one.
%
%   Draws one head-map, of every scalp channel's magnitude-squared
%   coherence to the reference, at the frequency CoherenceTopography
%   detected (or was told to use) for the selected bin -- the title shows
%   that bin's label and frequency. A "Bin" dropdown appears when there is
%   more than one bin, matching ScalpDistributionView's/Brain3DView's own
%   single-plot-plus-bin-dropdown interface (this used to draw a whole grid
%   of per-bin tiles at once; one topography plus a dropdown reads far more
%   clearly once there are more than a couple of bins, and keeps every
%   view in this family consistent with the others). Unlike
%   ScalpDistributionView there is no time scrubbing: a coherence
%   topography is one map per bin.
%
%   Uses TransTools.DrawScalpMap for the head/interpolation, then overrides
%   its (signed, diverging) colour scale with a sequential 0..max map,
%   since coherence is a non-negative [0,1] quantity. One shared colorbar.
%
%   See also ALAKAZAMPLOTTER, COHERENCETOPOGRAPHY, TRANSTOOLS.DRAWSCALPMAP,
%   SCALPDISTRIBUTIONVIEW, BRAIN3DVIEW.

    properties
    end

    properties (SetAccess = private)
        Figure
        EEG
        Grid
        Axes            % the single head-map uiaxes
        BinLabels        % display label for each bin
        SelectedBin      % index of the bin currently drawn
        BinDropdown      % uidropdown, only built when numel(BinLabels) > 1
    end

    methods
        function this = CoherenceTopographyView(fig, eeg)
            this.Figure = fig;
            this.EEG    = eeg;

            nBins = size(eeg.CohTopoValues, 2);
            this.BinLabels = eeg.CohTopoBinLabels;
            this.SelectedBin = 1;

            hasDropdown = nBins > 1;
            dropdownRows = double(hasDropdown); % 0 or 1 extra row at the top

            this.Grid = uigridlayout(fig, [dropdownRows + 1, 2], ...
                "RowHeight", [repmat({26}, 1, dropdownRows), {'1x'}], ...
                "ColumnWidth", {'1x', TransTools.ColorbarColumnWidth()}, "Padding", [4 4 4 4]);

            if hasDropdown
                this.BinDropdown = TransTools.BuildBinDropdown(this.Grid, 1, 1, ...
                    this.BinLabels, @(idx) this.onBinChanged(idx));
            end

            axRow = dropdownRows + 1;
            this.Axes = uiaxes(this.Grid);
            this.Axes.Layout.Row = axRow;
            this.Axes.Layout.Column = 1;
            this.Axes.ButtonDownFcn = @(~, ~) this.notifyActivated();
            axtoolbar(this.Axes, "default");

            this.redraw();

            % Built AFTER the first redraw() above -- see Brain3DView's own
            % constructor comment for why (a real reported regression when
            % this order was briefly swapped for cross-file consistency).
            TransTools.AddSharedColorbar(this.Grid, axRow, 2, parula, ...
                [0, this.EEG.CohTopoLimit], sprintf('Coherence to %s', this.EEG.CohTopoRef));
        end

    end

    methods (Access = private)
        function redraw(this)
        %REDRAW  Draw the currently selected bin's coherence head-map.
            eeg   = this.EEG;
            b     = this.SelectedBin;
            label = char(string(this.BinLabels{b}));
            ax    = this.Axes;
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

        function onBinChanged(this, binIdx)
        %ONBINCHANGED  BinDropdown ValueChangedFcn target.
            this.notifyActivated();
            this.SelectedBin = binIdx;
            this.redraw();
        end
    end
end
