classdef CrossCorrelationView < AlakazamView
%CROSSCORRELATIONVIEW  One channel's averaged cross-correlation to the
%   reference, as r against lag, with channel and bin dropdowns.
%
%   Draws the Fisher-z-averaged correlation with a +/-1 SE band around it,
%   a marker at the peak, and a dashed line at lag zero. Three things are
%   deliberate:
%
%   THE BAND, not just the line. CrossCorrelation averages in Fisher-z
%   precisely so a standard error exists; drawing the line alone would
%   throw away the one thing that says whether a bump is worth looking at.
%   The band is computed in z and mapped back through tanh, so it is
%   asymmetric in r near +/-1 -- which is correct, and is what a band drawn
%   naively in r would get wrong.
%
%   THE LAG-ZERO LINE, because the whole reading of the plot is "which side
%   of zero is the peak on". Without it the sign has to be read off the
%   axis ticks, which is exactly the mistake the transform's own header
%   warns about.
%
%   THE AXES ARE FIXED TO [-1, 1]. Autoscaling r makes a weak, noisy
%   correlation look as convincing as a strong one -- the reader has no cue
%   that the y-axis just shrank to +/-0.05. A correlation has a natural
%   full scale and this uses it.
%
%   See also ALAKAZAMPLOTTER, CROSSCORRELATION.

    properties (SetAccess = private)
        Figure
        EEG
        Grid
        Axes
        ChannelLabels
        BinLabels
        SelectedChannel
        SelectedBin
        ChannelDropdown
        BinDropdown
    end

    methods
        function this = CrossCorrelationView(fig, eeg)
            this.Figure = fig;
            this.EEG    = eeg;
            this.ChannelLabels = eeg.xcorrLabels;
            this.BinLabels     = eeg.xcorrBinLabels;
            this.SelectedBin     = 1;
            this.SelectedChannel = firstNonReference(eeg);

            hasBins = numel(this.BinLabels) > 1;
            this.Grid = uigridlayout(fig, [2, 2 + double(hasBins)], ...
                "RowHeight", {26, '1x'}, ...
                "ColumnWidth", [{90, '1x'}, repmat({160}, 1, double(hasBins))], ...
                "Padding", [4 4 4 4]);

            uilabel(this.Grid, "Text", "  Channel", "HorizontalAlignment", "right");
            this.ChannelDropdown = uidropdown(this.Grid, ...
                "Items", this.ChannelLabels, "ItemsData", 1:numel(this.ChannelLabels), ...
                "Value", this.SelectedChannel, ...
                "ValueChangedFcn", @(src, ~) this.onChannelChanged(src.Value));

            if hasBins
                this.BinDropdown = TransTools.BuildBinDropdown(this.Grid, 1, 3, ...
                    this.BinLabels, @(idx) this.onBinChanged(idx));
            end

            this.Axes = uiaxes(this.Grid);
            this.Axes.Layout.Row = 2;
            this.Axes.Layout.Column = [1, 2 + double(hasBins)];
            this.Axes.ButtonDownFcn = @(~, ~) this.notifyActivated();
            axtoolbar(this.Axes, "default");

            this.redraw();
        end
    end

    methods (Access = private)
        function redraw(this)
            eeg = this.EEG;
            ax  = this.Axes;
            c   = this.SelectedChannel;
            b   = this.SelectedBin;
            cla(ax);

            lags = eeg.xcorrLags;
            r    = squeeze(eeg.xcorr(c, :, b));
            if all(~isfinite(r))
                axis(ax, 'off');
                title(ax, sprintf('%s (nothing estimated in this bin)', this.ChannelLabels{c}));
                return;
            end

            hold(ax, 'on');

            % The SE band, computed in z and mapped back: asymmetric in r,
            % which is the honest shape.
            se = squeeze(eeg.xcorrSE(c, :, b));
            if any(isfinite(se))
                z = atanh(min(1 - 1e-12, max(-1 + 1e-12, r)));
                loR = tanh(z - se);
                hiR = tanh(z + se);
                ok = isfinite(loR) & isfinite(hiR);
                if any(ok)
                    fill(ax, [lags(ok), fliplr(lags(ok))], [loR(ok), fliplr(hiR(ok))], ...
                        [0.29 0.50 0.79], 'FaceAlpha', 0.18, 'EdgeColor', 'none');
                end
            end

            plot(ax, [0 0], [-1 1], '--', 'Color', [0.6 0.6 0.6]);
            plot(ax, lags, r, '-', 'Color', [0.29 0.50 0.79], 'LineWidth', 1.4);

            peakR = eeg.xcorrPeakR(c, b);
            peakLag = eeg.xcorrPeakLagMs(c, b);
            if isfinite(peakR)
                plot(ax, peakLag, peakR, 'o', 'MarkerSize', 6, ...
                    'MarkerEdgeColor', [0.69 0.24 0.22], 'MarkerFaceColor', 'none');
            end

            hold(ax, 'off');
            ylim(ax, [-1 1]);
            if numel(lags) > 1
                xlim(ax, [lags(1), lags(end)]);
            end
            grid(ax, 'on');
            xlabel(ax, sprintf('Lag (ms) -- positive: %s follows %s', ...
                this.ChannelLabels{c}, eeg.xcorrRef));
            ylabel(ax, 'r');
            title(ax, this.titleFor(c, b));
        end

        function text = titleFor(this, c, b)
            eeg = this.EEG;
            text = sprintf('%s vs %s  |  %s  (%d trials)', ...
                this.ChannelLabels{c}, eeg.xcorrRef, ...
                char(string(this.BinLabels{b})), eeg.xcorrTrials(b));
            if isfinite(eeg.xcorrPeakR(c, b))
                text = sprintf('%s  |  peak r = %+.3f at %+g ms', ...
                    text, eeg.xcorrPeakR(c, b), eeg.xcorrPeakLagMs(c, b));
            end
        end

        function onChannelChanged(this, idx)
            this.notifyActivated();
            this.SelectedChannel = idx;
            this.redraw();
        end

        function onBinChanged(this, idx)
            this.notifyActivated();
            this.SelectedBin = idx;
            this.redraw();
        end
    end

    methods
        function focus = currentFocus(this)
            focus = struct();
            if ~isempty(this.SelectedBin) && this.SelectedBin <= numel(this.BinLabels)
                focus.Bin = char(string(this.BinLabels{this.SelectedBin}));
            end
            if ~isempty(this.SelectedChannel) && this.SelectedChannel <= numel(this.ChannelLabels)
                focus.Channel = char(string(this.ChannelLabels{this.SelectedChannel}));
            end
        end

        function applyFocus(this, focus)
            if ~isstruct(focus)
                return;
            end
            if isfield(focus, 'Bin') && ~isempty(this.BinLabels)
                idx = ViewFocus.indexOfLabel(this.BinLabels, focus.Bin);
                if ~isempty(idx) && ~isequal(idx, this.SelectedBin)
                    this.onBinChanged(idx);
                    if ~isempty(this.BinDropdown) && isvalid(this.BinDropdown)
                        this.BinDropdown.Value = idx;
                    end
                end
            end
            if isfield(focus, 'Channel') && ~isempty(this.ChannelLabels)
                idx = ViewFocus.indexOfLabel(this.ChannelLabels, focus.Channel);
                if ~isempty(idx) && ~isequal(idx, this.SelectedChannel)
                    this.onChannelChanged(idx);
                    if ~isempty(this.ChannelDropdown) && isvalid(this.ChannelDropdown)
                        this.ChannelDropdown.Value = idx;
                    end
                end
            end
        end
    end
end

% ======================================================================= %
function c = firstNonReference(eeg)
%FIRSTNONREFERENCE  Open on a channel that says something: the reference
%   against itself is r = 1 at lag 0 by construction, which is a fine
%   alignment check and a poor first impression.
    c = 1;
    for k = 1:numel(eeg.xcorrLabels)
        if ~strcmpi(eeg.xcorrLabels{k}, eeg.xcorrRef)
            c = k;
            return;
        end
    end
end
