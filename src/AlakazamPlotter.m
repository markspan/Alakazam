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

            % "Average (051423)" for a step's result, its new name once
            % renamed in the tree, its file's name otherwise (tabTitleFor).
            % Renaming retitles an open tab the same way (onRenameNode).
            tabName = tabTitleFor(eeg);

            newTab = uitab(app.PlotsTabGroup, "Title", tabName, "Tag", eeg.File);

            % uitab has no native close-button concept at all (checked its
            % full property list) -- the tab strip itself is rendered
            % entirely by MATLAB, so no uicomponent can be injected into it.
            % A right-click menu is the closest fully-supported
            % equivalent, and matches the workspace tree's own existing
            % right-click idiom. "Undock" lives here for the same reason,
            % and only here: in a tiled mode the tab strip is hidden
            % entirely, so there is no tab to right-click.
            %
            % The menu is parented to MainFigure, which stays correct while
            % a plot is undocked because the TAB never moves, only its
            % content does (see Alakazam.undockTab). A ContextMenu does not
            % follow a reparent, so a menu on the content itself would
            % quietly stop working the moment it left. Tiles get a real close-x button instead,
            % since those are a wrapper we fully control -- see
            % Alakazam.tileWrapperFor.
            tabMenu = uicontextmenu(app.MainFigure);
            uimenu(tabMenu, "Text", "Undock", "MenuSelectedFcn", @(~, ~) app.undockTab(eeg.File));
            uimenu(tabMenu, "Text", "Close", "MenuSelectedFcn", @(~, ~) app.closeTab(eeg.File));
            closeOthers = uimenu(tabMenu, "Text", "Close others", ...
                "MenuSelectedFcn", @(~, ~) app.closeOtherTabs(eeg.File));

            % "Close others" is greyed out when this is the only plot open,
            % rather than offered and doing nothing. The count is read when
            % the menu opens, not now: tabs come and go for the whole life
            % of this one, so anything decided here would be wrong within
            % a click or two.
            tabMenu.ContextMenuOpeningFcn = @(~, ~) set(closeOthers, "Enable", ...
                matlab.lang.OnOffSwitchState(numel(app.PlotsTabGroup.Children) > 1));

            newTab.ContextMenu = tabMenu;

            % Store the dataset on the tab for downstream access.
            setappdata(newTab, "EEG", eeg);

            % WHAT THE LAST VIEW WAS SHOWING, carried to this one. Read
            % BEFORE the new view is built, since building it changes which
            % tab is current. Stepping through the workspace tree otherwise
            % reset to the first electrode on every node, which made
            % comparing the same channel across analyses a matter of
            % clicking back to it each time.
            focus = this.App.ViewFocus;
            if ~isempty(focus)
                focus.capture(this.viewOnTab(app.PlotsTabGroup.SelectedTab));
            end

            % Draw the view that matches the dataset's format and type.
            if this.isEpoched(eeg)
                this.plotEpoched(eeg, newTab);
            else
                this.plotContinuous(eeg, newTab);
            end

            % Applied after construction rather than passed in: a view sets
            % its own default while building, and every one of them ends
            % that with a draw, so overriding afterwards is one code path
            % instead of an extra constructor argument in nine classes.
            if ~isempty(focus)
                focus.apply(this.viewOnTab(newTab));
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
            % drawnow yields to the event queue -- a nearly-simultaneous
            % tree selection/recalculate elsewhere (e.g. Recalculate
            % closing and reopening several tabs in quick succession) can
            % process during this exact yield and delete NEWTAB out from
            % under this call before it resumes, confirmed via a live
            % "Value must be a handle" crash right here. Everything up to
            % this point already succeeded against the same NEWTAB, so
            % only this post-construction resize step -- purely a visual
            % nicety, see the comment above -- needs to become a no-op
            % rather than crash if that happened.
            if isvalid(newTab)
                view = getappdata(newTab, "SignalView");
                if ~isempty(view) && isvalid(view)
                    view.redraw();
                end
            end
        end
    end

    methods (Static)
        function viewClass = viewClassFor(eeg)
        %VIEWCLASSFOR  The name of the view class that draws an epoched or
        %   averaged dataset, or '' when there is none: continuous data (drawn
        %   by plotContinuous instead) and single-channel epoched data.
        %   plotEpoched builds exactly this view, and the tree's Overlay on
        %   ERP plot command asks it whether a node is an ERP (AverageView), so
        %   the two cannot disagree about what counts as one.
        %
        %   Multichannel time-domain data is drawn either as individual trials
        %   (trials > 1, EpochView) or as a trial average (trials == 1,
        %   AverageView). Frequency-domain data is drawn as a FourierView.
        %
        %   EEG.id (stamped by Alakazam.persistResultNode to the
        %   transformation's own id) is checked first for transformations
        %   whose result needs a dedicated view rather than falling into
        %   the generic DataFormat/DataType routing below -- e.g.
        %   TimeFrequency's result is still DataFormat "EPOCHED" with
        %   multiple trials (so it would otherwise land in EpochView,
        %   which cannot draw an ERSP heatmap), and ScalpDistribution's
        %   result is still DataFormat "AVERAGED" with trials==1 (so it
        %   would otherwise land in AverageView, which cannot draw a
        %   scalp topography).
        %
        %   The id check catches a fresh transform result; the field check
        %   also catches a grand average of such results, whose id has been
        %   renamed to the grand-average's name (see saveGrandAverage) but
        %   which still carries the .ersp / .coherence map to draw.
            viewClass = '';
            format = fieldText(eeg, 'DataFormat');
            if ~strcmpi(format, 'EPOCHED') && ~strcmpi(format, 'AVERAGED')
                return;   % continuous: plotContinuous's business
            end
            id = fieldText(eeg, 'id');
            if strcmpi(id, 'Report')
                % A rendered Quarto/R statistics report (see
                % Alakazam.persistReportNode), not a dataset at all -- its
                % DataFormat is set to "EPOCHED" purely to route here (see
                % persistReportNode's own comment), so this check must come
                % before every DataFormat/DataType-based branch below.
                viewClass = 'ReportView';
            elseif strcmpi(id, 'TimeFrequency') || hasContent(eeg, 'ersp')
                viewClass = 'TimeFrequencyView';
            elseif strcmpi(id, 'ScalpDistribution')
                viewClass = 'ScalpDistributionView';
            elseif strcmpi(id, 'Brain3D')
                % Also DataFormat "AVERAGED" with trials==1, same as
                % ScalpDistribution's own result (see TransTools.
                % ResolveScalpDistribution, shared by both) -- projected
                % onto a rotatable 3D brain mesh instead of a flat topoplot.
                viewClass = 'Brain3DView';
            elseif strcmpi(id, 'SpectralMeasure')
                % Still DataFormat "EPOCHED" with multiple trials (so it would
                % otherwise land in EpochView), but it carries EEG.spectrum /
                % .spectralMeasures for a per-channel tagged-spectrum view.
                viewClass = 'SpectralMeasureView';
            elseif strcmpi(id, 'CoherenceMap') || hasContent(eeg, 'coherence')
                % Also EPOCHED, but carries EEG.coherence for a per-channel
                % time x frequency coherence-to-reference heatmap (or a grand
                % average of such maps, renamed -- see the TimeFrequency note).
                viewClass = 'CoherenceView';
            elseif strcmpi(id, 'CoherenceTopography') || hasContent(eeg, 'CohTopoValues')
                % Also EPOCHED, but carries EEG.CohTopoValues for a per-bin
                % scalp head-map of coherence to a reference at a single
                % (auto-detected) frequency.
                viewClass = 'CoherenceTopographyView';
            elseif strcmpi(id, 'CrossCorrelation') || hasContent(eeg, 'xcorr')
                % Passes the data through but carries EEG.xcorr: r against
                % lag per channel per bin, drawn as a line with an SE band.
                viewClass = 'CrossCorrelationView';
            elseif strcmpi(id, 'Covariance') || hasContent(eeg, 'covariance')
                % Passes the data through but carries EEG.covariance: a
                % channel x channel matrix per bin, drawn as a heatmap.
                viewClass = 'CovarianceView';
            elseif strcmpi(fieldText(eeg, 'DataType'), 'TIMEDOMAIN')
                if isfield(eeg, 'nbchan') && eeg.nbchan > 1 && isfield(eeg, 'trials')
                    if eeg.trials > 1
                        viewClass = 'EpochView';     % channels x time x trials
                    elseif eeg.trials == 1
                        viewClass = 'AverageView';   % a trial average, with its SE
                    end
                end
            elseif strcmpi(fieldText(eeg, 'DataType'), 'FREQUENCYDOMAIN')
                viewClass = 'FourierView';
            end
        end
    end

    methods (Access = private)
        function view = viewOnTab(~, tab)
        %VIEWONTAB  The AlakazamView stored on TAB, or [] if there is none.
        %   Each branch of plotEpoched stores its view under its own class
        %   name (setappdata(tab, "EpochView", view) and so on), so there is
        %   no single key to read. Asking for the one value that IS a view
        %   avoids repeating that list of names here, where it would fall
        %   out of step the first time a view was added.
            view = [];
            if isempty(tab) || ~isvalid(tab)
                return;
            end
            stored = getappdata(tab);
            names = fieldnames(stored);
            for k = 1:numel(names)
                candidate = stored.(names{k});
                if isa(candidate, 'AlakazamView') && isscalar(candidate) && isvalid(candidate)
                    view = candidate;
                    return;
                end
            end
        end

        function tf = isEpoched(~, eeg)
        %ISEPOCHED  True for epoched or averaged datasets.
        %   TF = ISEPOCHED(~, EEG) returns true when EEG.DataFormat is either
        %   "EPOCHED" or "AVERAGED", and false for continuous data.
            tf = strcmpi(eeg.DataFormat, "EPOCHED") || ...
                 strcmpi(eeg.DataFormat, "AVERAGED");
        end

        function plotEpoched(this, eeg, tab)
        %PLOTEPOCHED  Render an epoched or averaged dataset into TAB.
        %   Which view draws it is viewClassFor's answer (see there for the
        %   rules). The view handle is stored on the tab under its own class
        %   name, so it lives as long as the tab does. Single-channel epoched
        %   data is not yet handled (empty tab). Each view's ActivatedFcn is
        %   wired to Alakazam.registerTileClick so keyboard/wheel shortcuts
        %   route to whichever tile was last clicked while several are
        %   visible at once in Grid/Stack mode -- see Alakazam.dispatchKey
        %   and migration.md.
            viewClass = AlakazamPlotter.viewClassFor(eeg);
            if isempty(viewClass)
                return;   % single-channel epoched data is not yet supported
            end
            view = feval(viewClass, tab, eeg);
            view.ActivatedFcn = @() this.App.registerTileClick(tab.Tag);
            setappdata(tab, viewClass, view);
        end

        function plotContinuous(this, eeg, tab)
        %PLOTCONTINUOUS  Render a continuous dataset into TAB.
        %   Time-domain data is drawn with the fast SignalView (min/max pyramid
        %   decimation, channel stacking, event overlays); frequency-domain
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

% ======================================================================= %
function text = fieldText(eeg, name)
%FIELDTEXT  EEG.(NAME) as char, or '' when the field is absent.
    text = '';
    if isfield(eeg, name) && ~isempty(eeg.(name))
        text = char(string(eeg.(name)));
    end
end

function tf = hasContent(eeg, name)
%HASCONTENT  Whether EEG carries a non-empty field NAME.
    tf = isfield(eeg, name) && ~isempty(eeg.(name));
end
