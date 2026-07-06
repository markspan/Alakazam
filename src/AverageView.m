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

    properties (SetAccess = private)
        Figure          % owning figure
        Axes            % axes the averages are drawn in
        Series          % flat cell array of per-line series structs
        Channel = 1     % channel shown for every line
    end

    properties (Constant, Access = private)
        % Fixed per-line colours so a bin keeps its colour while stepping
        % electrodes: bin 1 red, bin 2 blue, then a stable palette.
        Palette = [ ...
            1.00 0.00 0.00;   % red
            0.00 0.00 1.00;   % blue
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
            this.Axes   = axes("Parent", fig);
            this.Series = this.prepare(eeg);
            set(fig, "KeyPressFcn", @(~, e) this.onKey(e));
            this.redraw();
            axtoolbar(this.Axes, "default");
        end

        function addDataset(this, eeg)
        %ADDDATASET  Overlay another averaged dataset (ignores duplicates by id).
            newSeries = this.prepare(eeg);
            if isempty(newSeries)
                return;
            end
            existingIds = cellfun(@(s) string(s.id), this.Series);
            if ~any(existingIds == string(newSeries{1}.id))
                this.Series = [this.Series, newSeries];
            end
            this.redraw();
        end

        function redraw(this)
        %REDRAW  Draw every line's channel average and +/- 3 SE band.
            ax = this.Axes;
            % Remove ALL prior objects, including ones with hidden handles
            % (bands, patches, reference lines). cla only deletes visible-handle
            % children on older MATLAB, which otherwise pile up on each redraw.
            delete(allchild(ax));
            hold(ax, "on");

            ids = cellfun(@(s) string(s.id), this.Series);
            manyIds = numel(unique(ids)) > 1;   % overlaying > 1 dataset
            ymin = inf; ymax = -inf;

            handles = gobjects(1, numel(this.Series));   % mean line per series
            names   = strings(1, numel(this.Series));

            for i = 1:numel(this.Series)
                s = this.Series{i};
                ch = min(this.Channel, size(s.data, 1));

                % Force row vectors so the band arithmetic is unambiguous.
                meanCh = reshape(s.data(ch, :), 1, []);
                band   = 3 * reshape(s.stErr(ch, :), 1, []);

                if manyIds; names(i) = sprintf('%s: %s', s.id, s.name); else; names(i) = s.name; end

                colour = this.Palette(mod(i - 1, size(this.Palette, 1)) + 1, :);
                line   = plot(ax, s.times, meanCh, "Color", colour, "LineWidth", 1.5);
                plot(ax, s.times, meanCh + band, "Color", colour, "LineStyle", ":");
                plot(ax, s.times, meanCh - band, "Color", colour, "LineStyle", ":");
                patch(ax, [s.times, fliplr(s.times)], [meanCh + band, fliplr(meanCh - band)], ...
                    colour, "EdgeColor", "none", "FaceAlpha", 0.3);

                handles(i) = line;
                ymin = min(ymin, min(meanCh - band, [], "omitnan"));
                ymax = max(ymax, max(meanCh + band, [], "omitnan"));
            end

            first = this.Series{1};
            ch = min(this.Channel, numel(first.labels));
            title(ax, "Channel: " + first.labels{ch});
            xline(ax, 0, "Color", "k", "LineStyle", "--");
            yline(ax, 0, "Color", "k", "LineStyle", "--");
            box(ax, "off");
            xlim(ax, [min(first.times), max(first.times)]);
            if isfinite(ymin) && isfinite(ymax) && ymax > ymin
                ylim(ax, [ymin, ymax]);
            end
            % Build the legend from the mean-line handles only, so the bin
            % names always appear and bands/reference lines never leak in.
            legend(handles, cellstr(names), "Location", "northeast");
            hold(ax, "off");
        end
    end

    methods (Access = private)
        function onKey(this, event)
        %ONKEY  Up / down arrows step the channel shown for all lines.
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

        function series = prepare(~, eeg)
        %PREPARE  Expand an averaged dataset into one plot series per line:
        %   one per bin for a bin-aware average, otherwise a single series.
            labels = {eeg.chanlocs.labels};
            if isfield(eeg, "id") && ~isempty(eeg.id); id = char(string(eeg.id)); else; id = ""; end
            series = {};

            isBinned = ndims(eeg.data) == 3 && isfield(eeg, "bindesc") ...
                && ~isempty(eeg.bindesc);

            if isBinned
                for b = 1:size(eeg.data, 3)
                    name = char(string(eeg.bindesc(b).label));
                    if isfield(eeg.bindesc, "n") && ~isempty(eeg.bindesc(b).n)
                        name = sprintf('%s (n=%d)', name, eeg.bindesc(b).n);
                    end
                    s.id     = id;
                    s.name   = name;
                    s.times  = eeg.times;
                    s.data   = eeg.data(:, :, b);
                    s.stErr  = eeg.stErr(:, :, b);
                    s.labels = labels;
                    series{end + 1} = s; %#ok<AGROW>
                end
            else
                s.id    = id;
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
