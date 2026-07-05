classdef AlakazamPlotter < handle
%ALAKAZAMPLOTTER  Renders EEG datasets into docked figures for an Alakazam app.
%
%   AlakazamPlotter owns the plotting responsibility that used to live inside
%   the main Alakazam class. It is constructed with a handle to the owning
%   application and reaches back through it for the current dataset
%   (App.Workspace.EEG), the document window (App.ToolGroup) and the registry
%   of open figures (App.Figures).
%
%   The public entry point is plotCurrent; the remaining methods are private
%   helpers that select and draw the correct view for a dataset.
%
%   Naming conventions match the Alakazam class: classes UpperCamelCase,
%   methods lowerCamelCase (verb first), properties UpperCamelCase, locals
%   descriptive lowerCamelCase. Double quotes are used for string literals
%   except where a char array is required by a third-party API.
%
%   See also ALAKAZAM.

    properties
        App   % Alakazam, handle to the owning application
    end

    methods
        function this = AlakazamPlotter(app)
        %ALAKAZAMPLOTTER  Construct a plotter bound to an Alakazam application.
        %   THIS = ALAKAZAMPLOTTER(APP) stores a handle to the owning app so
        %   that plotting can read its current dataset and add figures to its
        %   document window.
            this.App = app;
        end

        function plotCurrent(this)
        %PLOTCURRENT  Show the app's current dataset, reusing an open figure.
        %   PLOTCURRENT(THIS) brings the existing figure for the current
        %   dataset to the front if one is already open; otherwise it creates
        %   a new document figure, draws the appropriate view (epoched or
        %   continuous, time or frequency domain) and docks it in the app.
            app = this.App;
            eeg = app.Workspace.EEG;

            % If a figure already exists for this dataset, just show it.
            existingFig = findobj("Type", "Figure", "Tag", eeg.File);
            if ~isempty(existingFig)
                app.ToolGroup.showClient(get(existingFig, "Name"));
                return;
            end

            % Otherwise open a new (initially hidden) document figure for it.
            newFig = figure( ...
                "NumberTitle",       "off", ...
                "Name",              eeg.id, ...
                "Tag",               eeg.File, ...
                "Color",             [.98 .98 .98], ...
                "PaperOrientation",  "landscape", ...
                "PaperPosition",     [.05 .05 .9 .9], ...
                "PaperPositionMode", "auto", ...
                "PaperType",         "A0", ...
                "Units",             "normalized", ...
                "MenuBar",           "none", ...
                "Toolbar",           "none", ...
                "DockControls",      "on", ...
                "Visible",           "off");
            app.Figures(end + 1) = newFig;

            % Attach a handle-graphics view of the dataset (used for the
            % interactive R-peak / cursor editing elsewhere in the app).
            hEEG = Tools.hEEG;
            hEEG.toHandle(eeg);
            set(newFig, "UserData", eeg);

            % Draw the view that matches the dataset's format and type.
            if this.isEpoched(eeg)
                this.plotEpoched(eeg, newFig);
            else
                this.plotContinuous(eeg, newFig);
                set(newFig, "Toolbar", "none");
            end

            % Dock the finished figure and reveal it.
            app.ToolGroup.addFigure(newFig);
            newFig.Visible = "on";
        end
    end

    methods (Access = private)
        function tf = isEpoched(~, eeg)
        %ISEPOCHED  True for epoched or averaged datasets.
        %   TF = ISEPOCHED(~, EEG) returns true when EEG.DataFormat is either
        %   "EPOCHED" or "AVERAGED", and false for continuous data.
            tf = strcmpi(eeg.DataFormat, "EPOCHED") || ...
                 strcmpi(eeg.DataFormat, "AVERAGED");
        end

        function plotEpoched(~, eeg, fig)
        %PLOTEPOCHED  Render an epoched or averaged dataset into FIG.
        %   Multichannel time-domain data is drawn either as individual trials
        %   (trials > 1) or as a trial average (trials == 1). Frequency-domain
        %   data is drawn as a Fourier plot. Single-channel epoched data is not
        %   yet handled and leaves the figure empty.
            if strcmpi(eeg.DataType, "TIMEDOMAIN")
                if eeg.nbchan > 1 && isfield(eeg, "trials")
                    if eeg.trials > 1
                        % Multichannel epoched data (channels x time x trials).
                        Tools.plotEpochedTimeMulti(eeg, fig);
                    elseif eeg.trials == 1
                        % Trial average (carries a standard deviation).
                        Tools.plotEpochedTimeMultiAverage(eeg, fig);
                    end
                end
                % (single-channel epoched data is not yet supported)
            elseif strcmpi(eeg.DataType, "FREQUENCYDOMAIN")
                Tools.plotFourier(eeg, fig);
            end
        end

        function plotContinuous(~, eeg, fig)
        %PLOTCONTINUOUS  Render a continuous dataset into FIG.
        %   Time-domain data is drawn with plotECG, stacking the channels for
        %   multichannel recordings; frequency-domain data is drawn as a
        %   Fourier plot. The plotECG name-value names and the line spec are
        %   kept as char arrays, which that third-party helper expects.
            if strcmpi(eeg.DataType, "TIMEDOMAIN")
                if eeg.nbchan > 1
                    % Multichannel: stack the channels on shared time axis.
                    Tools.plotECG(eeg.times, eeg, ...
                        'ShowAxisTicks',    'on', ...
                        'YLimMode',         'fixed', ...
                        'mmPerSec',         25, ...
                        'AutoStackSignals', {eeg.chanlocs.labels}, ...
                        'Parent',           fig);
                else
                    % Single channel.
                    Tools.plotECG(eeg.times, eeg, 'b-', ...
                        'mmPerSec',      25, ...
                        'ShowAxisTicks', 'on', ...
                        'YLimMode',      'fixed', ...
                        'Parent',        fig);
                end
            else
                % Frequency-domain data.
                Tools.plotFourier(eeg, fig);
            end
        end
    end
end
