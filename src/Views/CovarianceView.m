classdef CovarianceView < AlakazamView
%COVARIANCEVIEW  One channel-by-channel covariance (or correlation) matrix,
%   with a bin dropdown when there is more than one bin.
%
%   Drawn as a heatmap on a signed, zero-centred colour scale (the app's
%   shared TransTools.DivergingColormap), because a covariance entry's SIGN
%   is the interesting half: blue and red either side of white say
%   "anticorrelated" and "correlated" at a glance in a way a sequential map
%   cannot. Correlation is drawn on a fixed [-1, 1] scale so two bins are
%   directly comparable; covariance, whose units are uV^2 and whose range
%   depends entirely on the montage and window, is scaled symmetrically to
%   its own largest magnitude.
%
%   The title carries what the matrix cannot show: how many observations it
%   was estimated from, and how hard the shrinkage had to work. A matrix
%   from 40 trials and one from 4 look equally smooth as a picture and are
%   not equally trustworthy, so the numbers travel with the plot rather
%   than living only in the console.
%
%   Channel ticks are thinned rather than dropped when there are many
%   channels: every label on a 64-channel matrix is unreadable, and no
%   labels at all makes the picture unusable for finding a specific pair.
%
%   See also ALAKAZAMPLOTTER, COVARIANCE, TRANSTOOLS.DIVERGINGCOLORMAP.

    properties (SetAccess = private)
        Figure
        EEG
        Grid
        Axes
        BinLabels
        SelectedBin
        BinDropdown
    end

    methods
        function this = CovarianceView(fig, eeg)
            this.Figure = fig;
            this.EEG    = eeg;

            this.BinLabels = eeg.covBinLabels;
            this.SelectedBin = firstUsableBin(eeg);

            hasDropdown = numel(this.BinLabels) > 1;
            dropdownRows = double(hasDropdown);

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

            % After the first redraw, matching CoherenceTopographyView's own
            % ordering (see its constructor comment).
            TransTools.AddSharedColorbar(this.Grid, axRow, 2, TransTools.DivergingColormap(), ...
                this.colourLimits(), this.EEG.covStatistic);
        end
    end

    methods (Access = private)
        function lim = colourLimits(this)
        %COLOURLIMITS  [-1 1] for correlation (comparable across bins), or
        %   symmetric about zero at the largest magnitude for covariance.
            if strcmpi(this.EEG.covStatistic, 'correlation')
                lim = [-1, 1];
                return;
            end
            m = max(abs(this.EEG.covariance(:)), [], 'omitnan');
            if isempty(m) || ~isfinite(m) || m <= 0
                m = 1;
            end
            lim = [-m, m];
        end

        function redraw(this)
            eeg = this.EEG;
            ax  = this.Axes;
            b   = this.SelectedBin;
            cla(ax);

            if isempty(b) || b < 1 || b > size(eeg.covariance, 3)
                axis(ax, 'off');
                title(ax, 'No matrix to show');
                return;
            end

            S = eeg.covariance(:, :, b);
            if all(~isfinite(S(:)))
                axis(ax, 'off');
                title(ax, sprintf('%s (not estimated: too few observations)', ...
                    char(string(this.BinLabels{b}))));
                return;
            end

            imagesc(ax, S);
            colormap(ax, TransTools.DivergingColormap());
            ax.CLim = this.colourLimits();
            axis(ax, 'image');

            labels = eeg.covLabels;
            n = numel(labels);
            % Thin the ticks to at most ~20 so they stay readable, but never
            % to none -- the labels are how a pair is found.
            step = max(1, ceil(n / 20));
            ticks = 1:step:n;
            ax.XTick = ticks; ax.YTick = ticks;
            ax.XTickLabel = labels(ticks); ax.YTickLabel = labels(ticks);
            ax.XTickLabelRotation = 90;

            title(ax, this.titleFor(b));
        end

        function text = titleFor(this, b)
        %TITLEFOR  Bin label plus the two numbers that say how much to trust
        %   the picture: observations behind it, and the shrinkage applied.
            eeg = this.EEG;
            text = sprintf('%s  (n = %d obs', char(string(this.BinLabels{b})), eeg.covN(b));
            if isfield(eeg, 'covDropped') && eeg.covDropped(b) > 0
                text = sprintf('%s, %d dropped', text, eeg.covDropped(b));
            end
            if isfield(eeg, 'covShrinkage') && isfinite(eeg.covShrinkage(b)) && eeg.covShrinkage(b) > 0
                text = sprintf('%s, shrinkage %.2f', text, eeg.covShrinkage(b));
            end
            text = [text ')'];
        end

        function onBinChanged(this, binIdx)
            this.notifyActivated();
            this.SelectedBin = binIdx;
            this.redraw();
        end
    end

    methods
        function focus = currentFocus(this)
            focus = struct();
            if ~isempty(this.SelectedBin) && this.SelectedBin >= 1 && ...
                    this.SelectedBin <= numel(this.BinLabels)
                focus.Bin = char(string(this.BinLabels{this.SelectedBin}));
            end
        end

        function applyFocus(this, focus)
            if ~isstruct(focus) || ~isfield(focus, 'Bin') || isempty(this.BinLabels)
                return;
            end
            idx = ViewFocus.indexOfLabel(this.BinLabels, focus.Bin);
            if isempty(idx) || isequal(idx, this.SelectedBin)
                return;
            end
            this.onBinChanged(idx);
            if ~isempty(this.BinDropdown) && isvalid(this.BinDropdown)
                this.BinDropdown.Value = idx;
            end
        end
    end
end

% ======================================================================= %
function b = firstUsableBin(eeg)
%FIRSTUSABLEBIN  Open on a bin that actually has a matrix: a combination
%   bin owns no trials of its own, so its slice is all NaN, and opening on
%   an empty plot reads as a broken transform rather than an empty bin.
    b = 1;
    for k = 1:size(eeg.covariance, 3)
        if any(isfinite(eeg.covariance(:, :, k)), 'all')
            b = k;
            return;
        end
    end
end
