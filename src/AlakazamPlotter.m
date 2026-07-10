classdef AlakazamPlotter < handle
%ALAKAZAMPLOTTER  Renders EEG datasets into docked figures for an Alakazam app.
%
%   AlakazamPlotter owns the plotting responsibility that used to live inside
%   the main Alakazam class. It is constructed with a handle to the owning
%   application and reaches back through it for the current dataset
%   (App.Workspace.EEG), the document window (App.AppContainer) and the
%   registry of open figures (App.Figures).
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

            % AppContainer-hosted document figures have HandleVisibility=off
            % and are never parented under groot, so findobj/gcf-style global
            % figure search cannot discover them; the FigureDocument's own
            % Tag (deterministic from eeg.File, so it doubles as the lookup
            % key) is looked up directly in the "plots" document group
            % instead -- see docTag below.
            docTag = string(matlab.lang.makeValidName(eeg.File));

            % If a document already exists for this dataset, just show it.
            if app.AppContainer.hasDocument("plots", docTag)
                app.AppContainer.getDocument("plots", docTag).Selected = true;
                return;
            end

            % Otherwise open a new (initially hidden) document figure for it.
            % EEG.id is just the transform name now (e.g. "Average" for every
            % averaged dataset in the tree), so it collides across nodes; the
            % file's own stem is the node's timestamped key (transformId +
            % timestamp, glued with no separator, e.g. "Average051423") and
            % is unique by construction (see Alakazam.persistResultNode).
            % Split it back into "id (timestamp)" for display -- e.g.
            % "Average (051423)" -- rather than showing the glued form as-is.
            [~, tabName, ~] = fileparts(eeg.File);
            idStr = char(string(eeg.id));
            if startsWith(tabName, idStr) && ~strcmp(tabName, idStr)
                tabName = sprintf('%s (%s)', idStr, tabName(numel(idStr) + 1:end));
            end

            doc = matlab.ui.internal.FigureDocument('Tag', docTag, 'Title', tabName, ...
                'DocumentGroupTag', 'plots');
            newFig = doc.Figure;
            % doc.Figure is a web-hosted "divfigure": classic graphics
            % (axes/uicontrol) construct on it without error but do not
            % reliably render inside AppContainer's tab, whereas
            % App-Designer-family content (uiaxes, uigridlayout, uicontrol's
            % ui*-prefixed replacements) does -- see the View classes
            % (SignalView, AverageView, EpochView, FourierView), all of
            % which draw with uiaxes for this reason. Classic print/menu/
            % toolbar figure properties (NumberTitle, PaperOrientation,
            % MenuBar, Toolbar, DockControls, ...) are therefore no longer
            % set here: they are meaningless once nothing on the figure is
            % classic-graphics-hosted.
            set(newFig, ...
                "Name",  tabName, ...
                "Tag",   eeg.File, ...
                "Color", [.98 .98 .98], ...
                "Visible", "on");
            app.Figures(end + 1) = newFig;

            % Store the dataset on the figure for downstream access.
            set(newFig, "UserData", eeg);

            % Dock the figure BEFORE drawing into it: content drawn into a
            % divfigure before it is registered with AppContainer via
            % addDocument does not reliably show up once the tab is
            % revealed (it stays "off" here; nothing is shown yet).
            app.AppContainer.addDocument(doc);

            % Draw the view that matches the dataset's format and type.
            if this.isEpoched(eeg)
                this.plotEpoched(eeg, newFig);
            else
                this.plotContinuous(eeg, newFig);
            end

            % Reveal the finished figure.
            newFig.Visible = "on";
            drawnow;
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
        %   (trials > 1, EpochView) or as a trial average (trials == 1,
        %   AverageView). Frequency-domain data is drawn as a FourierView. The
        %   view handle is stored on the figure so it lives as long as it does.
        %   Single-channel epoched data is not yet handled (empty figure).
            if strcmpi(eeg.DataType, "TIMEDOMAIN")
                if eeg.nbchan > 1 && isfield(eeg, "trials")
                    if eeg.trials > 1
                        % Multichannel epoched data (channels x time x trials).
                        setappdata(fig, "EpochView", EpochView(fig, eeg));
                    elseif eeg.trials == 1
                        % Trial average (carries a standard error).
                        setappdata(fig, "AverageView", AverageView(fig, eeg));
                    end
                end
                % (single-channel epoched data is not yet supported)
            elseif strcmpi(eeg.DataType, "FREQUENCYDOMAIN")
                setappdata(fig, "FourierView", FourierView(fig, eeg));
            end
        end

        function plotContinuous(~, eeg, fig)
        %PLOTCONTINUOUS  Render a continuous dataset into FIG.
        %   Time-domain data is drawn with the fast SignalView (min/max pyramid
        %   decimation, channel stacking, IBI/event overlays); frequency-domain
        %   data is drawn as a Fourier plot. The SignalView handle is stored on
        %   the figure so it lives as long as the figure does.
            if strcmpi(eeg.DataType, "TIMEDOMAIN")
                if eeg.nbchan > 1
                    % Multichannel: stack the channels on a shared time axis.
                    view = SignalView(fig, eeg.times, eeg, ...
                        "ShowAxisTicks",    true, ...
                        "YLimMode",         "fixed", ...
                        "MmPerSec",         25, ...
                        "AutoStackSignals", string({eeg.chanlocs.labels}));
                else
                    % Single channel.
                    view = SignalView(fig, eeg.times, eeg, ...
                        "LineSpec",      'b-', ...
                        "MmPerSec",      25, ...
                        "ShowAxisTicks", true, ...
                        "YLimMode",      "fixed");
                end
                setappdata(fig, "SignalView", view);
            else
                % Frequency-domain data.
                setappdata(fig, "FourierView", FourierView(fig, eeg));
            end
        end
    end
end
