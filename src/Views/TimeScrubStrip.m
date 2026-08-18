classdef TimeScrubStrip < handle
%TIMESCRUBSTRIP  The bin-dropdown + "t = ... ms" readout + Play-button/
%   slider scaffolding ScalpDistributionView and Brain3DView both build
%   below their single plot. Previously duplicated ~150 lines between the
%   two (already drifted: a dead PlayFrameSeconds constant survived in
%   one, was dropped from the other); consolidated here.
%
%   A dumb UI component, not a state owner: BINLABELS/TIMES are read once
%   at construction (to size the dropdown/slider), but which bin/instant
%   is currently selected stays the OWNING view's own business, tracked in
%   its own SelectedBin property exactly as before this consolidation.
%   Every user action here (drag the slider, press Play, switch the bin
%   dropdown) is reported back to the owner via the callbacks passed into
%   the constructor, the same closure-callback pattern ZoomPanButtons uses
%   for FourierView/SpectralMeasureView's zoom/pan row:
%     ACTIVATEDFCN()        -- called before every action below, mirroring
%                               the owning view's own notifyActivated
%     REDRAWFCN(t)          -- called whenever the drawn instant should
%                               change (slider drag/release, a Play frame,
%                               or after a bin switch at the slider's
%                               current position)
%     ONBINCHANGEDFCN(idx)  -- called (before REDRAWFCN) when the bin
%                               dropdown changes, for anything view-
%                               specific a bin switch needs beyond
%                               redrawing (ScalpDistributionView updates
%                               its axes title there; Brain3DView's mesh
%                               has no separate title, so passes []).
%   The initial draw is NOT triggered from inside this constructor: the
%   owning view calls REDRAWFCN itself once construction returns (see
%   ScalpDistributionView/Brain3DView), since a callback fired mid-
%   construction here would run before the owning view has finished
%   assigning its own Strip property, or (for Brain3DView) before its
%   Mesh/Axes are otherwise ready.
%
%   Built into GRID at DROPDOWNROW (used only when NUMEL(BINLABELS) > 1;
%   column 1), LABELROW and SLIDERROW (both spanning columns [1, 2]) --
%   the caller's own plot axes/colorbar rows sit around this range; see
%   ScalpDistributionView/Brain3DView's own constructors for the full grid
%   layout each one builds.
%
%   See also SCALPDISTRIBUTIONVIEW, BRAIN3DVIEW, ZOOMPANBUTTONS.

    properties (SetAccess = private)
        BinDropdown     % uidropdown, only built when numel(binLabels) > 1
        TimeLabel       % "t = ... ms" readout above the slider
        Slider          % uislider spanning times(1):times(end)
        PlayButton      % uibutton, just left of the slider -- see onPlay
    end

    properties (Access = private)
        Times
        ActivatedFcn
        RedrawFcn
        OnBinChangedFcn
    end

    properties (Constant, Access = private)
        PlayMaxFrames = 60   % subsample above this many samples in range, for a snappy animation on high-rate data
    end

    methods
        function this = TimeScrubStrip(grid, dropdownRow, labelRow, sliderRow, ...
                binLabels, times, activatedFcn, redrawFcn, onBinChangedFcn)
            this.Times           = times;
            this.ActivatedFcn    = activatedFcn;
            this.RedrawFcn       = redrawFcn;
            this.OnBinChangedFcn = onBinChangedFcn;

            if numel(binLabels) > 1
                this.BinDropdown = TransTools.BuildBinDropdown(grid, dropdownRow, 1, ...
                    binLabels, @(idx) this.onBinChanged(idx));
            end

            this.TimeLabel = uilabel(grid, "HorizontalAlignment", "center", "FontWeight", "bold");
            this.TimeLabel.Layout.Row = labelRow;
            this.TimeLabel.Layout.Column = [1, 2];

            % Round the slider's own end-to-end range to the nearest 5 ms
            % (on request) -- times(1)/(end) are themselves rarely round
            % numbers (e.g. -197.5 ms, wherever the nearest sample happens
            % to land), and Limits drives both the draggable range and
            % (via MajorTicks below) the printed tick labels, so rounding
            % it once here keeps both consistent. The owning view's own
            % redraw() always maps whatever Value the slider lands on to
            % the nearest real sample in its own times array, so a Limits
            % endpoint that rounds a few ms past the true data edge is
            % harmless -- it just clamps to the nearest real edge sample
            % instead of erroring or leaving a gap.
            roundTo5 = @(t) round(t / 5) * 5;
            sliderMin = roundTo5(times(1));
            sliderMax = roundTo5(times(end));

            % The Play button sits just left of the slider, in its own
            % narrow fixed-width column -- a nested 2-column grid inside
            % this one cell (rather than adding a column to GRID itself)
            % so the caller's own axes/colorbar columns, and the
            % TimeLabel row's own span, are untouched.
            sliderGrid = uigridlayout(grid, [1, 2], ...
                "ColumnWidth", {28, '1x'}, "Padding", [0 0 0 0], "ColumnSpacing", 4);
            sliderGrid.Layout.Row = sliderRow;
            sliderGrid.Layout.Column = [1, 2];

            this.PlayButton = uibutton(sliderGrid, "Text", char(9654), ... % U+25B6 "black right-pointing triangle"
                "Tooltip", "Play through the time range once", ...
                "ButtonPushedFcn", @(~, ~) this.onPlay());
            this.PlayButton.Layout.Column = 1;

            this.Slider = uislider(sliderGrid, "Limits", [sliderMin, sliderMax]);
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
        end

        function onWheel(this, callbackData)
        %ONWHEEL  Scroll the mouse wheel to scrub the slider one real
        %   sample forward/back -- the same "step through the underlying
        %   data one unit at a time" convention EpochView/TimeFrequencyView
        %   use for channels, applied here to time (positive
        %   VerticalScrollCount, i.e. scrolling down, steps forward, the
        %   same direction convention those views use for downarrow).
        %   Public: the owning view's own onWheel (dispatched centrally by
        %   Alakazam.dispatchWheel) forwards straight to this.
            [~, idx] = min(abs(this.Times - this.Slider.Value));
            if callbackData.VerticalScrollCount > 0
                idx = min(numel(this.Times), idx + 1);
            else
                idx = max(1, idx - 1);
            end
            % Slider.Limits is times(1)/(end) rounded to the nearest 5
            % (see the constructor), which can land just inside the true
            % data range -- clamp into Limits so an edge sample never
            % throws a "Value must be within Limits" error. The owning
            % view's redraw() always snaps back to the nearest real sample
            % regardless, so this clamp does not change which sample ends
            % up drawn.
            newT = min(max(this.Times(idx), this.Slider.Limits(1)), this.Slider.Limits(2));
            this.Slider.Value = newT;
            this.onSlide(newT);
        end
    end

    methods (Access = private)
        function fireActivated(this)
        %FIREACTIVATED  Call ActivatedFcn, if set. Named to avoid colliding
        %   with handle's own built-in, PUBLIC notify() method: a private
        %   method here named notify() is a real MATLAB class-definition
        %   error ("uses different access permissions than its
        %   superclass"), not just a style clash -- confirmed the hard
        %   way, it broke construction of every view built on this class
        %   (ScalpDistributionView, Brain3DView) outright.
            if ~isempty(this.ActivatedFcn)
                this.ActivatedFcn();
            end
        end

        function onSlide(this, t)
        %ONSLIDE  uislider ValueChangingFcn/ValueChangedFcn target.
            this.fireActivated();
            this.RedrawFcn(t);
        end

        function onBinChanged(this, binIdx)
        %ONBINCHANGED  BinDropdown ValueChangedFcn target: report the new
        %   bin to the owner (OnBinChangedFcn, for anything view-specific,
        %   e.g. a title update) before redrawing at the slider's current
        %   position.
            this.fireActivated();
            if ~isempty(this.OnBinChangedFcn)
                this.OnBinChangedFcn(binIdx);
            end
            this.RedrawFcn(this.Slider.Value);
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
        %   pending callbacks, not just graphics) is what lets that Close
        %   happen at all while this loop is running.
        %
        %   Subsamples to at most PlayMaxFrames evenly-spaced samples
        %   across the range (a several-hundred-sample epoch at a high
        %   sample rate would otherwise mean hundreds of real redraws --
        %   each a genuine interpolated/projected render, not a cheap line
        %   redraw -- making "once" take far longer than a quick,
        %   watchable pass).
        %
        %   Restores the slider (and the drawn instant) to wherever it was
        %   before playing, once the animation ends by any path -- see
        %   restoreSliderValue -- so Play previews the whole range as a
        %   one-off without permanently losing your place.
            this.fireActivated();
            startT = this.Slider.Value;
            inRange = find(this.Times >= this.Slider.Limits(1) & this.Times <= this.Slider.Limits(2));
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
                t = this.Times(idx);
                this.Slider.Value = min(max(t, this.Slider.Limits(1)), this.Slider.Limits(2));
                this.RedrawFcn(t);
                drawnow;
            end
        end

        function restoreSliderValue(this, t)
        %RESTORESLIDERVALUE  onPlay's onCleanup target: put the slider
        %   (and the drawn instant) back to T -- wherever it was before
        %   Play was pressed -- once the animation ends, by any path.
        %   Guarded the same way as reenablePlayButton, since the slider
        %   may no longer exist if the tab was closed mid-animation.
            if isvalid(this.Slider)
                this.Slider.Value = t;
                this.RedrawFcn(t);
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
end
