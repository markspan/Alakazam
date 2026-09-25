classdef EpochView < AlakazamView
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
%   "Bin:" shows one bin's trials alone (every ordinary bin that holds a
%   trial is offered; a combination bin has none of its own), with the
%   average below taken over them, or "All trials". A bin shown alone is
%   never bracketed, since there is one group. The choice is reported to
%   ViewFocus and adopted from it like the other views' bin choices, so the
%   same bin follows from node to node.
%
%   "Sort by" puts the rows in order of a per-trial value (epochSortKeys
%   lists what a dataset offers: when the next or previous event of each
%   type fell, DefineBins' reaction time, and any numeric field of the
%   time-locking event, such as a fixation's duration or a saccade's
%   amplitude), ascending from the top (descending with the "Reverse the
%   sort" setting, as EEGLAB's erpimage draws it), trials without a value
%   last either way. With "group by bin" on, the sort happens within each
%   bin, so the
%   groups stay whole (the split the Unfold ERP-image tutorial uses). When
%   the value is a time after the event (reaction time, duration) it is
%   drawn across the image as a line, so activity that moves with it (a
%   response, the next saccade) shows as a band following the line, and
%   activity locked to the event as a vertical one. That is the picture
%   that tells overlap from a response: on Deconvolve's overlap-corrected
%   trials the band following the line should be gone.
%
%   One shared, symmetric colour scale PER CHANNEL GROUP (EEG/EOG/OTHER,
%   see channelGroup), computed once in the constructor -- so paging
%   through channels with the arrow keys is an eye-to-eye comparison
%   within a group (does EEG channel 3 swing wider than EEG channel 5?),
%   the same "shared scale, not autoscaled per redraw" convention
%   ScalpDistribution/TimeFrequency already established, rather than
%   MATLAB's own default of a fresh, locally-autoscaled range on every
%   redraw. Grouped, not one single scale across the whole dataset,
%   because a large-amplitude EOG/ECG channel would otherwise set the
%   limit and wash every EEG channel's ERP-image out (or vice versa) --
%   each group gets a scale appropriate to its own typical amplitude.
%
%   THE AUTOMATIC SCALE IS THE 98TH PERCENTILE of the group's absolute
%   amplitude (robustColorLimit), not its maximum. The maximum was set by
%   the one largest sample, a blink, a drift or an unrejected artefact, and
%   left ordinary single-trial activity in the palest few colours.
%   "Colour ±" in the top row shows the scale of the shown channel's group
%   and takes a value of its own; "Auto" puts the automatic one back. Set
%   per group, so paging through the channels of one group stays
%   comparable.
%
%   Style follows the project standard (UpperCamelCase class/properties,
%   lowerCamelCase methods, double quotes except where a char array is
%   required by an API).
%
%   See also ALAKAZAMPLOTTER, AVERAGEVIEW, FOURIERVIEW, TIMEFREQUENCYVIEW,
%   TRANSTOOLS.DIVERGINGCOLORMAP, ALAKAZAMSETTINGS.

    properties
    end

    properties (SetAccess = private)
        Figure          % owning figure
        Grid            % (3x3) uigridlayout: channel dropdown row, then brace margin | heatmap | colorbar, with the summary trace spanning the heatmap's own column below
        ChannelDropdown % "Channel:" uidropdown (see TransTools.BuildChannelDropdown), row 1
        BraceAxes       % narrow left-margin axes: bin-group brackets + rotated labels (empty/unused when ~HasBins)
        HeatAxes        % the ERP-image axes
        HeatImage       % the heatmap's Image object (imagesc handle)
        TraceAxes       % the trial-average trace axes below it
        TraceLine       % the trial-average trace's Line object
        EEG             % the epoched dataset (channels x time x trials)
        Times           % 1 x time, sample times
        Labels          % 1 x nchan cell of channel labels
        Channel = 1     % current channel
        ChannelGroup    % 1 x nchan cellstr, each channel's display group ("EEG"/"EOG"/"OTHER", see channelGroup)
        GroupColorLimit % containers.Map: group name -> shared, symmetric [-lim lim] colour scale for that group
        AutoColorLimit  % containers.Map: group name -> the automatic scale (robustColorLimit), which "Auto" restores
        ColorField      % "Colour ±" numeric field, row 1: the shown group's limit, editable
        ShownLimit      % the limit the drawn ColorbarWrap was built for
        ColorbarWrap    % the shared colorbar's own wrapping sub-grid (TransTools.AddSharedColorbar); rebuilt, not just re-CLim'd, when the shown channel's group changes
        ShownGroup      % the group the currently-drawn ColorbarWrap/HeatAxes.CLim was built for, so redraw() only rebuilds the colorbar when it actually changes
        HasBins = false      % true when epochs carry .bini membership
        BinNameMap           % containers.Map: bin index -> label (if known)
        BinNamesKnown = false
        TrialOrder      % 1 x nRows, trial index per row (bin-grouped if HasBins, else 1:nTrials);
                         % may repeat a trial index when grouped by bin, so nRows can exceed nTrials
        RowBinKey       % 1 x nRows, each row's bin key (0 = no bin), parallel to TrialOrder
        BinDropdown     % "Bin:" uidropdown, row 1: every trial, or one bin's alone
        BinChoices      % positions in EEG.bindesc of the bins "Bin:" offers (ordinary bins with trials)
        SelectedBin = 0 % position in EEG.bindesc of the bin shown alone, 0 for every trial
        SortKeys        % what the trials can be sorted by (epochSortKeys)
        SortDropdown    % "Sort by:" uidropdown, row 1; its value indexes SortKeys, 0 = recording order
        SortLine        % the sort value drawn across the heatmap when it is a time (else NaN data)
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

            % Base each channel's colour scale on its OWN group's range
            % (EEG/EOG/OTHER, see channelGroup), not one shared scale across
            % everything -- see this file's own header comment for why.
            % Falls back to "every channel is EEG" when there is no usable
            % per-channel chanlocs at all (channelGroup's own fallback).
            if isfield(eeg, "chanlocs") && numel(eeg.chanlocs) == size(eeg.data, 1)
                this.ChannelGroup = channelGroup(eeg.chanlocs);
            else
                this.ChannelGroup = repmat({'EEG'}, 1, size(eeg.data, 1));
            end
            this.GroupColorLimit = containers.Map("KeyType", "char", "ValueType", "double");
            this.AutoColorLimit = containers.Map("KeyType", "char", "ValueType", "double");
            for g = unique(this.ChannelGroup)
                mask = strcmp(this.ChannelGroup, g{1});
                lim = EpochView.robustColorLimit(eeg.data(mask, :, :));
                this.AutoColorLimit(g{1}) = lim;
                this.GroupColorLimit(g{1}) = lim;
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
            this.Grid = uigridlayout(fig, [3 3], "RowHeight", {22, '3x', '1x'}, ...
                "ColumnWidth", {0, '1x', TransTools.ColorbarColumnWidth()}, "Padding", [4 4 4 4], "RowSpacing", 2);

            % Row 1: jump straight to an electrode instead of stepping to it
            % one channel at a time with the up/down arrow keys (onKey) --
            % spans every column, above the brace margin/heatmap/colorbar
            % row, so it is unaffected by the brace column's own width
            % (collapsed to 0 except while "group by bin" is active).
            % The row is shared with "Bin", "Sort by" and the colour scale.
            controls = uigridlayout(this.Grid, [1 4], "ColumnWidth", {'1x', '1x', '1x', 220}, ...
                "Padding", [0 0 0 0], "ColumnSpacing", 12);
            controls.Layout.Row = 1;
            controls.Layout.Column = [1, 3];
            this.ChannelDropdown = TransTools.BuildChannelDropdown(controls, 1, 1, ...
                this.Labels, @(idx) this.onChannelSelected(idx));
            this.BinChoices = EpochView.selectableBins(eeg);
            this.BinDropdown = TransTools.BuildBinDropdown(controls, 1, 2, ...
                [{'All trials'}, this.binLabels()], @(choice) this.onBinSelected(choice));
            this.BinDropdown.Tag = "bin";
            if isempty(this.BinChoices)
                this.BinDropdown.Enable = "off";
                this.BinDropdown.Tooltip = 'These trials are in no bin, so there is none to show alone.';
            end
            this.SortKeys = epochSortKeys(eeg);
            this.SortDropdown = this.buildSortDropdown(controls);
            this.ColorField = this.buildColorControl(controls);

            this.BraceAxes = uiaxes(this.Grid);
            this.BraceAxes.Layout.Row = 2;
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
            this.HeatAxes.Layout.Row = 2;
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
            hold(this.HeatAxes, "on");
            this.SortLine = plot(this.HeatAxes, NaN, NaN, "k-", "LineWidth", 1.5, "HitTest", "off");
            hold(this.HeatAxes, "off");
            xlabel(this.HeatAxes, "Time (ms)");

            % The shared colorbar itself is built by redraw() below (it
            % needs this.ChannelGroup/GroupColorLimit above, plus
            % this.Channel, to pick the right group's scale, and is rebuilt
            % whenever paging lands on a different group -- see redraw()'s
            % own comment).

            this.TraceAxes = uiaxes(this.Grid);
            this.TraceAxes.Layout.Row = 3;
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
            group = this.ChannelGroup{this.Channel};
            lim = this.GroupColorLimit(group);
            this.HeatAxes.CLim = [-lim, lim];
            if ~isequal(group, this.ShownGroup) || ~isequal(lim, this.ShownLimit)
                % Paging landed on a different group (EEG/EOG/OTHER) than
                % what the colorbar currently shows, or its scale was set
                % in "Colour ±" -- rebuild it to match.
                % AddSharedColorbar's own hidden axes isn't exposed to just
                % re-set CLim on, so a changing scale means delete() + build
                % again (see its own header comment on this exact case).
                if ~isempty(this.ColorbarWrap) && isvalid(this.ColorbarWrap)
                    delete(this.ColorbarWrap);
                end
                this.ColorbarWrap = TransTools.AddSharedColorbar(this.Grid, 2, 3, ...
                    TransTools.DivergingColormap(), [-lim, lim], "Amplitude (\muV)");
                this.ShownGroup = group;
                this.ShownLimit = lim;
            end
            this.ColorField.Value = lim;
            xlim(this.HeatAxes, [this.Times(1), this.Times(end)]);
            ylim(this.HeatAxes, [0.5, nRows + 0.5]);
            key = this.currentSortKey();
            heading = "Channel: " + this.Labels{this.Channel};
            if this.SelectedBin > 0
                heading = heading + ", " + this.binLabel(this.SelectedBin);
            end
            if ~isempty(key)
                heading = heading + ", sorted by " + key.label;
            end
            title(this.HeatAxes, heading);
            this.ChannelDropdown.Value = this.Channel;
            this.drawBinGroupLines(nRows);
            this.drawSortLine(key);

            % The average of what the image shows: every trial, or the
            % chosen bin's.
            if this.SelectedBin > 0
                this.TraceLine.YData = mean(data(unique(this.TrialOrder), :), 1, "omitnan");
                title(this.TraceAxes, "Average of " + this.binLabel(this.SelectedBin));
            else
                this.TraceLine.YData = mean(data, 1, "omitnan");
                title(this.TraceAxes, "Trial average");
            end
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

    end

    methods (Access = private)
        function tf = showsBinGroups(this)
        %SHOWSBINGROUPS  Rows grouped by bin, with brackets: the dataset has
        %   bins, the "groupByBin" setting is on (read fresh), and no single
        %   bin is chosen in "Bin:", where one group would only repeat it.
            tf = this.HasBins && this.SelectedBin == 0 ...
                && AlakazamSettings.get("graphics", "epochImage", "groupByBin");
        end

        function onBinSelected(this, choice)
        %ONBINSELECTED  "Bin:"'s ValueChangedFcn. CHOICE 1 is every trial;
        %   CHOICE k shows the trials of bin BinChoices(k - 1) alone.
            this.notifyActivated();
            if choice <= 1
                this.SelectedBin = 0;
            else
                this.SelectedBin = this.BinChoices(choice - 1);
            end
            this.redraw();
        end

        function onChannelSelected(this, idx)
        %ONCHANNELSELECTED  ChannelDropdown's ValueChangedFcn: jump straight
        %   to the picked electrode, the same effect as stepping there one
        %   channel at a time with the up/down arrow keys (onKey).
            this.notifyActivated();
            this.Channel = idx;
            this.redraw();
        end

        function drawBinGroupLines(this, nRows)
        %DRAWBINGROUPLINES  Thin horizontal separators between bin groups
        %   in HeatAxes, and, in the dedicated BraceAxes margin, a
        %   bracket + label for each group, spanning exactly the rows it
        %   covers -- from this.RowBinKey, one key per ROW (not per
        %   trial), which stays correct in "group by bin" mode where a
        %   trial can appear as more than one row, each under a
        %   different bin. Only drawn at all when grouping is actually
        %   ACTIVE (showsBinGroups: HasBins, the "groupByBin" setting, and
        %   no single bin chosen -- computeTrialOrder already leaves
        %   RowBinKey all-zero otherwise), so the brace margin column
        %   collapses back to 0 width and the heatmap/trace reclaim the full
        %   tab width when the setting is off, exactly like a bins-less
        %   dataset.
            delete(findobj(this.HeatAxes, "Type", "constantline"));
            cla(this.BraceAxes);
            if ~this.showsBinGroups()
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
        %   Either way, a "Sort by" choice then orders the rows within each
        %   run of equal RowBinKey (the whole image when not grouped), so
        %   RowBinKey itself is unchanged by it: smallest at the top, or
        %   largest with the "reverseSort" setting (also read fresh).
        %   A bin chosen in "Bin:" comes first: its trials alone, in
        %   recording order, and no grouping.
            nTrials = size(this.EEG.data, 3);
            if this.SelectedBin > 0
                order = reshape(TransTools.BinTrials(this.EEG, this.SelectedBin), 1, []);
                order = order(order >= 1 & order <= nTrials);
                this.RowBinKey = zeros(1, numel(order));
            elseif ~this.showsBinGroups()
                order = 1:nTrials;
                this.RowBinKey = zeros(1, nTrials);
            else
                [order, this.RowBinKey] = this.computeTrialOrderByBin();
            end
            key = this.currentSortKey();
            if ~isempty(key)
                order = EpochView.sortWithinGroups(order, this.RowBinKey, key.values, ...
                    AlakazamSettings.get("graphics", "epochImage", "reverseSort"));
            end
        end

        function dropdown = buildSortDropdown(this, parent)
        %BUILDSORTDROPDOWN  "Sort by:" beside the channel control. Always
        %   shown, so its place does not jump between datasets; disabled,
        %   with the reason as its tooltip, when the trials offer nothing to
        %   sort by.
            box = uigridlayout(parent, [1, 2], "ColumnWidth", {70, '1x'}, ...
                "Padding", [0 0 0 0], "ColumnSpacing", 4);
            box.Layout.Row = 1;
            box.Layout.Column = 3;
            uilabel(box, "Text", "Sort by:", "HorizontalAlignment", "right");
            dropdown = uidropdown(box, "Tag", "sortBy", ...
                "Items", [{'Recording order'}, {this.SortKeys.label}], ...
                "ItemsData", 0:numel(this.SortKeys), "Value", 0, ...
                "ValueChangedFcn", @(~, ~) this.redraw());
            if isempty(this.SortKeys)
                dropdown.Enable = "off";
                dropdown.Tooltip = ['These trials carry nothing to sort by: no neighbouring ' ...
                    'events recorded when they were cut, no reaction time from DefineBins, and ' ...
                    'no numeric field on their events that varies.'];
            end
        end

        function field = buildColorControl(this, parent)
        %BUILDCOLORCONTROL  "Colour ±" with its "Auto" button, at the end of
        %   the top row: the colour scale of the shown channel's group, which
        %   redraw keeps showing and which a value typed here replaces.
            box = uigridlayout(parent, [1, 3], "ColumnWidth", {62, '1x', 48}, ...
                "Padding", [0 0 0 0], "ColumnSpacing", 4);
            box.Layout.Row = 1;
            box.Layout.Column = 4;
            uilabel(box, "Text", "Colour ±", "HorizontalAlignment", "right");
            field = uieditfield(box, "numeric", "Tag", "colourRange", "Value", 1, ...
                "Limits", [0 Inf], "LowerLimitInclusive", "off", "ValueDisplayFormat", "%.3g", ...
                "ValueChangedFcn", @(src, ~) this.setColorLimit(src.Value), ...
                "Tooltip", ['The colour scale runs from minus to plus this value, for every ' ...
                 'channel of the shown channel''s group (EEG, EOG or other), so stepping ' ...
                 'through them stays comparable. Auto sets it from the data: the 98th ' ...
                 'percentile of the absolute amplitude.']);
            uibutton(box, "Text", "Auto", "Tag", "colourAuto", ...
                "Tooltip", 'Back to the scale taken from the data', ...
                "ButtonPushedFcn", @(~, ~) this.setColorLimit([]));
        end

        function key = currentSortKey(this)
        %CURRENTSORTKEY  The chosen entry of SortKeys, or [] for recording order.
            key = [];
            if isempty(this.SortDropdown) || ~isvalid(this.SortDropdown)
                return;
            end
            index = this.SortDropdown.Value;
            if index >= 1 && index <= numel(this.SortKeys)
                key = this.SortKeys(index);
            end
        end

        function drawSortLine(this, key)
        %DRAWSORTLINE  Each row's sort value across the image, when it is a
        %   time after the event; nothing otherwise, since a pupil size or a
        %   position has no place on a time axis.
            if isempty(key) || ~key.timeMs
                set(this.SortLine, "XData", NaN, "YData", NaN);
                return;
            end
            x = key.values(this.TrialOrder);
            set(this.SortLine, "XData", x, "YData", 1:numel(x));
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

    methods
        function setColorLimit(this, limit)
        %SETCOLORLIMIT  Colour scale of the shown channel's group: -LIMIT to
        %   +LIMIT, or the automatic scale when LIMIT is empty ("Auto").
            group = this.ChannelGroup{this.Channel};
            if isempty(limit) || ~isfinite(limit) || limit <= 0
                limit = this.AutoColorLimit(group);
            end
            this.GroupColorLimit(group) = limit;
            this.redraw();
        end

        function focus = currentFocus(this)
        %CURRENTFOCUS  The channel this view is showing, by label, and the
        %   bin when one is shown alone. "All trials" reports no bin, which
        %   leaves the one remembered from another view as it was.
            focus = struct();
            if this.Channel >= 1 && this.Channel <= numel(this.Labels)
                focus.Channel = char(string(this.Labels{this.Channel}));
            end
            if this.SelectedBin > 0
                focus.Bin = this.binLabel(this.SelectedBin);
            end
        end

        function applyFocus(this, focus)
        %APPLYFOCUS  Show FOCUS.Channel, and FOCUS.Bin alone, where this
        %   dataset has them, as the other views with a bin choice do.
            if ~isstruct(focus)
                return;
            end
            changed = false;
            if isfield(focus, 'Channel') && ~isempty(this.Labels)
                idx = ViewFocus.indexOfLabel(this.Labels, focus.Channel);
                if ~isempty(idx) && idx ~= this.Channel
                    this.Channel = idx;
                    changed = true;
                end
            end
            if isfield(focus, 'Bin') && ~isempty(this.BinChoices)
                k = ViewFocus.indexOfLabel(this.binLabels(), focus.Bin);
                if ~isempty(k) && this.BinChoices(k) ~= this.SelectedBin
                    this.SelectedBin = this.BinChoices(k);
                    this.BinDropdown.Value = k + 1;
                    changed = true;
                end
            end
            if changed
                this.redraw();
            end
        end
    end

    methods (Access = private)
        function labels = binLabels(this)
        %BINLABELS  The labels of the bins "Bin:" offers, in its order.
            labels = arrayfun(@(b) this.binLabel(b), this.BinChoices, 'UniformOutput', false);
        end

        function label = binLabel(this, position)
            label = char(string(this.EEG.bindesc(position).label));
        end
    end

    methods (Static)
        function positions = selectableBins(EEG)
        %SELECTABLEBINS  The bins "Bin:" offers, as positions in
        %   EEG.bindesc: every ordinary bin that holds a trial. A combination
        %   (difference) bin has no trials of its own to show.
            positions = zeros(1, 0);
            if ~isfield(EEG, 'bindesc') || isempty(EEG.bindesc)
                return;
            end
            for b = 1:numel(EEG.bindesc)
                isCombo = isfield(EEG.bindesc, 'combo') && ~isempty(EEG.bindesc(b).combo);
                if ~isCombo && ~isempty(TransTools.BinTrials(EEG, b))
                    positions(end + 1) = b; %#ok<AGROW>
                end
            end
        end

        function lim = robustColorLimit(data)
        %ROBUSTCOLORLIMIT  The automatic colour scale: the 98th percentile of
        %   the absolute amplitude in DATA, rather than its maximum, which the
        %   one largest sample (a blink, a drift, an unrejected artefact) set
        %   for everything else. Read from at most a million evenly spaced
        %   samples, which is as good for a percentile and stays quick on a
        %   long recording's worth of trials. 1 when there is nothing to scale
        %   by (all zero or all NaN), so the scale is never empty.
            step = max(1, floor(numel(data) / 1e6));
            values = abs(double(data(1:step:end)));
            values = sort(values(isfinite(values)));
            lim = 1;
            if isempty(values)
                return;
            end
            candidate = values(max(1, ceil(0.98 * numel(values))));
            if candidate <= 0
                candidate = values(end);    % mostly zeros: fall back on the largest
            end
            if candidate > 0
                lim = candidate;
            end
        end

        function order = sortWithinGroups(order, keys, values, descending)
        %SORTWITHINGROUPS  ORDER (trial per row) sorted by VALUES(trial),
        %   ascending, or descending when DESCENDING is true, within each run
        %   of equal KEYS (bin per row), so a grouped image keeps its groups.
        %   Stable, so ties keep recording order, and NaN last in either
        %   direction, so trials without a value collect at the bottom of
        %   their group instead of scattering through it.
            if nargin < 4
                descending = false;
            end
            direction = 'ascend';
            if descending
                direction = 'descend';
            end
            if isempty(order)
                return;
            end
            starts = [1, find(diff(keys) ~= 0) + 1];
            stops = [starts(2:end) - 1, numel(keys)];
            for g = 1:numel(starts)
                span = starts(g):stops(g);
                [~, at] = sort(values(order(span)), direction, 'MissingPlacement', 'last');
                order(span) = order(span(at));
            end
        end
    end
end
