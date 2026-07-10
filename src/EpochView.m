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
        Grid            % 1x1 uigridlayout the axes fills
        Axes            % axes the epochs are drawn in
        EEG             % the epoched dataset (channels x time x trials)
        Times           % 1 x time, sample times
        Labels          % 1 x nchan cell of channel labels
        Channel = 1     % current channel (channel mode)
        Trial = 1       % current trial (trial mode)
        Mode = "channel" % "channel" or "trial"
        ShowLegend = true
        HasBins = false      % true when epochs carry .bini membership
        BinNameMap           % containers.Map: bin index -> label (if known)
        BinNamesKnown = false
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

            this.Grid = uigridlayout(fig, [1 1], "Padding", [0 0 0 0]);
            this.Axes = uiaxes(this.Grid);
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
                legendText = cell(nTrials, 1);
                for t = 1:nTrials
                    bins = this.binsForTrial(t, false);   % compact "1,2"
                    if isempty(bins)
                        legendText{t} = sprintf('Trial=%d', t);
                    else
                        legendText{t} = sprintf('Trial=%d [bin %s]', t, bins);
                    end
                end
                legend(ax, legendText, "NumColumns", ceil(nTrials / 35), "Location", "northeast");
            else
                plot(ax, this.Times, squeeze(this.EEG.data(:, :, this.Trial)));
                bins = this.binsForTrial(this.Trial, true);   % "1 Related, 2 ..."
                if isempty(bins)
                    title(ax, "Trial: " + this.Trial);
                else
                    title(ax, sprintf('Trial %d   (bins: %s)', this.Trial, bins));
                end
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
        function s = binsForTrial(this, trial, verbose)
        %BINSFORTRIAL  Describe the bins a trial belongs to.
        %   Returns '' when the dataset carries no bin membership or the trial
        %   is in no bin. With VERBOSE, entries read "1 Related"; otherwise
        %   they are just the bin numbers ("1,2").
            s = '';
            if ~this.HasBins
                return;
            end
            bini = this.EEG.epoch(trial).bini;
            if isempty(bini)
                return;
            end
            parts = strings(1, numel(bini));
            for i = 1:numel(bini)
                bn = bini(i);
                if verbose && this.BinNamesKnown && isKey(this.BinNameMap, bn)
                    parts(i) = sprintf('%d %s', bn, this.BinNameMap(bn));
                else
                    parts(i) = sprintf('%d', bn);
                end
            end
            if verbose; sep = ', '; else; sep = ','; end
            s = char(strjoin(parts, sep));
        end

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
