classdef ZoomPanButtons < handle
%ZOOMPANBUTTONS  The zoom/pan push-button row (+ optional step buttons)
%   FourierView and SpectralMeasureView both build at the bottom of their
%   grid: "+"/"-" zoom x, "^"/"v" zoom y, "<"/">" pan x (all clamped to
%   [0, Nyquist]), plus an optional trailing "<<"/">>" pair that steps
%   whatever secondary dimension the owning view has (trial for
%   FourierView, bin for SpectralMeasureView) via STEPFCN. Previously
%   duplicated near-identically (addButtons/onButtonPushed/zoomX/zoomY/
%   panX) between the two views; consolidated here.
%
%   AX and NYQUIST are captured once at construction, not read live from
%   the owning view on every button press: both are fixed for the whole
%   life of either current caller (neither ever reassigns its own Axes or
%   swaps in a different EEG after construction).
%
%   See also FOURIERVIEW, SPECTRALMEASUREVIEW.

    properties (Access = private)
        Axes
        Nyquist        % upper x-limit clamp (EEG.srate / 2)
        ActivatedFcn   % function handle (), or empty
    end

    methods
        function this = ZoomPanButtons(grid, row, ax, nyquist, activatedFcn, stepFcn)
        %ZOOMPANBUTTONS  Build the button row into GRID's ROW.
        %   ACTIVATEDFCN(), if non-empty, is called before every button's
        %   own action (mirroring the owning view's own notifyActivated).
        %   STEPFCN(delta), if given and non-empty, adds the trailing
        %   "<<"/">>" pair calling STEPFCN(-1)/STEPFCN(1); omit (or pass
        %   empty) to build only the six zoom/pan buttons.
            this.Axes = ax;
            this.Nyquist = nyquist;
            this.ActivatedFcn = activatedFcn;

            labels    = {"+", "-", "^", "v", "<", ">"};
            callbacks = {@() this.zoomX(0.5), @() this.zoomX(2), @() this.zoomY(0.5), ...
                         @() this.zoomY(2), @() this.panX(-1), @() this.panX(1)};
            if nargin >= 6 && ~isempty(stepFcn)
                labels    = [labels, {"<<", ">>"}];
                callbacks = [callbacks, {@() stepFcn(-1), @() stepFcn(1)}];
            end
            n = numel(labels);
            btnGrid = uigridlayout(grid, [1, n + 1], "Padding", [0 0 0 0], ...
                "ColumnWidth", [repmat({30}, 1, n), {'1x'}], "ColumnSpacing", 4);
            btnGrid.Layout.Row = row;
            for i = 1:n
                b = uibutton(btnGrid, "Text", labels{i}, ...
                    "ButtonPushedFcn", @(~, ~) this.onButtonPushed(callbacks{i}));
                b.Layout.Column = i;
            end
        end
    end

    methods (Access = private)
        function onButtonPushed(this, callback)
        %ONBUTTONPUSHED  A zoom/pan/step button was pushed: mark the owning
        %   view activated (via ActivatedFcn) before running its callback.
            if ~isempty(this.ActivatedFcn)
                this.ActivatedFcn();
            end
            callback();
        end

        function zoomX(this, factor)
        %ZOOMX  Scale the x range about its left edge (factor < 1 zooms in).
            span = xlim(this.Axes);
            newHigh = span(1) + (span(2) - span(1)) * factor;
            if factor > 1
                newHigh = min(newHigh, this.Nyquist);
            end
            xlim(this.Axes, [span(1), newHigh]);
        end

        function zoomY(this, factor)
        %ZOOMY  Scale the y range about its bottom edge.
            span = ylim(this.Axes);
            ylim(this.Axes, [span(1), span(1) + (span(2) - span(1)) * factor]);
        end

        function panX(this, direction)
        %PANX  Shift the x range by a tenth of its width, clamped to [0, Nyquist].
            span = xlim(this.Axes);
            shifted = span + direction * (span(2) - span(1)) / 10;
            if shifted(1) < 0
                shifted = shifted - shifted(1);
            end
            if shifted(2) > this.Nyquist
                shifted = shifted - (shifted(2) - this.Nyquist);
            end
            xlim(this.Axes, shifted);
        end
    end
end
