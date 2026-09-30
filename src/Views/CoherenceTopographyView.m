classdef CoherenceTopographyView < AlakazamView
%COHERENCETOPOGRAPHYVIEW  Every bin's scalp coherence topography in one
%   plot, on one colour scale, with the bins ticked in a side column.
%
%   Each map shows every scalp channel's magnitude-squared coherence to the
%   reference at the frequency CoherenceTopography detected (or was told to
%   use) for that bin; its title gives the bin's label and frequency. The
%   side column holds a tickbox per bin, as the ERP view does for its lines:
%   the ticked bins are drawn side by side, up to three to a row, and all of
%   them start ticked.
%
%   WHY SIDE BY SIDE, not one at a time. The view used to show one bin
%   behind a dropdown. The question a coherence topography answers is
%   comparative (does the 64 Hz condition focus where the 60 Hz one does, is
%   the SSVEP control's map different), and one map at a time made the
%   reader carry the last one in memory. Drawn together on one colour scale
%   (0 to the largest coherence of any bin), the maps compare as they stand,
%   which is how Dimigen et al. (2025, Figure 1C) show them. The tickboxes
%   keep a study with many conditions readable: untick what is not being
%   compared.
%
%   Uses TransTools.DrawScalpMap for the head and interpolation, then
%   replaces its signed, diverging colour scale with a sequential 0..max
%   one, since coherence is a non-negative quantity in [0, 1]. One shared
%   colorbar.
%
%   See also ALAKAZAMPLOTTER, COHERENCETOPOGRAPHY, TRANSTOOLS.DRAWSCALPMAP,
%   AVERAGEVIEW, SCALPDISTRIBUTIONVIEW.

    properties (Constant, Access = private)
        MaxColumns = 3      % maps per row
        SideWidthPx = 170   % the tickbox column
    end

    properties (SetAccess = private)
        Figure
        EEG
        Grid
        MapGrid          % nested grid holding one uiaxes per ticked bin
        CheckboxGrid     % the side column: one uicheckbox per bin
        Axes             % the drawn maps' uiaxes, in bin order
        BinLabels        % display label for each bin
        Shown            % logical, one per bin: ticked in the side column
    end

    methods
        function this = CoherenceTopographyView(fig, eeg)
            this.Figure = fig;
            this.EEG    = eeg;
            this.BinLabels = cellfun(@(l) char(string(l)), eeg.CohTopoBinLabels, 'UniformOutput', false);
            this.Shown = true(1, numel(this.BinLabels));

            this.Grid = uigridlayout(fig, [1, 3], ...
                "RowHeight", {'1x'}, ...
                "ColumnWidth", {'1x', TransTools.ColorbarColumnWidth(), this.SideWidthPx}, ...
                "Padding", [4 4 4 4]);
            this.MapGrid = uigridlayout(this.Grid, [1, 1], "Padding", [0 0 0 0]);
            this.MapGrid.Layout.Row = 1;
            this.MapGrid.Layout.Column = 1;
            this.CheckboxGrid = uigridlayout(this.Grid, [1, 1], "Padding", [4 0 0 0], "RowSpacing", 2);
            this.CheckboxGrid.Layout.Row = 1;
            this.CheckboxGrid.Layout.Column = 3;

            this.buildCheckboxes();
            this.redraw();

            % Built AFTER the first redraw() above -- see Brain3DView's own
            % constructor comment for why (a real reported regression when
            % this order was briefly swapped for cross-file consistency).
            TransTools.AddSharedColorbar(this.Grid, 1, 2, parula, [0, this.EEG.CohTopoLimit], ...
                sprintf('Coherence to %s (%s)', this.EEG.CohTopoRef, methodLabel(this.EEG)));
        end
    end

    methods (Access = private)
        function buildCheckboxes(this)
        %BUILDCHECKBOXES  A heading and one tickbox per bin, named with the
        %   frequency its map is drawn at.
            n = numel(this.BinLabels);
            this.CheckboxGrid.RowHeight = [{18}, repmat({22}, 1, n), {'1x'}];
            heading = uilabel(this.CheckboxGrid, "Text", "Bins", "FontWeight", "bold");
            heading.Layout.Row = 1;
            for b = 1:n
                cb = uicheckbox(this.CheckboxGrid, ...
                    "Text", this.binTitle(b), ...
                    "Tooltip", this.binTitle(b), ...
                    "Value", this.Shown(b), ...
                    "ValueChangedFcn", @(src, ~) this.onToggle(b, src.Value));
                cb.Layout.Row = b + 1;
            end
        end

        function redraw(this)
        %REDRAW  One head-map per ticked bin, laid out in rows of up to
        %   MaxColumns, all on the same 0..CohTopoLimit scale.
            delete(this.MapGrid.Children);
            this.Axes = gobjects(0);
            bins = find(this.Shown);
            if isempty(bins)
                this.MapGrid.RowHeight = {'1x'};
                this.MapGrid.ColumnWidth = {'1x'};
                note = uilabel(this.MapGrid, "Text", "Tick a bin to show its map.", ...
                    "HorizontalAlignment", "center");
                note.Layout.Row = 1;
                note.Layout.Column = 1;
                return;
            end
            nCols = min(this.MaxColumns, numel(bins));
            nRows = ceil(numel(bins) / nCols);
            this.MapGrid.RowHeight = repmat({'1x'}, 1, nRows);
            this.MapGrid.ColumnWidth = repmat({'1x'}, 1, nCols);
            for k = 1:numel(bins)
                ax = uiaxes(this.MapGrid);
                ax.Layout.Row = ceil(k / nCols);
                ax.Layout.Column = mod(k - 1, nCols) + 1;
                ax.ButtonDownFcn = @(~, ~) this.notifyActivated();
                axtoolbar(ax, "default");
                this.drawMap(ax, bins(k));
                this.Axes(end + 1) = ax;
            end
        end

        function drawMap(this, ax, b)
        %DRAWMAP  Bin B's coherence head-map into AX.
            eeg = this.EEG;
            lim = eeg.CohTopoLimit;
            try
                TransTools.DrawScalpMap(ax, eeg.CohTopoValues(eeg.CohTopoDrawn, b), eeg.CohTopoChanlocs, lim);
                % Coherence is non-negative: replace DrawScalpMap's symmetric
                % diverging scale with a sequential 0..max one.
                colormap(ax, parula);
                ax.CLim = [0, lim];
            catch err
                cla(ax);
                axis(ax, 'off');
                title(ax, sprintf('%s (no map: %s)', this.BinLabels{b}, err.message), 'Interpreter', 'none');
                return;
            end
            title(ax, this.binTitle(b), 'Interpreter', 'none');
        end

        function text = binTitle(this, b)
        %BINTITLE  "Label  (64.0 Hz)", or the label alone without a frequency.
            text = this.BinLabels{b};
            f = this.EEG.CohTopoFreqs(b);
            if isfinite(f)
                text = sprintf('%s  (%.1f Hz)', text, f);
            end
        end

        function onToggle(this, b, value)
        %ONTOGGLE  A tickbox changed: show or hide that bin's map.
            this.notifyActivated();
            this.Shown(b) = logical(value);
            this.redraw();
        end
    end

    methods
        function focus = currentFocus(this)
        %CURRENTFOCUS  The first bin shown, by label: what another view
        %   should show to match this one.
            focus = struct();
            first = find(this.Shown, 1);
            if ~isempty(first)
                focus.Bin = this.BinLabels{first};
            end
        end

        function applyFocus(this, focus)
        %APPLYFOCUS  Make sure FOCUS.Bin is among the maps shown, if this
        %   dataset has it; the other ticked bins stay as they are.
            if ~isstruct(focus) || ~isfield(focus, 'Bin') || isempty(this.BinLabels)
                return;
            end
            idx = ViewFocus.indexOfLabel(this.BinLabels, focus.Bin);
            if isempty(idx) || this.Shown(idx)
                return;
            end
            this.Shown(idx) = true;
            delete(this.CheckboxGrid.Children);
            this.buildCheckboxes();
            this.redraw();
        end
    end
end

function label = methodLabel(eeg)
%METHODLABEL  Which estimator made the values, in words for the colour bar.
%   A topography made before the method was recorded used the single window.
    if isfield(eeg, 'CohTopoMethod') && strcmpi(eeg.CohTopoMethod, 'frames')
        label = 'frame-averaged';
    else
        label = 'single window';
    end
end
