classdef EpochView < handle
%EPOCHVIEW  Keyboard-driven view of an epoched multichannel dataset.
%
%   EpochView draws epoched (channels x time x trials) data in one of two
%   modes and steps through it with the arrow keys, replacing the old
%   Tools.plotEpochedTimeMulti function with a clean stateful class.
%
%   Modes:
%     * channel mode: one channel, all trials overlaid (up / down arrows
%       change the channel);
%     * trial mode: one trial, all channels overlaid (left / right arrows
%       change the trial).
%   The "l" key toggles the legend.
%
%   Style follows the project standard (UpperCamelCase class/properties,
%   lowerCamelCase methods, double quotes except where a char array is
%   required by an API).
%
%   See also ALAKAZAMPLOTTER, AVERAGEVIEW, FOURIERVIEW.

    properties (SetAccess = private)
        Figure          % owning figure
        Axes            % axes the epochs are drawn in
        EEG             % the epoched dataset (channels x time x trials)
        Times           % 1 x time, sample times
        Labels          % 1 x nchan cell of channel labels
        Channel = 1     % current channel (channel mode)
        Trial = 1       % current trial (trial mode)
        Mode = "channel" % "channel" or "trial"
        ShowLegend = true
    end

    methods
        function this = EpochView(fig, eeg)
        %EPOCHVIEW  Build the view for an epoched dataset in FIG.
            this.Figure = fig;
            this.EEG    = eeg;
            this.Times  = eeg.times;
            this.Labels = {eeg.chanlocs.labels};
            this.Axes   = axes("Parent", fig);
            set(fig, "KeyPressFcn", @(~, e) this.onKey(e));
            this.redraw();
            axtoolbar(this.Axes, "default");
        end

        function redraw(this)
        %REDRAW  Draw the current channel (all trials) or trial (all channels).
            ax = this.Axes;
            cla(ax);
            nTrials = size(this.EEG.data, 3);
            if this.Mode == "channel"
                plot(ax, this.Times, squeeze(this.EEG.data(this.Channel, :, :)));
                title(ax, "Channel: " + this.Labels{this.Channel});
                legendText = cellstr(num2str((1:nTrials)', 'Trial=%-d'));
                legend(ax, legendText, "NumColumns", ceil(nTrials / 35), "Location", "northeast");
            else
                plot(ax, this.Times, squeeze(this.EEG.data(:, :, this.Trial)));
                title(ax, "Trial: " + this.Trial);
                legend(ax, this.Labels, "NumColumns", ceil(numel(this.Labels) / 35), "Location", "northeast");
            end
            legendHandle = findobj(this.Figure, "Type", "legend");
            if this.ShowLegend
                set(legendHandle, "Visible", "on");
            else
                set(legendHandle, "Visible", "off");
            end
        end
    end

    methods (Access = private)
        function onKey(this, event)
        %ONKEY  Arrow keys step channel / trial; "l" toggles the legend.
            switch lower(event.Key)
                case "uparrow"
                    this.Channel = max(1, this.Channel - 1);
                    this.Mode = "channel";
                case "downarrow"
                    this.Channel = min(size(this.EEG.data, 1), this.Channel + 1);
                    this.Mode = "channel";
                case "leftarrow"
                    this.Trial = max(1, this.Trial - 1);
                    this.Mode = "trial";
                case "rightarrow"
                    this.Trial = min(size(this.EEG.data, 3), this.Trial + 1);
                    this.Mode = "trial";
                case "l"
                    this.ShowLegend = ~this.ShowLegend;
                otherwise
                    return;
            end
            this.redraw();
        end
    end
end
