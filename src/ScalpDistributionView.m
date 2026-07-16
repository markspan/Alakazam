classdef ScalpDistributionView < handle
%SCALPDISTRIBUTIONVIEW  Grid of per-bin scalp topographies, scrubbable by time.
%
%   Draws one topography tile per bin (up to 3 per row, wrapping to a new
%   row -- the same tiling convention TimeFrequencyView/AverageView use),
%   via TransTools.DrawScalpMap (a uiaxes-compatible port of EEGLAB's
%   topoplot(), see its own header comment for why a port was needed at
%   all). A uislider along the bottom scrubs through the dataset's time
%   range; every tile redraws live while dragging (uislider's
%   ValueChangingFcn fires continuously during the drag itself, not just
%   on release -- the uifigure-native equivalent of the PostSet-listener
%   trick the previous classic-uicontrol-slider version needed, and
%   arguably simpler).
%
%   Only draws the bins currently ticked on in this dataset's own Average
%   plot (its AverageView tickboxes), if that tab happens to be open --
%   found by walking this tab's own tabgroup siblings for one tagged with
%   the same EEG.File, exactly the way AlakazamPlotter/Alakazam.overlayAverage
%   locate a sibling tab. Falls back to every bin if that tab is not open,
%   its bin count no longer matches this dataset, or every bin happens to
%   be unticked (a softer fallback than the previous pure-plot version's
%   own hard error for the "every bin unticked" case: this result is now a
%   real, persisted tree node that can be reopened at any time, including
%   after every bin has since been unticked elsewhere, so showing
%   everything is friendlier than refusing to open at all).
%
%   Style follows the project standard.
%
%   See also ALAKAZAMPLOTTER, SCALPDISTRIBUTION, TRANSTOOLS.DRAWSCALPMAP,
%   TIMEFREQUENCYVIEW, AVERAGEVIEW.

    properties
        % Called (no args) when the user clicks a tile or the slider.
        % Wired by AlakazamPlotter to Alakazam.registerTileClick, so
        % keyboard/wheel shortcuts route to whichever tile was last
        % clicked while several are visible at once in Grid/Stack mode --
        % see Alakazam.dispatchKey/dispatchWheel and migration.md.
        % (ScalpDistributionView has no keyboard navigation -- but the
        % mouse wheel scrubs the time slider, see onWheel.)
        ActivatedFcn = function_handle.empty
    end

    properties (SetAccess = private)
        Figure          % owning uitab
        EEG             % averaged dataset (channels x samples[ x bins]) with .ScalpChanlocs/.ScalpHasPos/.ScalpMapLimit
        Grid            % (nRows+1) x nCols uigridlayout: bottom row the slider strip, rest tiles
        Axes            % 1 x nBins array of uiaxes, one per drawn bin
        BinIndices      % original EEG.data 3rd-dim index for each drawn tile
        TimeLabel       % "t = ... ms" readout above the slider
        Slider          % uislider spanning EEG.times(1):EEG.times(end)
        PlayButton      % uibutton, just left of the slider -- see onPlay
    end

    properties (Constant, Access = private)
        PlayMaxFrames    = 60    % subsample above this many samples in range, for a snappy animation on high-rate data
        PlayFrameSeconds = 0.04  % target pause between frames (on top of each frame's own render time)
    end

    methods
        function this = ScalpDistributionView(fig, eeg)
        %SCALPDISTRIBUTIONVIEW  Build the topography tile grid for EEG in FIG.
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

            selected = this.tickedBins(fig, eeg, nBinsTotal);
            this.BinIndices = find(selected);
            labels = labels(this.BinIndices);
            nBins = numel(this.BinIndices);

            nCols = min(3, nBins);
            nRows = ceil(nBins / nCols);

            % Key handling is wired by the shared Alakazam-level dispatcher
            % elsewhere for other views, but this one has none -- no
            % fig.KeyPressFcn needed here at all. Two extra rows below the
            % tile grid: a centred "t = ... ms" readout, then the slider
            % itself (uislider shows its own Limits as tick labels at
            % each end natively, so no separate flanking start/end labels
            % are needed the way the previous classic-uicontrol-slider
            % version had to build by hand). One extra, narrow trailing
            % column reserved for the shared colorbar -- see the dedicated
            % hidden axes built below for why it needs its own column
            % rather than sharing a tile's.
            this.Grid = uigridlayout(fig, [nRows + 2, nCols + 1], ...
                "RowHeight", [repmat({'1x'}, 1, nRows), {22}, {36}], ...
                "ColumnWidth", [repmat({'1x'}, 1, nCols), {56}], "Padding", [4 4 4 4]);

            this.Axes = gobjects(1, nBins);
            for b = 1:nBins
                row = ceil(b / nCols);
                col = mod(b - 1, nCols) + 1;
                ax = uiaxes(this.Grid);
                ax.Layout.Row = row;
                ax.Layout.Column = col; % 1..nCols always valid regardless of the extra colorbar column
                title(ax, labels{b}, "Interpreter", "none");
                ax.ButtonDownFcn = @(~, ~) this.notifyActivated();
                this.Axes(b) = ax;
            end

            this.TimeLabel = uilabel(this.Grid, "HorizontalAlignment", "center", "FontWeight", "bold");
            this.TimeLabel.Layout.Row = nRows + 1;
            this.TimeLabel.Layout.Column = this.spanColumns(nCols + 1);

            % Round the slider's own end-to-end range to the nearest 5 ms
            % (on request) -- eeg.times(1)/(end) are themselves rarely
            % round numbers (e.g. -197.5 ms, wherever the nearest sample
            % happens to land), and Limits drives both the draggable range
            % and (via MajorTicks below) the printed tick labels, so
            % rounding it once here keeps both consistent. redraw() always
            % maps whatever Value the slider lands on to the nearest real
            % sample in eeg.times (see its own min(abs(eeg.times-t))
            % lookup), so a Limits endpoint that rounds a few ms past the
            % true data edge is harmless -- it just clamps to the nearest
            % real edge sample instead of erroring or leaving a gap.
            roundTo5 = @(t) round(t / 5) * 5;
            sliderMin = roundTo5(eeg.times(1));
            sliderMax = roundTo5(eeg.times(end));

            % The Play button sits just left of the slider, in its own
            % narrow fixed-width column -- a nested 2-column grid inside
            % this one cell (rather than adding a column to this.Grid
            % itself) so the tile/colorbar columns above, and the
            % TimeLabel row's own span, are untouched.
            sliderRow = uigridlayout(this.Grid, [1, 2], ...
                "ColumnWidth", {28, '1x'}, "Padding", [0 0 0 0], "ColumnSpacing", 4);
            sliderRow.Layout.Row = nRows + 2;
            sliderRow.Layout.Column = this.spanColumns(nCols + 1);

            this.PlayButton = uibutton(sliderRow, "Text", char(9654), ... % U+25B6 "black right-pointing triangle"
                "Tooltip", "Play through the time range once", ...
                "ButtonPushedFcn", @(~, ~) this.onPlay());
            this.PlayButton.Layout.Column = 1;

            this.Slider = uislider(sliderRow, "Limits", [sliderMin, sliderMax]);
            this.Slider.Layout.Column = 2;
            % uislider's own default MajorTicks/MajorTickLabels are 5
            % evenly-spaced raw fractions of Limits -- pretty-print
            % instead: round tick values to whole ms, labelled to match.
            tickValues = round(linspace(sliderMin, sliderMax, 5));
            this.Slider.MajorTicks = tickValues;
            this.Slider.MajorTickLabels = arrayfun(@(t) sprintf('%.0f', t), tickValues, "UniformOutput", false);
            % uislider's MinorTicksMode defaults to "auto", which densely
            % auto-generates a minor tick mark roughly every Step (default
            % 1) between major ticks -- on a several-hundred-ms range that
            % is a wall of clutter with no individually-readable meaning.
            % Locking MinorTicks to empty only removes the visual marks;
            % it does not affect Step/Value at all, so every value in
            % between remains just as reachable by dragging as before.
            this.Slider.MinorTicksMode = "manual";
            this.Slider.MinorTicks = [];
            startTime = 0;
            if startTime < sliderMin || startTime > sliderMax
                startTime = sliderMin; % 0 is not inside this epoch's window
            end
            this.Slider.Value = startTime;
            this.Slider.ValueChangingFcn = @(~, event) this.onSlide(event.Value);
            this.Slider.ValueChangedFcn  = @(~, event) this.onSlide(event.Value);

            this.redraw(startTime);
            for b = 1:nBins
                axtoolbar(this.Axes(b), "default");
            end
            % One shared colorbar: every tile carries the same CLim
            % (DrawScalpMap.m is always called with this dataset's single
            % ScalpMapLimit). Deliberately NOT attached directly to one of
            % the real tiles (colorbar(this.Axes(...))) -- confirmed
            % directly that doing so shrinks that tile's own axes to make
            % room for it, and visibly worse here than a plain imagesc
            % tile would be: DrawScalpMap forces axis(ax,'square'), so
            % narrowing the axes to fit a colorbar also shrinks its
            % height to preserve the square aspect, making that one head
            % noticeably smaller than its siblings. Attached instead to a
            % dedicated, invisible axes in its own reserved grid column --
            % confirmed directly that every real tile's InnerPosition is
            % then completely unaffected by the colorbar's presence.
            colorbarAxes = uiaxes(this.Grid);
            colorbarAxes.Layout.Column = nCols + 1;
            if nRows > 1
                colorbarAxes.Layout.Row = [1, nRows];
            else
                colorbarAxes.Layout.Row = 1;
            end
            colorbarAxes.Visible = "off";
            colormap(colorbarAxes, TransTools.DivergingColormap()); % must match DrawScalpMap's own tile colormap
            colorbarAxes.CLim = [-eeg.ScalpMapLimit, eeg.ScalpMapLimit];
            cb = colorbar(colorbarAxes);
            cb.Label.String = "Amplitude (\muV)";
        end

        function redraw(this, t)
        %REDRAW  Show every drawn bin's scalp topography at the instant
        %   nearest T (ms). Called directly by the constructor and by
        %   onSlide (both the live-drag and release paths).
            eeg = this.EEG;
            [~, idx] = min(abs(eeg.times - t));
            this.TimeLabel.Text = sprintf('t = %.0f ms', eeg.times(idx));
            for b = 1:numel(this.Axes)
                values = eeg.data(eeg.ScalpHasPos, idx, this.BinIndices(b));
                TransTools.DrawScalpMap(this.Axes(b), values, eeg.ScalpChanlocs, eeg.ScalpMapLimit);
            end
        end

        function onWheel(this, callbackData)
        %ONWHEEL  Scroll the mouse wheel to scrub the time slider one real
        %   sample forward/back -- the same "step through the underlying
        %   data one unit at a time" convention EpochView/TimeFrequencyView
        %   already use for channels, applied here to time (positive
        %   VerticalScrollCount, i.e. scrolling down, steps forward, the
        %   same direction convention those views use for downarrow).
        %   Public: dispatched centrally by Alakazam.dispatchWheel for
        %   whichever tab is currently active.
            eeg = this.EEG;
            [~, idx] = min(abs(eeg.times - this.Slider.Value));
            if callbackData.VerticalScrollCount > 0
                idx = min(numel(eeg.times), idx + 1);
            else
                idx = max(1, idx - 1);
            end
            % Slider.Limits is eeg.times(1)/(end) rounded to the nearest 5
            % (see the constructor), which can land just inside the true
            % data range -- clamp into Limits so an edge sample never
            % throws a "Value must be within Limits" error. redraw()
            % always snaps back to the nearest real sample regardless, so
            % this clamp does not change which sample ends up drawn.
            newT = min(max(eeg.times(idx), this.Slider.Limits(1)), this.Slider.Limits(2));
            this.Slider.Value = newT;
            this.onSlide(newT);
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
        function onSlide(this, t)
        %ONSLIDE  uislider ValueChangingFcn/ValueChangedFcn target: mark
        %   this view activated (matching FourierView's onButtonPushed
        %   convention) and redraw at the dragged/released time.
            this.notifyActivated();
            this.redraw(t);
        end

        function onPlay(this)
        %ONPLAY  Play button callback: animate through the slider's whole
        %   [Limits(1), Limits(2)] range once, from the start, moving the
        %   slider and redrawing one frame at a time. A plain synchronous
        %   pause/drawnow loop, not a timer object -- this is a short,
        %   bounded "play once" animation with no need to keep running in
        %   the background once the callback returns, so there is no
        %   separate object lifetime to start/stop/clean up on tab close
        %   (unlike a timer, which would keep firing after the tab/figure
        %   is gone unless something explicitly stopped it first). If the
        %   tab is closed mid-animation, the isvalid guard below just ends
        %   the loop on its next iteration; drawnow (which processes
        %   pending callbacks, not just graphics) is what lets that
        %   Close happen at all while this loop is running.
        %
        %   Subsamples to at most PlayMaxFrames evenly-spaced samples
        %   across the range (a several-hundred-sample epoch at a high
        %   sample rate would otherwise mean hundreds of real topography
        %   redraws -- each a genuine EEGLAB-style interpolated render,
        %   not a cheap line redraw -- making "once" take far longer than
        %   a quick, watchable pass).
        %
        %   Restores the slider (and the drawn topography) to wherever it
        %   was before playing, once the animation ends by any path -- see
        %   restoreSliderValue -- so Play previews the whole range as a
        %   one-off without permanently losing your place.
            this.notifyActivated();
            eeg = this.EEG;
            startT = this.Slider.Value;
            inRange = find(eeg.times >= this.Slider.Limits(1) & eeg.times <= this.Slider.Limits(2));
            if numel(inRange) > this.PlayMaxFrames
                inRange = inRange(round(linspace(1, numel(inRange), this.PlayMaxFrames)));
            end
            if isempty(inRange)
                return;
            end

            this.PlayButton.Enable = "off";
            restoreButton   = onCleanup(@() this.reenablePlayButton());
            restorePosition = onCleanup(@() this.restoreSliderValue(startT));

            for idx = inRange
                if ~isvalid(this.Slider)
                    return; % the tab was closed mid-animation
                end
                t = eeg.times(idx);
                this.Slider.Value = min(max(t, this.Slider.Limits(1)), this.Slider.Limits(2));
                this.redraw(t);
                drawnow;
                pause(this.PlayFrameSeconds);
            end
        end

        function restoreSliderValue(this, t)
        %RESTORESLIDERVALUE  onPlay's onCleanup target: put the slider
        %   (and the drawn topography) back to T -- wherever it was before
        %   Play was pressed -- once the animation ends, by any path.
        %   Guarded the same way as reenablePlayButton, since the slider
        %   may no longer exist if the tab was closed mid-animation.
            if isvalid(this.Slider)
                this.Slider.Value = t;
                this.redraw(t);
            end
        end

        function reenablePlayButton(this)
        %REENABLEPLAYBUTTON  onPlay's onCleanup target: re-enable the Play
        %   button once the animation loop ends, by any path (ran to
        %   completion, or returned early because the tab was closed).
        %   Guarded the same way, since the button itself may no longer
        %   exist in that second case.
            if isvalid(this.PlayButton)
                this.PlayButton.Enable = "on";
            end
        end
    end

    methods (Access = private, Static)
        function selected = tickedBins(fig, eeg, nBinsTotal)
        %TICKEDBINS  Which of EEG's NBINSTOTAL bins to draw: the ones
        %   currently ticked on in this dataset's own AverageView tab, if
        %   one happens to be open as a sibling in the same tabgroup.
        %   Falls back to every bin if no such tab is open, its bin count
        %   no longer matches, or every bin is unticked.
        %
        %   Looked up by EEG.ScalpSourceFile (the parent Average dataset's
        %   own file, stashed by ScalpDistribution.m before
        %   Alakazam.persistResultNode overwrites EEG.File with this
        %   result's own new cache path), not EEG.File itself -- by the
        %   time this view is constructed, EEG.File no longer identifies
        %   the parent, only this persisted result.
            selected = true(1, nBinsTotal);
            if ~isfield(eeg, 'ScalpSourceFile')
                return;
            end
            tabGroup = fig.Parent;
            if isempty(tabGroup) || ~isprop(tabGroup, 'Children')
                return;
            end
            siblingTab = findobj(tabGroup.Children, 'flat', 'Tag', eeg.ScalpSourceFile);
            if isempty(siblingTab)
                return;
            end
            parentView = getappdata(siblingTab(1), 'AverageView');
            if isempty(parentView) || ~isvalid(parentView)
                return;
            end
            ownSeries = cellfun(@(s) strcmp(s.file, eeg.ScalpSourceFile), parentView.Series);
            if sum(ownSeries) ~= nBinsTotal
                return;
            end
            ticked = parentView.Visible(ownSeries);
            if any(ticked)
                selected = ticked;
            end
        end

        function col = spanColumns(nCols)
        %SPANCOLUMNS  A Layout.Column value spanning every column: a plain
        %   scalar 1 for a single-column grid (Layout.Column rejects
        %   [1 1] -- it requires a strictly increasing pair, or a
        %   scalar), [1 nCols] otherwise.
            if nCols > 1
                col = [1, nCols];
            else
                col = 1;
            end
        end
    end
end
