classdef AverageView < handle
%AVERAGEVIEW  View of trial-averaged data with error bands, one line per bin.
%
%   AverageView draws the per-channel trial average of an averaged dataset
%   together with a +/- 3 standard-error band. A bin-aware average (produced by
%   Average on a DefineBins dataset) is drawn as one labelled line per bin;
%   a plain average is a single line. Several averaged datasets can be overlaid
%   on the same axes (dragging one onto another calls addDataset), and a legend
%   identifies each line. It replaces the old Tools.plotEpochedTimeMultiAverage
%   function with a clean stateful class.
%
%   The up / down arrow keys step the displayed channel for every line at once.
%
%   Style follows the project standard.
%
%   See also ALAKAZAMPLOTTER, EPOCHVIEW, FOURIERVIEW.

    properties
        % Called (no args) when the user clicks this view's axes or toggles
        % a tickbox. Wired by AlakazamPlotter to Alakazam.registerTileClick,
        % so keyboard shortcuts route to whichever tile was last clicked
        % while several are visible at once in Grid/Stack mode -- see
        % Alakazam.dispatchKey and migration.md.
        ActivatedFcn = function_handle.empty
    end

    properties (SetAccess = private)
        Figure          % owning figure
        Grid            % 1x2 uigridlayout: axes | checkbox strip
        Axes            % axes the averages are drawn in
        CheckboxGrid    % uigridlayout the tickboxes stack into (right strip)
        Series          % flat cell array of per-line series structs
        Channel = 1     % channel shown for every line
        Visible         % logical row vector, one per series: line shown?
    end

    properties (Constant, Access = private)
        % Fixed per-line colours so a bin keeps its colour while stepping
        % electrodes: bin 1 red, bin 2 blue, then a stable palette.
        Palette = [ ...
            0.00 0.00 1.00;   % blue
            1.00 0.00 0.00;   % red
            0.00 0.55 0.00;   % green
            0.75 0.00 0.75;   % magenta
            0.00 0.55 0.55;   % teal
            0.85 0.55 0.00;   % orange
            0.00 0.00 0.00]   % black
    end

    methods
        function this = AverageView(fig, eeg)
        %AVERAGEVIEW  Build the view for an averaged dataset in FIG.
            this.Figure = fig;
            this.Grid   = uigridlayout(fig, [1 2], "ColumnWidth", {'7x', '3x'}, ...
                "Padding", [4 4 4 4]);
            this.Axes   = uiaxes(this.Grid);
            this.Axes.Layout.Column = 1;
            this.Axes.ButtonDownFcn = @(~, ~) this.notifyActivated();
            this.CheckboxGrid = uigridlayout(this.Grid, [1 1], "Padding", [0 0 0 0]);
            this.CheckboxGrid.Layout.Column = 2;
            this.Series  = this.prepare(eeg);
            this.Visible = true(1, numel(this.Series));
            % Key handling is wired by the shared Alakazam-level dispatcher
            % (Alakazam.dispatchKey), not a per-view fig.KeyPressFcn here:
            % every open dataset is now a uitab on one shared uifigure, so a
            % per-view KeyPressFcn would be overwritten by whichever view was
            % constructed last, breaking key navigation on every other open
            % tab.
            this.redraw();
            axtoolbar(this.Axes, "default");
        end

        function addDataset(this, eeg)
        %ADDDATASET  Overlay another averaged dataset (ignores duplicates by
        %   source file). EEG.id is just the transform name (e.g. "Average"
        %   for every averaged dataset in the tree), so it cannot identify
        %   *which* dataset this is; EEG.File is the unique cache path.
            newSeries = this.prepare(eeg);
            if isempty(newSeries)
                return;
            end
            existingFiles = cellfun(@(s) string(s.file), this.Series);
            if ~any(existingFiles == string(newSeries{1}.file))
                this.Series  = [this.Series, newSeries];
                this.Visible = [this.Visible, true(1, numel(newSeries))];
            end
            this.redraw();
        end

        function redraw(this)
        %REDRAW  Draw every visible line's channel average and +/- 3 SE band,
        %   plus the tickbox list (right of the axes) used to show/hide lines.
        %   Checked state lives in this.Visible, not in the tickboxes
        %   themselves, so it survives the delete+recreate below (e.g. an
        %   electrode step via the arrow keys leaves the ticks untouched).
            ax = this.Axes;
            % Remove ALL prior axes objects, including ones with hidden
            % handles (bands, patches, reference lines). cla only deletes
            % visible-handle children on older MATLAB, which otherwise pile up
            % on each redraw. The tickboxes live in their own grid cell (see
            % the constructor / buildCheckboxes), cleared there.
            delete(allchild(ax));
            hold(ax, "on");

            fileKeys = cellfun(@(s) string(s.file), this.Series);
            manyIds  = numel(unique(fileKeys)) > 1;   % overlaying > 1 dataset
            allNames = strings(1, numel(this.Series));
            for i = 1:numel(this.Series)
                s = this.Series{i};
                if manyIds; allNames(i) = sprintf('%s: %s', s.id, s.name); else; allNames(i) = s.name; end
            end

            ymin = inf; ymax = -inf;
            handles = gobjects(1, 0);   % mean line per VISIBLE series
            names   = strings(1, 0);
            showBand = AlakazamSettings.get('graphics', 'erpPlot', 'showConfInt');
            confN    = AlakazamSettings.get('graphics', 'erpPlot', 'confIntN');

            for i = 1:numel(this.Series)
                if ~this.Visible(i)
                    continue;
                end
                s = this.Series{i};
                ch = min(this.Channel, size(s.data, 1));

                % Force row vectors so the band arithmetic is unambiguous.
                meanCh = reshape(s.data(ch, :), 1, []);
                band   = confN * reshape(s.stErr(ch, :), 1, []);

                colour = this.Palette(mod(i - 1, size(this.Palette, 1)) + 1, :);
                line   = plot(ax, s.times, meanCh, "Color", colour, "LineWidth", 1.5);
                if showBand
                    plot(ax, s.times, meanCh + band, "Color", colour, "LineStyle", ":");
                    plot(ax, s.times, meanCh - band, "Color", colour, "LineStyle", ":");
                    patch(ax, [s.times, fliplr(s.times)], [meanCh + band, fliplr(meanCh - band)], ...
                        colour, "EdgeColor", "none", "FaceAlpha", 0.3);
                    lo = meanCh - band; hi = meanCh + band;
                else
                    lo = meanCh; hi = meanCh;
                end

                handles(end + 1) = line;      %#ok<AGROW>
                names(end + 1)   = allNames(i); %#ok<AGROW>
                ymin = min(ymin, min(lo, [], "omitnan"));
                ymax = max(ymax, max(hi, [], "omitnan"));
            end

            first = this.Series{1};
            ch = min(this.Channel, numel(first.labels));
            title(ax, "Channel: " + first.labels{ch});
            xlabel(ax, "Time (ms)");
            ylabel(ax, "Amplitude (\muV)");
            xline(ax, 0, "Color", "k", "LineStyle", "--");
            yline(ax, 0, "Color", "k", "LineStyle", "--");
            box(ax, "off");
            xlim(ax, [min(first.times), max(first.times)]);
            % Clamp every electrode to the largest range (graphics > erpPlot >
            % clampYAxis) so the amplitude axis stays fixed while stepping
            % electrodes; otherwise rescale to the shown electrode.
            if AlakazamSettings.get('graphics', 'erpPlot', 'clampYAxis')
                [ymin, ymax] = this.globalExtent();
            end
            if isfinite(ymin) && isfinite(ymax) && ymax > ymin
                ylim(ax, [ymin, ymax]);
            end
            % Orientation of the amplitude axis (graphics > erpPlot > positiveUp).
            if AlakazamSettings.get('graphics', 'erpPlot', 'positiveUp')
                set(ax, 'YDir', 'normal');
            else
                set(ax, 'YDir', 'reverse');
            end
            % Build the legend from the mean-line handles only, so the bin
            % names always appear and bands/reference lines never leak in.
            if ~isempty(handles)
                legend(handles, cellstr(names), "Location", "northeast");
            else
                legend(ax, "off");
            end
            hold(ax, "off");

            this.buildCheckboxes(allNames);
        end

        function onKey(this, event)
        %ONKEY  Up / down arrows step the channel shown for all lines.
        %   Public (not the private helper it used to be): dispatched by
        %   Alakazam.dispatchKey for whichever tab is currently selected --
        %   see the constructor comment.
            switch lower(event.Key)
                case "uparrow"
                    this.Channel = max(1, this.Channel - 1);
                case "downarrow"
                    maxChan = min(cellfun(@(s) size(s.data, 1), this.Series));
                    this.Channel = min(maxChan, this.Channel + 1);
                otherwise
                    return;
            end
            this.redraw();
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
        function [lo, hi] = globalExtent(this)
        %GLOBALEXTENT  Min/max over every channel and series, so a clamped axis
        %   fits the electrode with the largest deflection. Includes the +/- 3 SE
        %   band only when it is being drawn.
            showBand = AlakazamSettings.get('graphics', 'erpPlot', 'showConfInt');
            confN    = AlakazamSettings.get('graphics', 'erpPlot', 'confIntN');
            lo = inf; hi = -inf;
            for i = 1:numel(this.Series)
                if ~this.Visible(i)
                    continue;
                end
                s = this.Series{i};
                if showBand
                    loMat = s.data - confN * s.stErr;
                    hiMat = s.data + confN * s.stErr;
                else
                    loMat = s.data;
                    hiMat = s.data;
                end
                lo = min(lo, min(loMat(:), [], "omitnan"));
                hi = max(hi, max(hiMat(:), [], "omitnan"));
            end
        end

        function buildCheckboxes(this, names)
        %BUILDCHECKBOXES  One tickbox per series, stacked down the right-hand
        %   grid strip (this.CheckboxGrid), reflecting (and toggling)
        %   this.Visible.
            delete(this.CheckboxGrid.Children);
            n = numel(this.Series);
            if n == 0
                this.CheckboxGrid.RowHeight = {'1x'};
                return;
            end
            this.CheckboxGrid.RowHeight = [repmat({22}, 1, n), {'1x'}];
            for i = 1:n
                cb = uicheckbox(this.CheckboxGrid, ...
                    "Text", char(names(i)), ...
                    "Value", this.Visible(i), ...
                    "ValueChangedFcn", @(src, ~) this.onToggle(i, src.Value));
                cb.Layout.Row = i;
            end
        end

        function onToggle(this, idx, value)
        %ONTOGGLE  A tickbox was (un)checked: show/hide that line and redraw.
            this.Visible(idx) = logical(value);
            this.notifyActivated();
            this.redraw();
        end

        function series = prepare(~, eeg)
        %PREPARE  Expand an averaged dataset into one plot series per line:
        %   one per bin for a bin-aware average, otherwise a single series.
            labels = {eeg.chanlocs.labels};
            if isfield(eeg, "id") && ~isempty(eeg.id); id = char(string(eeg.id)); else; id = ""; end
            file = char(string(eeg.File));   % unique per dataset; id is not
            series = {};

            isBinned = ndims(eeg.data) == 3 && isfield(eeg, "bindesc") ...
                && ~isempty(eeg.bindesc);

            if isBinned
                for b = 1:size(eeg.data, 3)
                    name = char(string(eeg.bindesc(b).label));
                    if isfield(eeg.bindesc, "n") && ~isempty(eeg.bindesc(b).n)
                        % A regular bin's n is numeric (trial count); a
                        % combination bin's is a string built from its
                        % constituents' counts (e.g. "68-74"), since it has
                        % no trials of its own.
                        name = sprintf('%s (n=%s)', name, string(eeg.bindesc(b).n));
                    end
                    s.id     = id;
                    s.file   = file;
                    s.name   = name;
                    s.times  = eeg.times;
                    s.data   = eeg.data(:, :, b);
                    s.stErr  = eeg.stErr(:, :, b);
                    s.labels = labels;
                    series{end + 1} = s; %#ok<AGROW>
                end
            else
                s.id    = id;
                s.file  = file;
                s.name  = id;
                s.times = eeg.times;
                s.data  = reshape(eeg.data, size(eeg.data, 1), size(eeg.data, 2));
                if isfield(eeg, "stErr") && ~isempty(eeg.stErr)
                    s.stErr = reshape(eeg.stErr, size(s.data, 1), size(s.data, 2));
                else
                    s.stErr = zeros(size(s.data));
                end
                s.labels = labels;
                series{end + 1} = s;
            end
        end
    end
end
