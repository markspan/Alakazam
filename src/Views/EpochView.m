classdef EpochView < handle
%EPOCHVIEW  ERP-image view of an epoched multichannel dataset.
%
%   Draws one channel's epoched (time x trials) data as a heatmap -- time
%   on the x-axis, trial on the y-axis, colour the signed amplitude --
%   instead of the previous overlaid-line-traces plot, and instead of a
%   separate "all channels, one trial" mode (removed on request: with
%   dozens to hundreds of channels, overlaying every channel's trace for
%   one trial had exactly the same unreadable-tangle problem the
%   trial-overlay did, and a per-trial channel x time heatmap did not
%   carry its weight as its own mode). Up/down arrows step the channel.
%
%   With realistic trial counts (dozens to hundreds) overlaid opaque
%   lines just become an unreadable tangle: MATLAB's own line colour
%   order cycles after 7 colours, so past that point distinct trials
%   become visually indistinguishable anyway, and the legend needed to
%   tell them apart grows just as unreadable. A heatmap ("ERP-image",
%   the standard EEGLAB/FieldTrip answer to exactly this problem) scales
%   to hundreds of rows without becoming visual noise, and needs no
%   legend at all -- a row's position on the y-axis already tells you
%   which trial it is.
%
%   Row order/grouping is itself a setting, opt-in, not automatic just
%   because the dataset happens to have bins
%   (AlakazamSettings.get("graphics","epochImage","groupByBin")):
%   unchecked (default) shows trials in their plain natural order, no
%   grouping decoration of any kind; checked groups rows by bin (trials
%   with no bin membership trailing last, since that's the single most
%   useful "sort trials by" variable this app already tracks), separated
%   by thin lines, with each group labelled AND bracketed (a slim
%   vertical bracket spanning exactly the rows it covers, see
%   BraceAxes/drawBrace) in a dedicated left-margin panel that widens
%   only while grouping is active -- a trial belonging to more than one
%   bin is then plotted once per bin (more rows than trials). Re-read on
%   every redraw, so toggling it in Settings updates an already-open tab.
%   A thin trial-average trace is drawn below the heatmap: the same
%   "look at the single-trial detail AND the summary at once" idea an
%   ERP-image conventionally pairs with.
%
%   One shared, symmetric colour scale across the WHOLE dataset (every
%   channel, every trial), computed once in the constructor -- so paging
%   through channels with the arrow keys is an eye-to-eye comparison
%   (does channel 3 swing wider than channel 5?), the same "shared
%   scale, not autoscaled per redraw" convention ScalpDistribution/
%   TimeFrequency already established, rather than MATLAB's own default
%   of a fresh, locally-autoscaled range on every redraw.
%
%   Style follows the project standard (UpperCamelCase class/properties,
%   lowerCamelCase methods, double quotes except where a char array is
%   required by an API).
%
%   See also ALAKAZAMPLOTTER, AVERAGEVIEW, FOURIERVIEW, TIMEFREQUENCYVIEW,
%   TRANSTOOLS.DIVERGINGCOLORMAP, ALAKAZAMSETTINGS.

    properties
        % Called (no args) when the user clicks this view's axes. Wired by
        % AlakazamPlotter to Alakazam.registerTileClick, so keyboard
        % shortcuts route to whichever tile was last clicked while several
        % are visible at once in Grid/Stack mode -- see
        % Alakazam.dispatchKey and migration.md.
        ActivatedFcn = function_handle.empty
    end

    properties (SetAccess = private)
        Figure          % owning figure
        Grid            % (2x3) uigridlayout: brace margin | heatmap | colorbar, with the summary trace spanning the heatmap's own column below
        BraceAxes       % narrow left-margin axes: bin-group brackets + rotated labels (empty/unused when ~HasBins)
        HeatAxes        % the ERP-image axes
        HeatImage       % the heatmap's Image object (imagesc handle)
        TraceAxes       % the trial-average trace axes below it
        TraceLine       % the trial-average trace's Line object
        EEG             % the epoched dataset (channels x time x trials)
        Times           % 1 x time, sample times
        Labels          % 1 x nchan cell of channel labels
        Channel = 1     % current channel
        ColorLimit      % shared, symmetric [-lim lim] colour scale for the whole dataset
        HasBins = false      % true when epochs carry .bini membership
        BinNameMap           % containers.Map: bin index -> label (if known)
        BinNamesKnown = false
        TrialOrder      % 1 x nRows, trial index per row (bin-grouped if HasBins, else 1:nTrials);
                         % may repeat a trial index when grouped by bin, so nRows can exceed nTrials
        RowBinKey       % 1 x nRows, each row's bin key (0 = no bin), parallel to TrialOrder
    end

    methods
        function this = EpochView(fig, eeg)
        %EPOCHVIEW  Build the view for an epoched dataset in FIG.
            this.Figure = fig;
            this.EEG    = eeg;
            this.Times  = eeg.times;
            this.Labels = {eeg.chanlocs.labels};

            % Bin membership per trial (written by DefineBins). Optional, so
            % epoched datasets without bins still draw.
            this.HasBins = isfield(eeg, "epoch") && ~isempty(eeg.epoch) ...
                && isfield(eeg.epoch, "bini");
            if isfield(eeg, "bindesc") && ~isempty(eeg.bindesc)
                this.BinNameMap = containers.Map("KeyType", "double", ...
                                                 "ValueType", "char");
                for b = 1:numel(eeg.bindesc)
                    this.BinNameMap(eeg.bindesc(b).index) = char(eeg.bindesc(b).label);
                end
                this.BinNamesKnown = true;
            end

            % Base the shared colour scale on the scalp EEG channels only: a
            % large-amplitude EOG/ECG channel would otherwise set the limit and
            % wash every EEG channel's ERP-image out (see eegChannelMask). Falls
            % back to all channels when there is no usable per-channel type info.
            scaleData = eeg.data;
            if isfield(eeg, "chanlocs") && numel(eeg.chanlocs) == size(eeg.data, 1)
                m = eegChannelMask(eeg.chanlocs);
                scaleData = eeg.data(m, :, :);
            end
            this.ColorLimit = max(abs(scaleData(:)), [], "omitnan");
            if ~isfinite(this.ColorLimit) || this.ColorLimit == 0
                this.ColorLimit = 1; % an all-zero (or all-NaN) dataset would otherwise give an empty [0 0] scale
            end

            % Key handling is wired by the shared Alakazam-level dispatcher
            % (Alakazam.dispatchKey), not a per-view fig.KeyPressFcn here:
            % every open dataset is now a uitab on one shared uifigure, so a
            % per-view KeyPressFcn would be overwritten by whichever view was
            % constructed last, breaking key navigation on every other open
            % tab. A narrow left column, reserved for BraceAxes (the
            % bin-group brackets/labels), starts collapsed to 0 width --
            % drawBinGroupLines (called from the very first redraw() below)
            % widens it only when grouping is actually active (HasBins AND
            % the "groupByBin" setting), and re-collapses it live if the
            % setting is later toggled off. A narrow trailing column is
            % reserved for the colorbar -- see the dedicated hidden axes
            % built below for why it needs its own column rather than
            % attaching directly to HeatAxes (confirmed directly: doing so
            % narrows HeatAxes' own Position to make room for it, breaking
            % the "same width as TraceAxes" pixel alignment below).
            this.Grid = uigridlayout(fig, [2 3], "RowHeight", {'3x', '1x'}, ...
                "ColumnWidth", {0, '1x', TransTools.ColorbarColumnWidth()}, "Padding", [4 4 4 4], "RowSpacing", 2);

            this.BraceAxes = uiaxes(this.Grid);
            this.BraceAxes.Layout.Row = 1;
            this.BraceAxes.Layout.Column = 1;
            this.BraceAxes.Visible = "off";
            this.BraceAxes.XLim = [0, 1];
            % HeatAxes uses imagesc, which defaults YDir to "reverse"
            % (row 1 at the top) -- BraceAxes is a plain axes (no
            % imagesc call ever made on it), which defaults to "normal"
            % (row 1 at the bottom) instead. Left unset, the two panels
            % draw rows in OPPOSITE vertical directions: a bracket for
            % the first group would land at the bottom of BraceAxes but
            % the top of HeatAxes. Match HeatAxes' own convention here.
            this.BraceAxes.YDir = "reverse";
            % A long bin label can legitimately need more width than the
            % fixed-width margin column reserves -- let it spill past x=0
            % rather than truncating (axes Clipping is "on" by default,
            % which would otherwise cut the label's left side off).
            this.BraceAxes.Clipping = "off";
            this.BraceAxes.Toolbar.Visible = "off";
            disableDefaultInteractivity(this.BraceAxes); % a fixed-scale decoration panel, not a real interactive plot

            this.HeatAxes = uiaxes(this.Grid);
            this.HeatAxes.Layout.Row = 1;
            this.HeatAxes.Layout.Column = 2;
            % No y-axis at all (no ruler, no ticks, no "Trial" label):
            % row identity is conveyed by the bracket panel when grouped,
            % and a bare row index carries little meaning otherwise. Set
            % once, here, at creation, and never toggled afterwards --
            % this is also what makes exact x-alignment with TraceAxes
            % below possible at all: confirmed directly that a uiaxes'
            % actual plotted-data box (InnerPosition) reserves a content-
            % dependent left margin for its own y-tick labels even when
            % Position/OuterPosition match exactly, and confirmed
            % directly that toggling YAxis.Visible AFTER the axes has
            % already rendered leaves InnerPosition in a broken,
            % incomplete-relayout state -- it must be set at creation,
            % not toggled live.
            this.HeatAxes.YAxis.Visible = "off";
            this.HeatAxes.ButtonDownFcn = @(~, ~) this.notifyActivated();
            colormap(this.HeatAxes, TransTools.DivergingColormap());
            this.HeatImage = imagesc(this.HeatAxes, this.Times, 1, zeros(1, numel(this.Times)));
            this.HeatImage.ButtonDownFcn = @(~, ~) this.notifyActivated();
            xlabel(this.HeatAxes, "Time (ms)");

            TransTools.AddSharedColorbar(this.Grid, 1, 3, TransTools.DivergingColormap(), ...
                [-this.ColorLimit, this.ColorLimit], "Amplitude (\muV)");

            this.TraceAxes = uiaxes(this.Grid);
            this.TraceAxes.Layout.Row = 2;
            % Same column as HeatAxes (not spanning the brace margin or
            % colorbar columns too) so the two axes are exactly the same
            % width -- their x-axes then land at identical pixel
            % positions, keeping "t=0" (and every other time) vertically
            % aligned between the heatmap and the trial-average trace
            % below it.
            this.TraceAxes.Layout.Column = 2;
            % No y-axis here either (see HeatAxes' own comment above): a
            % uiaxes' left-margin reservation for its y-tick labels is
            % content-dependent, so even with matching Position/width,
            % HeatAxes and TraceAxes would NOT land on the same actual
            % x-pixels unless BOTH have the same (here: zero) reservation
            % -- confirmed directly, matching numeric amplitude ticks on
            % one and none on the other still left a several-pixel gap.
            % The trial average's amplitude scale is already visible via
            % the heatmap's own colorbar, in the same units.
            this.TraceAxes.YAxis.Visible = "off";
            this.TraceAxes.ButtonDownFcn = @(~, ~) this.notifyActivated();
            this.TraceLine = plot(this.TraceAxes, this.Times, zeros(size(this.Times)), "Color", "k", "LineWidth", 1.2);
            title(this.TraceAxes, "Trial average");
            xlabel(this.TraceAxes, "Time (ms)");
            xlim(this.TraceAxes, [this.Times(1), this.Times(end)]);

            this.redraw();
            axtoolbar(this.HeatAxes, "default");
            axtoolbar(this.TraceAxes, "default");
        end

        function redraw(this)
        %REDRAW  ERP-image: every row (bin-grouped, see TrialOrder/
        %   computeTrialOrder) x time (columns), for the current channel;
        %   the mean across trials as the summary trace below.
        %   TrialOrder/RowBinKey are recomputed here (not cached from the
        %   constructor) so toggling the "group by bin" setting updates
        %   an already-open tab.
            this.TrialOrder = this.computeTrialOrder();
            data = squeeze(this.EEG.data(this.Channel, :, :))'; % nTrials x nTime
            ordered = data(this.TrialOrder, :); % nRows x nTime; nRows == nTrials unless grouped by bin
            nRows = size(ordered, 1);

            this.HeatImage.XData = this.Times;
            this.HeatImage.YData = 1:nRows;
            this.HeatImage.CData = ordered;
            this.HeatAxes.CLim = [-this.ColorLimit, this.ColorLimit];
            xlim(this.HeatAxes, [this.Times(1), this.Times(end)]);
            ylim(this.HeatAxes, [0.5, nRows + 0.5]);
            title(this.HeatAxes, "Channel: " + this.Labels{this.Channel});
            this.drawBinGroupLines(nRows);

            this.TraceLine.YData = mean(data, 1, "omitnan");
        end

        function onKey(this, event)
        %ONKEY  Up/down arrows step the shown channel.
        %   Public (not a private helper): dispatched by
        %   Alakazam.dispatchKey for whichever tab is currently selected --
        %   see the constructor comment.
            switch lower(event.Key)
                case "uparrow"
                    this.Channel = max(1, this.Channel - 1);
                case "downarrow"
                    this.Channel = min(size(this.EEG.data, 1), this.Channel + 1);
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
        %   currently active, mirroring SignalView's own onWheel
        %   contract (see its own comment for why dispatch is central,
        %   not a per-view fig.WindowScrollWheelFcn).
            if callbackData.VerticalScrollCount > 0
                this.Channel = min(size(this.EEG.data, 1), this.Channel + 1);
            else
                this.Channel = max(1, this.Channel - 1);
            end
            this.redraw();
            this.notifyActivated();
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
        function drawBinGroupLines(this, nRows)
        %DRAWBINGROUPLINES  Thin horizontal separators between bin groups
        %   in HeatAxes, and, in the dedicated BraceAxes margin, a
        %   bracket + label for each group, spanning exactly the rows it
        %   covers -- from this.RowBinKey, one key per ROW (not per
        %   trial), which stays correct in "group by bin" mode where a
        %   trial can appear as more than one row, each under a
        %   different bin. Only drawn at all when grouping is actually
        %   ACTIVE (both HasBins and the "groupByBin" setting are true --
        %   computeTrialOrder already leaves RowBinKey all-zero
        %   otherwise), so the brace margin column collapses back to 0
        %   width and the heatmap/trace reclaim the full tab width when
        %   the setting is off, exactly like a bins-less dataset.
            delete(findobj(this.HeatAxes, "Type", "constantline"));
            cla(this.BraceAxes);
            isGrouped = this.HasBins && AlakazamSettings.get("graphics", "epochImage", "groupByBin");
            if ~isGrouped
                this.Grid.ColumnWidth{1} = 0;
                return;
            end
            this.Grid.ColumnWidth{1} = 100;
            orderedKeys = this.RowBinKey;
            boundaries = find(diff(orderedKeys) ~= 0);
            hold(this.HeatAxes, "on");
            for b = boundaries
                yline(this.HeatAxes, b + 0.5, "Color", [0 0 0], "LineWidth", 1);
            end
            hold(this.HeatAxes, "off");

            groupStarts = [1, boundaries + 1];
            groupEnds   = [boundaries, nRows];

            this.BraceAxes.YLim = this.HeatAxes.YLim; % keep the brace panel's rows aligned with the heatmap's

            labels = strings(1, numel(groupStarts));
            for g = 1:numel(groupStarts)
                key = orderedKeys(groupStarts(g));
                if key == 0
                    labels(g) = "no bin";
                elseif this.BinNamesKnown && isKey(this.BinNameMap, key)
                    labels(g) = string(this.BinNameMap(key));
                else
                    labels(g) = string(key);
                end
            end

            % Labels are rotated 90 degrees, so their reading-direction
            % extent runs VERTICALLY, alongside their own bracket. A
            % label is only shrunk when it would actually collide with
            % its immediate neighbour's label -- not just because it is
            % "wider" (taller) than its own bracket's row span: a short
            % group's label is free to spread past its own bracket's
            % bounds towards a comfortably-spaced neighbour, as long as
            % the two labels themselves don't overlap. Never overlapping
            % takes priority over legibility: no minimum font size floor
            % other than what's needed to avoid a literal zero/negative
            % FontSize, so an extreme case (e.g. a 2-trial group next to
            % a 100-trial one) still shrinks as far as it must.
            %
            % Collision uses each text object's own KNOWN anchor Y
            % (ymids, computed here, not re-derived from the object)
            % together with Extent(4) (height) only -- confirmed directly
            % that Extent(4)'s MAGNITUDE correctly reflects Rotation (a
            % rotated label's height is its string length, as expected),
            % but Extent's POSITION component is unreliable under
            % BraceAxes.YDir="reverse" combined with Rotation=90 (does
            % not consistently anchor around the known text position --
            % confirmed directly with a minimal reproduction), so it must
            % not be used at all here.
            requestedFontSize = 12;
            labelX = 0.85 - 0.12 - 0.08; % must match drawBrace's own xLine/tipLen and this label gap

            hold(this.BraceAxes, "on");
            textHandles = gobjects(1, numel(groupStarts));
            ymids = zeros(1, numel(groupStarts));
            for g = 1:numel(groupStarts)
                y1 = groupStarts(g) - 0.5;
                y2 = groupEnds(g) + 0.5;
                ymids(g) = (y1 + y2) / 2;
                this.drawBrace(y1, y2);
                textHandles(g) = text(this.BraceAxes, labelX, ymids(g), labels(g), ...
                    "HorizontalAlignment", "center", "VerticalAlignment", "middle", ...
                    "FontSize", requestedFontSize, "Rotation", 90);
            end

            for g = 1:numel(groupStarts) - 1
                % Re-measured (not just once): FontSize-to-Extent scaling
                % is only approximately linear in practice (font
                % rendering/hinting), so a couple of correction passes
                % converges more precisely than trusting one calculation.
                for attempt = 1:3
                    h1 = textHandles(g).Extent(4);
                    h2 = textHandles(g + 1).Extent(4);
                    hi1 = ymids(g) + h1 / 2;
                    lo2 = ymids(g + 1) - h2 / 2;
                    overlap = hi1 - lo2;
                    if overlap <= 0
                        break;
                    end
                    totalHeight = h1 + h2;
                    % The scale that makes the two labels' combined
                    % height exactly equal the (fixed) gap between their
                    % anchors: newTotalHeight = totalHeight - 2*overlap.
                    scale = max(0.05, (totalHeight - 2 * overlap) / totalHeight);
                    textHandles(g).FontSize     = textHandles(g).FontSize * scale;
                    textHandles(g + 1).FontSize = textHandles(g + 1).FontSize * scale;
                end
            end
            hold(this.BraceAxes, "off");
        end

        function drawBrace(this, y1, y2)
        %DRAWBRACE  A slim, rounded bracket in BraceAxes spanning rows
        %   [Y1 Y2]: a vertical line with small rounded "grip" corners at
        %   each end (marking the exact row boundaries, curving towards
        %   the heatmap) and one small rounded bump at the vertical
        %   midpoint pointing the other way, towards the group's label --
        %   drawn separately by the caller (drawBinGroupLines), not here,
        %   since its font size depends on collision-checking against its
        %   neighbours' labels, not on any one bracket in isolation.
        %   Drawn as one continuous polyline (straight segments,
        %   elliptical-arc corners and a sine-curve bump for the tip)
        %   rather than separate sharp-cornered segments, for a smoother,
        %   more finished look. BraceAxes' fixed XLim = [0 1] regardless
        %   of its actual pixel width, so X figures here are proportions
        %   of the margin column's width, not row units.
            xLine   = 0.85; % the vertical line -- close to the heatmap edge (x=1), not the middle of the margin
            gripLen = 0.08; % end-cap grips, curving right towards the rows they bound
            tipLen  = 0.12; % the midpoint bump, pointing left towards the label
            ymid = (y1 + y2) / 2;

            % Corner/bump radii shrink to fit a very short (few-row)
            % group rather than overlapping each other.
            rX = 0.055;
            rY = min(5, (y2 - y1) * 0.25);
            bumpHalf = min(0.6, (y2 - y1) * 0.35);
            reserved = 2 * (rY + bumpHalf);
            if reserved > (y2 - y1) && reserved > 0
                scale = (y2 - y1) / reserved;
                rY = rY * scale;
                bumpHalf = bumpHalf * scale;
            end

            nArc = 10;
            aBot = linspace(3 * pi / 2, pi, nArc); % bottom corner: grip (right) into the vertical line (up)
            arcBotX = (xLine + rX) + rX * cos(aBot);
            arcBotY = (y1 + rY) + rY * sin(aBot);

            aTop = linspace(pi, pi / 2, nArc); % top corner: vertical line (up) into the grip (right)
            arcTopX = (xLine + rX) + rX * cos(aTop);
            arcTopY = (y2 - rY) + rY * sin(aTop);

            nBump = 20;
            tt = linspace(0, 1, nBump);
            bumpX = xLine - tipLen * sin(pi * tt); % smooth half-sine poking left, peaking at the midpoint
            bumpY = (ymid - bumpHalf) + 2 * bumpHalf * tt;

            x = [xLine + gripLen, arcBotX, bumpX, arcTopX, xLine + gripLen];
            y = [y1,              arcBotY, bumpY, arcTopY, y2];
            plot(this.BraceAxes, x, y, "Color", [0.3 0.3 0.3], "LineWidth", 1.1);
        end

        function order = computeTrialOrder(this)
        %COMPUTETRIALORDER  Row order, and this.RowBinKey (one bin key per
        %   row). Two modes, selected by the "graphics"/"epochImage"/
        %   "groupByBin" setting (read fresh every call, so toggling it
        %   updates an already-open tab):
        %     - false (default), or no bins at all: natural trial order
        %       (1:nTrials), no grouping, no brackets/labels drawn.
        %     - true: one row per (trial, bin) membership, grouped by
        %       bin ascending -- a trial belonging to more than one bin
        %       is plotted once per bin it belongs to, so the row count
        %       can exceed the trial count. Trials with no bin
        %       membership trail last (key 0 sorts before any real bin
        %       index).
            nTrials = size(this.EEG.data, 3);
            if ~this.HasBins || ~AlakazamSettings.get("graphics", "epochImage", "groupByBin")
                order = 1:nTrials;
                this.RowBinKey = zeros(1, nTrials);
                return;
            end
            [order, this.RowBinKey] = this.computeTrialOrderByBin();
        end

        function [order, keys] = computeTrialOrderByBin(this)
        %COMPUTETRIALORDERBYBIN  "Group by bin" row order: every
        %   (trial, bin) membership becomes its own row, grouped by bin
        %   ascending and listed in original trial order within each
        %   bin -- so a trial belonging to more than one bin appears as
        %   more than one row. Trials with no bin membership trail last,
        %   same convention as the default (single-row) mode.
            nTrials = size(this.EEG.data, 3);
            biniLists = cell(1, nTrials);
            for t = 1:nTrials
                biniLists{t} = this.EEG.epoch(t).bini;
            end
            allBins = sort(unique([biniLists{:}]));
            order = [];
            keys = [];
            for bin = allBins
                inBin = find(cellfun(@(b) ismember(bin, b), biniLists));
                order = [order, inBin]; %#ok<AGROW>
                keys  = [keys, repmat(bin, 1, numel(inBin))]; %#ok<AGROW>
            end
            unbinned = find(cellfun(@isempty, biniLists));
            order = [unbinned, order];
            keys  = [zeros(1, numel(unbinned)), keys];
        end
    end
end
