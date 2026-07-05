classdef AverageView < handle
%AVERAGEVIEW  View of one or more trial-averaged datasets with error bands.
%
%   AverageView draws the per-channel trial average of an averaged dataset
%   together with a +/- 3 standard-error band, and can overlay several such
%   datasets on the same axes. It replaces the old
%   Tools.plotEpochedTimeMultiAverage function with a clean stateful class.
%
%   The up / down arrow keys step the displayed channel for every overlaid
%   dataset at once. Dragging one averaged dataset onto another adds it here
%   through addDataset.
%
%   Style follows the project standard.
%
%   See also ALAKAZAMPLOTTER, EPOCHVIEW, FOURIERVIEW.

    properties (SetAccess = private)
        Figure          % owning figure
        Axes            % axes the averages are drawn in
        Datasets        % cell array of averaged datasets, drawn overlaid
        Channel = 1     % channel shown for every dataset
    end

    methods
        function this = AverageView(fig, eeg)
        %AVERAGEVIEW  Build the view for an averaged dataset in FIG.
            this.Figure   = fig;
            this.Axes     = axes("Parent", fig);
            this.Datasets = {this.prepare(eeg)};
            set(fig, "KeyPressFcn", @(~, e) this.onKey(e));
            this.redraw();
            axtoolbar(this.Axes, "default");
        end

        function addDataset(this, eeg)
        %ADDDATASET  Overlay another averaged dataset (ignores duplicates).
            added = this.prepare(eeg);
            existingIds = cellfun(@(d) string(d.id), this.Datasets);
            if ~any(existingIds == string(added.id))
                this.Datasets{end + 1} = added;
            end
            this.redraw();
        end

        function redraw(this)
        %REDRAW  Draw every overlaid dataset's channel average and error band.
            ax = this.Axes;
            cla(ax);
            hold(ax, "on");
            for i = 1:numel(this.Datasets)
                eeg = this.Datasets{i};
                ch = min(this.Channel, size(eeg.data, 1));

                % Force row vectors so the band arithmetic is unambiguous.
                mean3 = reshape(squeeze(eeg.data(ch, :, :)), 1, []);
                band = 3 * reshape(squeeze(eeg.stErr(ch, :)), 1, []);

                line = plot(ax, eeg.times, mean3);
                colour = line.Color;
                plot(ax, eeg.times, mean3 + band, "Color", colour, "LineStyle", ":");
                plot(ax, eeg.times, mean3 - band, "Color", colour, "LineStyle", ":");
                patch(ax, [eeg.times, fliplr(eeg.times)], [mean3 + band, fliplr(mean3 - band)], ...
                    colour, "EdgeColor", "none", "FaceAlpha", 0.3);

                title(ax, "Channel: " + eeg.labels{ch});
                xline(ax, 0, "Color", "k", "LineStyle", "--");
                yline(ax, 0, "Color", "k", "LineStyle", "--");
                box(ax, "off");
                xlim(ax, [min(eeg.times), max(eeg.times)]);
                ylim(ax, [min(eeg.data(:)), max(eeg.data(:))]);
            end
            hold(ax, "off");
        end
    end

    methods (Access = private)
        function onKey(this, event)
        %ONKEY  Up / down arrows step the channel shown for all datasets.
            switch lower(event.Key)
                case "uparrow"
                    this.Channel = max(1, this.Channel - 1);
                case "downarrow"
                    maxChan = min(cellfun(@(d) size(d.data, 1), this.Datasets));
                    this.Channel = min(maxChan, this.Channel + 1);
                otherwise
                    return;
            end
            this.redraw();
        end

        function eeg = prepare(~, eeg)
        %PREPARE  Attach the channel labels the view needs.
            eeg.labels = {eeg.chanlocs.labels};
        end
    end
end
