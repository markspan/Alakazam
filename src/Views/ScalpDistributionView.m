classdef ScalpDistributionView < handle
%SCALPDISTRIBUTIONVIEW  One scalp topography, scrubbable by time, with a
%   bin dropdown when there is more than one.
%
%   The flat-2D-topoplot sibling of Brain3DView (its rotatable 3D-brain-mesh
%   counterpart): both draw a ScalpDistribution-family result (see
%   TransTools.ResolveScalpDistribution/TransTools.TickedScalpBins, shared
%   between them) with the identical single-plot-plus-bin-dropdown
%   interface -- this used to draw a whole grid of per-bin tiles at once
%   (up to 3 per row); one topography plus a dropdown reads far more
%   clearly once there are more than a couple of bins, and keeps the two
%   sibling views consistent with each other. The dropdown/time-label/
%   Play-button/slider scaffolding itself is also shared -- see
%   TimeScrubStrip.
%
%   Drawn via TransTools.DrawScalpMap (a uiaxes-compatible port of
%   EEGLAB's topoplot(), see its own header comment for why a port was
%   needed at all). A uislider along the bottom scrubs through the
%   dataset's time range; the plot redraws live while dragging (uislider's
%   ValueChangingFcn fires continuously during the drag itself, not just
%   on release -- the uifigure-native equivalent of the PostSet-listener
%   trick the previous classic-uicontrol-slider version needed, and
%   arguably simpler).
%
%   Only offers the bins currently ticked on in this dataset's own Average
%   plot (its AverageView tickboxes), if that tab happens to be open -- see
%   TransTools.TickedScalpBins. Falls back to every bin if that tab is not
%   open, its bin count no longer matches this dataset, or every bin
%   happens to be unticked (a softer fallback than the previous pure-plot
%   version's own hard error for the "every bin unticked" case: this
%   result is now a real, persisted tree node that can be reopened at any
%   time, including after every bin has since been unticked elsewhere, so
%   showing everything is friendlier than refusing to open at all).
%
%   Style follows the project standard.
%
%   See also ALAKAZAMPLOTTER, SCALPDISTRIBUTION, BRAIN3DVIEW, TIMESCRUBSTRIP,
%   TRANSTOOLS.DRAWSCALPMAP, TRANSTOOLS.TICKEDSCALPBINS,
%   TRANSTOOLS.RESOLVESCALPDISTRIBUTION, TIMEFREQUENCYVIEW, AVERAGEVIEW.

    properties
        % Called (no args) when the user clicks the topography, the bin
        % dropdown, or the slider. Wired by AlakazamPlotter to
        % Alakazam.registerTileClick, so keyboard/wheel shortcuts route to
        % whichever tile was last clicked while several are visible at
        % once in Grid/Stack mode -- see Alakazam.dispatchKey/dispatchWheel
        % and migration.md. (ScalpDistributionView has no keyboard
        % navigation -- but the mouse wheel scrubs the time slider, see
        % onWheel.)
        ActivatedFcn = function_handle.empty
    end

    properties (SetAccess = private)
        Figure          % owning uitab
        EEG             % averaged dataset (channels x samples[ x bins]) with .ScalpChanlocs/.ScalpHasPos/.ScalpMapLimit
        Grid            % uigridlayout: optional bin-dropdown row, the topography axes, the slider strip
        Axes            % the single topography uiaxes
        BinIndices      % original EEG.data 3rd-dim index for each selectable bin
        BinLabels       % display label for each entry in BinIndices, same order
        SelectedBin     % index INTO BinIndices of the bin currently drawn
        Strip           % TimeScrubStrip, the bin-dropdown/time-label/Play-button/slider scaffolding
    end

    methods
        function this = ScalpDistributionView(fig, eeg)
        %SCALPDISTRIBUTIONVIEW  Build the topography view for EEG in FIG.
            this.Figure = fig;
            this.EEG    = eeg;

            isBinned = ndims(eeg.data) == 3 && isfield(eeg, 'bindesc') && ~isempty(eeg.bindesc);
            if isBinned
                nBinsTotal = size(eeg.data, 3);
                labels = {eeg.bindesc.label};
            else
                nBinsTotal = 1;
                labels = {char(string(eeg.id))};
            end

            selected = TransTools.TickedScalpBins(fig, eeg, nBinsTotal);
            this.BinIndices = find(selected);
            this.BinLabels  = labels(this.BinIndices);
            this.SelectedBin = 1;

            hasDropdown = numel(this.BinIndices) > 1;
            dropdownRows = double(hasDropdown); % 0 or 1 extra row at the top

            % Rows: [optional bin dropdown, the topography axes, the
            % "t = ... ms" readout, the Play+slider strip]. Columns: the
            % axes itself, plus one narrow trailing column for the shared
            % colorbar -- see the dedicated hidden axes built below for why
            % it needs its own column rather than sharing the topography's.
            this.Grid = uigridlayout(fig, [dropdownRows + 3, 2], ...
                "RowHeight", [repmat({26}, 1, dropdownRows), {'1x'}, {22}, {36}], ...
                "ColumnWidth", {'1x', TransTools.ColorbarColumnWidth()}, "Padding", [4 4 4 4]);

            axRow = dropdownRows + 1;
            this.Axes = uiaxes(this.Grid);
            this.Axes.Layout.Row = axRow;
            this.Axes.Layout.Column = 1;
            this.Axes.ButtonDownFcn = @(~, ~) this.notifyActivated();
            title(this.Axes, this.BinLabels{this.SelectedBin}, "Interpreter", "none");
            axtoolbar(this.Axes, "default");

            this.Strip = TimeScrubStrip(this.Grid, 1, axRow + 1, axRow + 2, ...
                this.BinLabels, eeg.times, @() this.notifyActivated(), ...
                @(t) this.redraw(t), @(idx) this.onBinChanged(idx));
            this.redraw(this.Strip.Slider.Value);

            % One shared colorbar, in its own reserved column -- see
            % TransTools.AddSharedColorbar for why it is a dedicated hidden
            % axes rather than attached to Axes directly (DrawScalpMap
            % forces axis(ax,'square'), so narrowing it to fit a colorbar
            % would also shrink its height to preserve that aspect). Built
            % AFTER the first redraw() above -- see Brain3DView's own
            % constructor comment for why (a real reported regression when
            % this order was briefly swapped for cross-file consistency).
            TransTools.AddSharedColorbar(this.Grid, axRow, 2, TransTools.DivergingColormap(), ...
                [-eeg.ScalpMapLimit, eeg.ScalpMapLimit], "Amplitude (\muV)");
        end

        function redraw(this, t)
        %REDRAW  Show the currently selected bin's scalp topography at the
        %   instant nearest T (ms). Called directly by the constructor and
        %   by TimeScrubStrip's own callbacks (slider drag/release, Play,
        %   a bin switch). DrawScalpMap's own cla(ax) call clears the
        %   plotted data but not ax.Title (cla without 'reset' preserves
        %   Title/XLabel/YLabel), so the title set in the constructor (or
        %   in onBinChanged, on a bin switch) survives every call here
        %   without needing to be reapplied each time.
            eeg = this.EEG;
            [~, idx] = min(abs(eeg.times - t));
            this.Strip.TimeLabel.Text = sprintf('t = %.0f ms', eeg.times(idx));
            values = eeg.data(eeg.ScalpHasPos, idx, this.BinIndices(this.SelectedBin));
            TransTools.DrawScalpMap(this.Axes, values, eeg.ScalpChanlocs, eeg.ScalpMapLimit);
        end

        function onWheel(this, callbackData)
        %ONWHEEL  Public: dispatched centrally by Alakazam.dispatchWheel
        %   for whichever tab is currently active; forwarded straight to
        %   TimeScrubStrip's own onWheel (mouse wheel scrubs the slider).
            this.Strip.onWheel(callbackData);
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
        function onBinChanged(this, binIdx)
        %ONBINCHANGED  TimeScrubStrip's OnBinChangedFcn hook: switch the
        %   displayed bin and update the title (redraw() itself is called
        %   by TimeScrubStrip right after this returns). The title is
        %   updated here, not in redraw() (see its own comment), since it
        %   is the label that actually changes on a bin switch, not the
        %   drawn instant.
            this.SelectedBin = binIdx;
            title(this.Axes, this.BinLabels{binIdx}, "Interpreter", "none");
        end
    end
end
