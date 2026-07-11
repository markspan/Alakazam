classdef AlakazamPlotter < handle
%ALAKAZAMPLOTTER  Renders EEG datasets into tabs for an Alakazam app.
%
%   AlakazamPlotter owns the plotting responsibility that used to live inside
%   the main Alakazam class. It is constructed with a handle to the owning
%   application and reaches back through it for the current dataset
%   (App.Workspace.EEG) and the tabgroup plots live in (App.PlotsTabGroup).
%
%   Plots are uitabs inside App.PlotsTabGroup, a single uitabgroup owned by
%   Alakazam's one main uifigure (see migration.md and Alakazam.setupMainWindow
%   for the full history): docking plots via the undocumented
%   matlab.ui.container.internal.AppContainer + matlab.ui.internal.
%   FigureDocument was tried first, but confirmed broken (both classic axes
%   and uiaxes content render as literal "undefined" text inside a
%   FigureDocument, reproducibly across MATLAB 2025a/2025b/2026a). Docking
%   plain classic figure() windows via MATLAB R2025a+'s built-in Tabbed
%   Figure Container worked, but opened a second, separate OS window from
%   Alakazam's own toolstrip+tree window, which was rejected. Managing our
%   own uitabgroup inside one shared uifigure avoids both problems: uiaxes
%   content is completely at home in a genuine uifigure (never involves
%   AppContainer/FigureDocument at all), and every tab lives in the same
%   window as the tree and toolbar.
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
        %   that plotting can read its current dataset and add tabs to its
        %   plots tabgroup.
            this.App = app;
        end

        function plotCurrent(this)
        %PLOTCURRENT  Show the app's current dataset, reusing an open tab.
        %   PLOTCURRENT(THIS) selects the existing tab for the current
        %   dataset if one is already open; otherwise it creates a new tab
        %   in App.PlotsTabGroup and draws the appropriate view into it
        %   (epoched or continuous, time or frequency domain).
            app = this.App;
            eeg = app.Workspace.EEG;

            % findobj searches any graphics container's descendants, not
            % just groot/figures, so this finds a tab by its own Tag
            % directly within the tabgroup.
            existingTab = findobj(app.PlotsTabGroup.Children, 'flat', 'Tag', eeg.File);
            if ~isempty(existingTab)
                app.PlotsTabGroup.SelectedTab = existingTab(1);
                app.refreshPlotsView();
                return;
            end

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

            newTab = uitab(app.PlotsTabGroup, "Title", tabName, "Tag", eeg.File);

            % uitab has no native close-button concept at all (checked its
            % full property list) -- the tab strip itself is rendered
            % entirely by MATLAB, so no uicomponent can be injected into it.
            % A right-click "Close" menu is the closest fully-supported
            % equivalent, and matches the workspace tree's own existing
            % right-click idiom. Tiles get a real close-x button instead,
            % since those are a wrapper we fully control -- see
            % Alakazam.tileWrapperFor.
            closeMenu = uicontextmenu(app.MainFigure);
            uimenu(closeMenu, "Text", "Close", "MenuSelectedFcn", @(~, ~) app.closeTab(eeg.File));
            newTab.ContextMenu = closeMenu;

            % Store the dataset on the tab for downstream access.
            setappdata(newTab, "EEG", eeg);

            % Draw the view that matches the dataset's format and type.
            if this.isEpoched(eeg)
                this.plotEpoched(eeg, newTab);
            else
                this.plotContinuous(eeg, newTab);
            end

            app.PlotsTabGroup.SelectedTab = newTab;
            app.refreshPlotsView();

            % SignalView measures its axes' real pixel width (AxWidthPx) to
            % size the min/max-pyramid decimation, but during construction
            % (just above) newTab is not yet selected -- and, in Grid/Stack
            % mode, refreshPlotsView's retile() has not yet reparented its
            % content into TileGrid either -- so a still-unplaced uiaxes
            % reports a stale placeholder size (confirmed: [10 10 400 300]
            % regardless of the real container) instead of its true size.
            % That mis-sized the initial decimation, which showed up as a
            % freshly opened continuous plot looking wrong until the next
            % zoom/pan recomputed the now-correct width. One more redraw,
            % now that the view is in its final visible location, fixes the
            % size for good.
            drawnow;
            view = getappdata(newTab, "SignalView");
            if ~isempty(view) && isvalid(view)
                view.redraw();
            end
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

        function plotEpoched(this, eeg, tab)
        %PLOTEPOCHED  Render an epoched or averaged dataset into TAB.
        %   Multichannel time-domain data is drawn either as individual trials
        %   (trials > 1, EpochView) or as a trial average (trials == 1,
        %   AverageView). Frequency-domain data is drawn as a FourierView. The
        %   view handle is stored on the tab so it lives as long as it does.
        %   Single-channel epoched data is not yet handled (empty tab). Each
        %   view's ActivatedFcn is wired to Alakazam.registerTileClick so
        %   keyboard/wheel shortcuts route to whichever tile was last
        %   clicked while several are visible at once in Grid/Stack mode --
        %   see Alakazam.dispatchKey and migration.md.
            if strcmpi(eeg.DataType, "TIMEDOMAIN")
                if eeg.nbchan > 1 && isfield(eeg, "trials")
                    if eeg.trials > 1
                        % Multichannel epoched data (channels x time x trials).
                        view = EpochView(tab, eeg);
                        view.ActivatedFcn = @() this.App.registerTileClick(tab.Tag);
                        setappdata(tab, "EpochView", view);
                    elseif eeg.trials == 1
                        % Trial average (carries a standard error).
                        view = AverageView(tab, eeg);
                        view.ActivatedFcn = @() this.App.registerTileClick(tab.Tag);
                        setappdata(tab, "AverageView", view);
                    end
                end
                % (single-channel epoched data is not yet supported)
            elseif strcmpi(eeg.DataType, "FREQUENCYDOMAIN")
                view = FourierView(tab, eeg);
                view.ActivatedFcn = @() this.App.registerTileClick(tab.Tag);
                setappdata(tab, "FourierView", view);
            end
        end

        function plotContinuous(this, eeg, tab)
        %PLOTCONTINUOUS  Render a continuous dataset into TAB.
        %   Time-domain data is drawn with the fast SignalView (min/max pyramid
        %   decimation, channel stacking, IBI/event overlays); frequency-domain
        %   data is drawn as a Fourier plot. The view handle is stored on the
        %   tab so it lives as long as the tab does; ActivatedFcn is wired the
        %   same way as in plotEpoched (see its comment).
            if strcmpi(eeg.DataType, "TIMEDOMAIN")
                if eeg.nbchan > 1
                    % Multichannel: stack the channels on a shared time axis.
                    view = SignalView(tab, eeg.times, eeg, ...
                        "ShowAxisTicks",    true, ...
                        "YLimMode",         "fixed", ...
                        "MmPerSec",         25, ...
                        "AutoStackSignals", string({eeg.chanlocs.labels}));
                else
                    % Single channel.
                    view = SignalView(tab, eeg.times, eeg, ...
                        "LineSpec",      'b-', ...
                        "MmPerSec",      25, ...
                        "ShowAxisTicks", true, ...
                        "YLimMode",      "fixed");
                end
                view.ActivatedFcn = @() this.App.registerTileClick(tab.Tag);
                setappdata(tab, "SignalView", view);
            else
                % Frequency-domain data.
                view = FourierView(tab, eeg);
                view.ActivatedFcn = @() this.App.registerTileClick(tab.Tag);
                setappdata(tab, "FourierView", view);
            end
        end
    end
end
