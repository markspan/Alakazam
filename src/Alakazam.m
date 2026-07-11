classdef Alakazam < handle
%ALAKAZAM  Single-window application for modular EEG / physiology analysis.
%
%   Alakazam presents a "tree of datasets plus draggable transformations"
%   workflow (inspired by BrainVision Analyzer). A WorkSpace holds a data
%   browser tree of EEGLAB EEG structures; transformations in the toolbar
%   gallery are applied to the selected dataset to produce new child nodes,
%   and dragging a branch onto another dataset re-applies that chain.
%
%   Application roots (resolved once, in the constructor, from this file's
%   own location so nothing depends on the current working directory):
%     RootDir  - the authored source tree (this src/ folder). Holds the
%                Transformations, Icons, the default workspace and the
%                +uiextras helper package.
%     RepoRoot - the repository root (parent of src/). Holds the shared
%                data-file resources. EEGLAB is not bundled; it is expected on
%                the path (see EEGLabEnvironment).
%
%   Launch with the startAlakazam function at the repository root, or add
%   src/ to the MATLAB path and construct Alakazam directly.
%
%   Naming conventions used throughout:
%     * Classes    UpperCamelCase (Alakazam, WorkSpace, AlakazamPlotter)
%     * Methods    lowerCamelCase, verb first (onTransformation, evaluateDroppedBranch)
%     * Properties UpperCamelCase (RootDir, MainFigure, Workspace)
%     * Locals     descriptive lowerCamelCase
%   Double quotes are used for string literals, except where a char array is
%   required by a third-party API (transformation ids, EEG.Call, fed straight
%   to feval; element-wise char comparisons; path components).
%
%   Adapted from "matlab.ui.internal.desktop.showcaseMPCDesigner()" by
%   R. Chen; original work (c) 2015 The MathWorks, Inc. Further developed by
%   M.M. Span, University of Groningen, Department of Experimental Psychology.
%
%   See also ALAKAZAMPLOTTER, EEGLABENVIRONMENT, WORKSPACE, BUILDTOOLBARALAKAZAM.

    properties (Transient = true)
        RootDir         % char, absolute path to the authored source tree (src/)
        RepoRoot        % char, absolute path to the repository root (vendored code)
        MainFigure      % matlab.ui.Figure, the single app window
        MainGrid        % uigridlayout, the top-level shell layout (see setupMainWindow)
        ToolbarGrid     % uigridlayout cell reserved for the ribbon
        Ribbon          % AlakazamRibbon, the Home/Tools/Grand Average control strip
        TreeGrid        % uigridlayout cell reserved for the workspace tree area (split top/bottom)
        DataTreePanel           % uipanel hosting WorkSpace.Tree (data & analyses), top half of TreeGrid
        GrandAveragesTreePanel  % uipanel hosting WorkSpace.GrandAveragesTree, bottom half of TreeGrid
        PlotsTabGroup   % uitabgroup, one uitab per open dataset
        TileGrid        % uigridlayout, sibling of PlotsTabGroup in the same cell -- see setPlotsViewMode/retile
        PlotsViewMode = "tabs" % "tabs", "grid" or "stack"; see setPlotsViewMode
        TileOrder = string.empty % tab Tags, display order within TileGrid; see retile
        PickedTileTag = "" % Tag of the tile picked for a click-to-swap reorder, or "" if none
        LastClickedTag = "" % Tag of the tile last clicked/interacted with in Grid/Stack mode; see registerTileClick/activeTileTag
        Workspace       % WorkSpace, the data-browser tree and session state
        Plotter         % AlakazamPlotter, renders datasets into tabs
        Debug = true    % logical, when true expose the instance in the base workspace
    end

    methods (Access = private)
        function setupDirectories(this)
        %SETUPDIRECTORIES  Put the authored source tree on the path.
        %   All paths are resolved absolutely, so the app does not depend on the
        %   current working directory. RootDir (src) holds the app code and the
        %   +uiextras package (added by putting src on the path); the
        %   Transformations are added with their subfolders.
            close all;
            warning("off", "MATLAB:ui:javacomponent:FunctionToBeRemoved");
            addpath(this.RootDir, '-end');
            addpath(genpath(fullfile(this.RootDir, 'Transformations')));
        end

        function setupMainWindow(this)
        %SETUPMAINWINDOW  Create the single-window app shell (not yet shown).
        %   One uifigure hosts everything: a top control-strip built by
        %   AlakazamRibbon (Home/Tools/Grand Average -- a uihtml component,
        %   replacing the Toolstrip ribbon, which cannot be attached to
        %   anything but the undocumented matlab.ui.container.internal.
        %   AppContainer; uihtml is a proven-safe pattern in this app
        %   already, see WorkSpaceTree), a reserved grid cell for the
        %   workspace tree (populated later by WorkSpace/CreateTreeComponent),
        %   and PlotsTabGroup, where AlakazamPlotter opens one uitab per
        %   dataset. See migration.md for the full history: docking plots
        %   via AppContainer + matlab.ui.internal.FigureDocument rendered
        %   "undefined" (a confirmed undocumented-API bug); docking classic
        %   figure() windows via MATLAB's own R2025a+ Tabbed Figure
        %   Container worked, but opened a second, separate OS window from
        %   the app's own shell, which was rejected. A self-managed
        %   uitabgroup inside one uifigure avoids both: uiaxes is completely
        %   at home in a genuine uifigure, and everything lives in one
        %   window.
        %
        %   Visible is deliberately NOT set here: the workspace tree (built
        %   after this method returns) must be attached to TreeGrid first,
        %   the same "build hidden, reveal once populated" ordering the old
        %   AppContainer/ToolGroup shells required.
        %
        %   TreeGrid itself is split top/bottom into two titled panels --
        %   DataTreePanel (data & analyses) and GrandAveragesTreePanel --
        %   each hosting its own separate WorkSpaceTree instance (see
        %   WorkSpace.CreateTreeComponent): grand averages combine several
        %   subjects' results, so they never belonged nested under any
        %   single subject's branch, and lived in the same tree only as an
        %   awkward always-present "Grand Averages" root node. Two real
        %   trees read more clearly and let WorkSpace.GrandAveragesTree
        %   hold flat, top-level grand-average nodes directly.
            this.MainFigure = uifigure( ...
                "Name",   "Alakazam", ...
                "Tag",    "AlakazamApp", ...
                "Position", [100 100 1280 720], ...
                "Visible", "off", ...
                "CloseRequestFcn", @(~, ~) this.onCloseRequest());

            % Column 2 is a narrow draggable splitter between the tree and
            % the plots area (see beginTreeResize/dragTreeResize/
            % endTreeResize): a plain uigridlayout has no built-in resizable
            % divider the way AppContainer's dock panels did, so this is a
            % hand-rolled replacement for that lost affordance.
            this.MainGrid = uigridlayout(this.MainFigure, [2 3], ...
                "RowHeight", {124, '1x'}, "ColumnWidth", {260, 3, '1x'}, ...
                "Padding", [4 4 4 4], "RowSpacing", 4, "ColumnSpacing", 0);

            this.ToolbarGrid = uigridlayout(this.MainGrid, [1 1], "Padding", [0 0 0 0]);
            this.ToolbarGrid.Layout.Row = 1;
            this.ToolbarGrid.Layout.Column = [1 3];
            this.Ribbon = AlakazamRibbon(this.ToolbarGrid, fullfile(this.RootDir, "Transformations"), ...
                "ItemPushedFcn", @(id) this.onRibbonAction(id));

            % Row 2 is a thin draggable splitter between the two trees (see
            % beginTreesSplitResize/dragTreesSplitResize/endTreesSplitResize),
            % the same hand-rolled pattern as the tree/plots splitter below --
            % a plain uigridlayout has no built-in resizable divider either way.
            this.TreeGrid = uigridlayout(this.MainGrid, [3 1], "RowHeight", {'2x', 3, '1x'}, ...
                "Padding", [0 0 0 0], "RowSpacing", 0);
            this.TreeGrid.Layout.Row = 2;
            this.TreeGrid.Layout.Column = 1;

            this.DataTreePanel = uipanel(this.TreeGrid, "Title", "Data & Analyses", "FontWeight", "bold");
            this.DataTreePanel.Layout.Row = 1;

            treesSplitter = uipanel(this.TreeGrid, "BorderType", "none", ...
                "BackgroundColor", [.75 .75 .75], ...
                "ButtonDownFcn", @(~, ~) this.beginTreesSplitResize());
            treesSplitter.Layout.Row = 2;

            this.GrandAveragesTreePanel = uipanel(this.TreeGrid, "Title", "Grand Averages", "FontWeight", "bold");
            this.GrandAveragesTreePanel.Layout.Row = 3;

            splitter = uipanel(this.MainGrid, "BorderType", "none", ...
                "BackgroundColor", [.75 .75 .75], ...
                "ButtonDownFcn", @(~, ~) this.beginTreeResize());
            splitter.Layout.Row = 2;
            splitter.Layout.Column = 2;

            this.PlotsTabGroup = uitabgroup(this.MainGrid);
            this.PlotsTabGroup.Layout.Row = 2;
            this.PlotsTabGroup.Layout.Column = 3;

            % TileGrid is a sibling in the exact same cell, toggled via
            % Visible instead of ever both showing at once (see
            % setPlotsViewMode) -- the "tile" view for multiple open plots
            % at a time that the old Java-Swing MDI desktop's
            % desktop.setDocumentArrangement(...TILED...) used to provide
            % (see migration.md); neither AppContainer nor MATLAB's own
            % Tabbed Figure Container ever had an equivalent, so this is
            % hand-rolled by reparenting each tab's content into a grid
            % cell and back (see retile/untile).
            this.TileGrid = uigridlayout(this.MainGrid, [1 1], ...
                "Padding", [2 2 2 2], "Visible", "off");
            this.TileGrid.Layout.Row = 2;
            this.TileGrid.Layout.Column = 3;

            % Wheel/key events are figure-wide; every open dataset is a tab
            % on this one shared figure, so a single dispatcher forwards
            % each event to whichever View is on the currently selected
            % plots tab (dispatchWheel/dispatchKey), rather than each View
            % wiring its own handler (which would just be overwritten by
            % the next one opened -- see SignalView/EpochView/AverageView).
            this.MainFigure.WindowScrollWheelFcn = @(~, e) this.dispatchWheel(e);
            this.MainFigure.KeyPressFcn          = @(~, e) this.dispatchKey(e);
        end

        function [resultEEG, newNode] = persistResultNode(this, resultEEG, sourceFile, ~, transformId, parentTreeNode)
        %PERSISTRESULTNODE  Save a transformation result and add it to the tree.
        %   [RESULTEEG, NEWNODE] = PERSISTRESULTNODE(THIS, RESULTEEG, SOURCEFILE,
        %   DISPLAYBASE, TRANSFORMID, PARENTTREENODE) performs the persistence
        %   step shared by onTransformation and evaluateDroppedBranch. DISPLAYBASE
        %   (the calling node's own label) is accepted but currently unused, since
        %   the tree shows each node's own transform id rather than an
        %   accumulated lineage string; kept as a parameter in case that changes:
        %     * derive a timestamped cache file in a folder named after the
        %       source dataset's own stem (sibling to SOURCEFILE), creating
        %       that folder if needed;
        %     * set RESULTEEG.File and RESULTEEG.id (just TRANSFORMID: the
        %       tree shows each node's own transform, not its lineage);
        %     * add a tree node under PARENTTREENODE with the matching icon,
        %       expand its parent and select it;
        %     * save RESULTEEG to disk and make it the workspace's current EEG.
        %   Returns the updated dataset and the new tree node.
        %
        %   The child folder MUST be named after the source's own stem, not
        %   the new node's key: treeTraverse (tree rebuild from disk) and
        %   evaluateDroppedBranch (drag-drop recursion) both locate a node's
        %   children this way, by re-deriving the same folder name from the
        %   node's own file path rather than storing it anywhere.

            % Timestamped key, e.g. "Fourier051423". The DDhhMMss format is
            % kept for backwards compatibility with existing cache trees. The
            % key stays a char array because it is used to build a file name.
            nodeKey = [transformId datestr(datetime('now'), 'DDhhMMss')]; %#ok<DATST>

            % The result is cached in a folder named after the source dataset,
            % which is how the tree is later rebuilt from disk.
            [parentDir, parentName] = fileparts(sourceFile);
            childDir = fullfile(parentDir, parentName);
            if ~exist(childDir, "dir")
                mkdir(childDir);
            end

            resultEEG.File = fullfile(childDir, [nodeKey '.mat']);
            resultEEG.id   = transformId;

            % Add the node to the data browser and select it, in whichever
            % of the two trees (Tree / GrandAveragesTree) PARENTTREENODE
            % actually belongs to -- this.Workspace.ActiveTree, kept
            % current by CreateTreeComponent's callback wiring, so running
            % a transformation on a currently-selected grand average adds
            % its result under that node in GrandAveragesTree, not the
            % unrelated data & analyses tree. WorkSpaceTree nodes are
            % always shown expanded, so there is no separate "expand the
            % parent" step to do here. The icon is the transformation's own
            % (Transformations/<transformId>/*.json's Icon), scaled down
            % for the tree row -- see WorkSpaceTree.iconForResult.
            transRoot = fullfile(this.RootDir, 'Transformations');
            newNode = this.Workspace.ActiveTree.addNode(resultEEG.id, parentTreeNode.Id, ...
                WorkSpaceTree.iconForResult(resultEEG, transRoot), resultEEG.File, ...
                WorkSpaceTree.optsFor(resultEEG));
            this.Workspace.ActiveTree.SelectedNodes = newNode;

            % Persist to disk under the variable name "EEG" and adopt it as the
            % workspace's current dataset.
            EEG = resultEEG; % saved to disk under the variable name "EEG"
            save(resultEEG.File, "EEG");
            this.Workspace.EEG = resultEEG;
        end

        function tf = isOverlayableAverage(~, targetEEG, sourceEEG)
        %ISOVERLAYABLEAVERAGE  True when two datasets are averages of equal shape.
        %   Used by evaluateDroppedBranch to decide whether dropping one
        %   dataset onto another should overlay their average plots rather than
        %   re-apply a transformation.
            tf = strcmpi(targetEEG.DataFormat, "AVERAGED") && ...
                 strcmpi(sourceEEG.DataFormat, "AVERAGED") && ...
                 isequal(size(targetEEG.data), size(sourceEEG.data));
        end

        function overlayAverage(this, targetEEG, sourceEEG)
        %OVERLAYAVERAGE  Overlay a dropped average dataset on the target's plot.
        %   Ensures the target average is shown (reusing its tab if open),
        %   then adds the source average to that tab's AverageView. Plots are
        %   uitabs in PlotsTabGroup, found directly by their own Tag (see
        %   AlakazamPlotter.plotCurrent).
            existingTab = findobj(this.PlotsTabGroup.Children, 'flat', 'Tag', targetEEG.File);
            if isempty(existingTab)
                this.Workspace.EEG = targetEEG;
                this.Plotter.plotCurrent();
                existingTab = findobj(this.PlotsTabGroup.Children, 'flat', 'Tag', targetEEG.File);
            else
                this.PlotsTabGroup.SelectedTab = existingTab(1);
            end

            view = getappdata(existingTab(1), "AverageView");
            if ~isempty(view) && isvalid(view)
                view.addDataset(sourceEEG);
            end
        end

        function [files, labels] = findGrandAverageCandidates(this)
        %FINDGRANDAVERAGECANDIDATES  Every Averaged dataset in the cache
        %   directory that is not itself a grand average -- the pool of
        %   subjects a grand average can be built from.
            files  = {};
            labels = {};
            found = dir(fullfile(this.Workspace.CacheDirectory, '**', '*.mat'));
            for i = 1:numel(found)
                file = fullfile(found(i).folder, found(i).name);
                loaded = load(file, "EEG");
                candidate = loaded.EEG;
                if ~isfield(candidate, "DataFormat") || ~strcmpi(candidate.DataFormat, "Averaged")
                    continue;
                end
                if isfield(candidate, "etc") && isfield(candidate.etc, "GrandAverage")
                    continue; % do not grand-average a grand average
                end
                files{end + 1}  = file; %#ok<AGROW>
                labels{end + 1} = sprintf('%s (%s)', candidate.id, ...
                    strjoin({candidate.bindesc.label}, ', ')); %#ok<AGROW>
            end
        end

        function saveGrandAverage(this, spec, existingNode)
        %SAVEGRANDAVERAGE  Compute a grand average from SPEC (see
        %   GrandAverageDialog) and save it, creating a new top-level node
        %   in Workspace.GrandAveragesTree (EXISTINGNODE empty) or
        %   refreshing an existing one in place (EXISTINGNODE the node
        %   being recalculated). Always GrandAveragesTree specifically
        %   (not Workspace.ActiveTree): this is only ever reached from the
        %   Grand Average tab's own "Define..."/"Recalculate" actions, not
        %   a generic current-selection flow.
            EEG = GrandAverage(spec.sources, spec.weighted);   % may throw a
                                                                % friendly
                                                                % compatibility
                                                                % error
            EEG.id = spec.name;

            gaDir = fullfile(this.Workspace.CacheDirectory, 'GrandAverages');
            if ~exist(gaDir, "dir")
                mkdir(gaDir);
            end
            safeName = matlab.lang.makeValidName(spec.name);
            EEG.File = fullfile(gaDir, [safeName '.mat']);
            save(EEG.File, "EEG");

            if isempty(existingNode)
                newNode = this.Workspace.GrandAveragesTree.addNode(EEG.id, '', ...
                    WorkSpaceTree.iconFor(EEG.DataType), EEG.File, WorkSpaceTree.optsFor(EEG));
                this.Workspace.GrandAveragesTree.SelectedNodes = newNode;
            else
                this.Workspace.GrandAveragesTree.renameNode(existingNode.Id, EEG.id);
                this.Workspace.GrandAveragesTree.setUserData(existingNode.Id, EEG.File);
            end

            this.Workspace.EEG = EEG;
            this.Plotter.plotCurrent();
        end

        function retile(this)
        %RETILE  Lay every open plot tab's content out in TileGrid, wrapped
        %   in a small handle+content wrapper (see tileWrapperFor) so each
        %   tile has a click target for reordering (onTileHandleClicked).
        %   TileOrder is synced first (drop tags for tabs that no longer
        %   exist, append any new tab's tag at the end), then wrappers are
        %   placed in that order rather than PlotsTabGroup.Children's
        %   creation order, so a click-to-swap reorder (which only mutates
        %   TileOrder) survives repeated retile() calls. Recomputes the
        %   full grid from scratch on every call (simple, cheap, avoids
        %   incremental-placement bugs). "grid" arranges tiles in a near-
        %   square rows/cols layout; "stack" is a single column, one tile
        %   per row.
            tabs = this.PlotsTabGroup.Children;
            tabTags = arrayfun(@(t) string(t.Tag), tabs);

            this.TileOrder = this.TileOrder(ismember(this.TileOrder, tabTags));
            newTags = tabTags(~ismember(tabTags, this.TileOrder));
            this.TileOrder = [this.TileOrder, newTags];

            n = numel(this.TileOrder);
            if n == 0
                return;
            end
            if strcmp(this.PlotsViewMode, "stack")
                rows = n;
                cols = 1;
            else % "grid"
                rows = max(1, floor(sqrt(n)));
                cols = ceil(n / rows);
            end
            this.TileGrid.RowHeight   = repmat({'1x'}, 1, rows);
            this.TileGrid.ColumnWidth = repmat({'1x'}, 1, cols);

            for i = 1:n
                tab = tabs(tabTags == this.TileOrder(i));
                wrapper = this.tileWrapperFor(tab);
                wrapper.Layout.Row    = ceil(i / cols);
                wrapper.Layout.Column = mod(i - 1, cols) + 1;
            end
        end

        function wrapper = tileWrapperFor(this, tab)
        %TILEWRAPPERFOR  The tile wrapper for TAB in TileGrid: a small
        %   2-row grid (title/close handle row | the view's own content),
        %   built once and reused on later retile() calls. The handle row
        %   is itself a 2-column grid: a title button (click-to-swap, see
        %   onTileHandleClicked) and a small close-x button (closeTab).
        %   uibutton, not uilabel, for both -- uibutton.ButtonPushedFcn is
        %   guaranteed reliable and already used everywhere in this app;
        %   uilabel click handling is not. The wrapper itself is tagged
        %   with the tab's own Tag, the same correlate-by-Tag idiom used
        %   everywhere else in this app, so onDeleteNode's existing
        %   tiled-content lookup finds (and deletes) the whole wrapper
        %   unchanged; the two handle buttons are tagged "tileTitle"/
        %   "tileClose" so highlightTile can find the title one specifically.
            existing = findobj(this.TileGrid.Children, 'flat', 'Tag', tab.Tag);
            if ~isempty(existing)
                wrapper = existing(1);
                return;
            end
            content = tab.Children(1); % the view's own top container, still in the tab
            wrapper = uigridlayout(this.TileGrid, [2 1], ...
                "RowHeight", {18, '1x'}, "Padding", [1 1 1 1], "RowSpacing", 1, ...
                "Tag", tab.Tag);

            handleRow = uigridlayout(wrapper, [1 2], "ColumnWidth", {'1x', 18}, ...
                "Padding", [0 0 0 0], "ColumnSpacing", 1);
            handleRow.Layout.Row = 1;

            titleBtn = uibutton(handleRow, "Text", tab.Title, "FontSize", 9, ...
                "BackgroundColor", [.85 .85 .93], "Tag", "tileTitle", ...
                "ButtonPushedFcn", @(~, ~) this.onTileHandleClicked(tab.Tag));
            titleBtn.Layout.Column = 1;

            closeBtn = uibutton(handleRow, "Text", char(215), "FontSize", 9, ...
                "FontWeight", "bold", "BackgroundColor", [.93 .82 .82], ...
                "Tag", "tileClose", "Tooltip", "Close this plot", ...
                "ButtonPushedFcn", @(~, ~) this.closeTab(tab.Tag));
            closeBtn.Layout.Column = 2;

            content.Parent = wrapper;
            content.Layout.Row = 2;
        end

        function untile(this)
        %UNTILE  Reparent every tiled plot's content back into its own tab,
        %   unwrapping it from its tile wrapper (see tileWrapperFor) first,
        %   then discarding the now-empty wrapper. The content is found by
        %   its Layout.Row (2 -- see tileWrapperFor) rather than by
        %   excluding uibuttons, since the handle row itself now also
        %   contains two uibuttons nested one level down.
            tabs = this.PlotsTabGroup.Children;
            for i = 1:numel(tabs)
                tab = tabs(i);
                wrapper = findobj(this.TileGrid.Children, 'flat', 'Tag', tab.Tag);
                if isempty(wrapper)
                    continue;
                end
                kids = wrapper(1).Children;
                content = kids(arrayfun(@(k) isequal(k.Layout.Row, 2), kids));
                if ~isempty(content)
                    content(1).Parent = tab;
                end
                delete(wrapper(1));
            end
            this.PickedTileTag = "";
        end

        function onTileHandleClicked(this, tag)
        %ONTILEHANDLECLICKED  A tile's handle button was clicked: pick it
        %   (first click, highlighted), cancel (clicking the same one
        %   again), or swap it with whichever tile was already picked
        %   (second click on a different tile) -- click-to-swap reordering,
        %   used instead of true drag-and-drop (see migration.md: MATLAB's
        %   hittest() does not support the point-based lookup live drag
        %   hit-testing would need). Also counts as clicking into that tile
        %   (see registerTileClick), so keyboard/wheel shortcuts follow the
        %   handle click even if the user never touches the tile's content.
            this.registerTileClick(tag);
            if strcmp(this.PickedTileTag, "")
                this.PickedTileTag = tag;
                this.highlightTile(tag, true);
            elseif strcmp(this.PickedTileTag, tag)
                this.highlightTile(tag, false);
                this.PickedTileTag = "";
            else
                ia = find(this.TileOrder == this.PickedTileTag, 1);
                ib = find(this.TileOrder == tag, 1);
                this.TileOrder([ia ib]) = this.TileOrder([ib ia]);
                this.highlightTile(this.PickedTileTag, false);
                this.PickedTileTag = "";
                this.retile();
            end
        end

        function highlightTile(this, tag, picked)
        %HIGHLIGHTTILE  Colour TAG's tile title button to show whether it is
        %   currently picked for a click-to-swap reorder. Searches the
        %   whole wrapper subtree (not just its direct Children), since the
        %   title button now sits one level down inside the handle row --
        %   see tileWrapperFor.
            wrapper = findobj(this.TileGrid.Children, 'flat', 'Tag', tag);
            if isempty(wrapper)
                return;
            end
            handle = findobj(wrapper(1), 'Tag', 'tileTitle');
            if isempty(handle)
                return;
            end
            if picked
                handle(1).BackgroundColor = [.6 .75 1];
            else
                handle(1).BackgroundColor = [.85 .85 .93];
            end
        end
    end

    methods
        function this = Alakazam(varargin)
        %ALAKAZAM  Construct and open the application.
        %   Resolves the application roots, makes sure EEGLAB and its plugins
        %   are available, sets up the paths, builds the single main window
        %   (toolbar strip + reserved tree cell + plots tabgroup), creates
        %   the plotter and the workspace (which builds the tree into the
        %   reserved TreeGrid cell and loads the data), and only then shows
        %   the window -- built hidden, revealed once populated.
            this.RootDir  = fileparts(mfilename('fullpath'));
            this.RepoRoot = fileparts(this.RootDir);

            EEGLabEnvironment.ensure();
            this.setupDirectories();
            this.setupMainWindow();
            this.Plotter = AlakazamPlotter(this);

            % Create the workspace (this builds the tree into TreeGrid and
            % loads the data).
            this.Workspace = WorkSpace(this);
            this.Workspace.open();
            this.MainFigure.Visible = "on";

            % Optional debug aid: expose this instance in the base workspace as
            % "AlakazamInst" (otherwise it is only reachable via "ans", which is
            % easily overwritten). Off by default.
            if this.Debug
                assignin("base", "AlakazamInst", this);
            end
        end

        function delete(this)
        %DELETE  Destructor: close the app window.
        %   Deleting MainFigure cascades to every child (toolbar, tree,
        %   plots tabgroup and all its tabs) automatically -- no explicit
        %   per-tab cleanup loop needed.
            if ~isempty(this.MainFigure) && isvalid(this.MainFigure)
                delete(this.MainFigure);
            end
        end

        function openSettings(this)
        %OPENSETTINGS  Open the global settings dialog (toolbar callback).
        %   Applied changes refresh the open views via onSettingsChanged.
            SettingsDialog(@() this.onSettingsChanged());
        end

        function onSettingsChanged(this)
        %ONSETTINGSCHANGED  Re-draw open views so changed settings take effect.
            for k = 1:numel(this.PlotsTabGroup.Children)
                tab = this.PlotsTabGroup.Children(k);
                if ~isgraphics(tab) || ~isvalid(tab)
                    continue;
                end
                for viewName = ["AverageView", "EpochView"]
                    view = getappdata(tab, char(viewName));
                    if ~isempty(view) && isvalid(view)
                        try
                            view.redraw();
                        catch err
                            warning('Alakazam:viewRefresh', ...
                                'Could not refresh %s: %s', char(viewName), err.message);
                        end
                    end
                end
            end
        end

        function onTransformation(this, entry)
        %ONTRANSFORMATION  Toolbar callback: run a transformation on the current EEG.
        %   ONTRANSFORMATION(THIS, ENTRY) executes the transformation whose
        %   entry file is ENTRY (for example "Fourier.m") on the selected
        %   dataset, stores the result as a new child node, and plots it. The
        %   stem of ENTRY is both the transformation id and the function that
        %   is invoked with feval. Two-arg form (was THIS, ~, ~, ENTRY): a
        %   uibutton's ButtonPushedFcn passes (source, eventdata), not a
        %   Toolstrip gallery item's three -- see BuildToolbarAlakazam.
        %
        %   A transformation returns [EEG, params]; if it instead returns a
        %   graphics handle it was a pure plot and nothing is persisted.
            % The gallery passes the entry file name (e.g. "Fourier.m"); its
            % stem is the transformation id and the function to call. The '.'
            % is a char so the element-wise comparison works. Computed before
            % the try block (cheap, pure string parsing) so it is always
            % available in the catch block below, even if something upstream
            % of the feval call itself somehow fails.
            entryName   = char(entry);
            transformId = entryName(1:find(entryName == '.', 1, "last") - 1);

            try
                % Run from the repository root (historic behaviour): individual
                % plugins may resolve resources relative to it. Restore the
                % previous directory on exit, including on error.
                originalDir = cd(this.RepoRoot);
                restoreDir  = onCleanup(@() cd(originalDir)); % restores cwd at method exit

                % Pointer is figure-wide (every dataset is a tab on the one
                % shared MainFigure), so no per-tab lookup is needed here.
                this.MainFigure.Pointer = "watch";

                % Apply the transformation to the current dataset.
                [result.EEG, usedParams] = feval(transformId, this.Workspace.EEG);

                if ishandle(result.EEG)
                    % The plugin returned a graphics handle, not a dataset: it
                    % was a pure plot, so there is nothing to persist.
                    return;
                end

                % Record how the result was produced, so it can be re-applied
                % when this branch is later dragged onto another dataset.
                % Call is just the transformation id (a plain function name,
                % fed straight to feval on replay -- see evaluateDroppedBranch);
                % it used to be a fake "EEG=<id>(x.EEG);" command string that
                % was then re-parsed with strfind, which added a redundant,
                % error-prone round trip for no benefit.
                result.EEG.Call = transformId;
                if isstruct(usedParams)
                    result.EEG.params = usedParams;
                else
                    result.EEG.params = struct('Param', usedParams);
                end

                % Persist under the selected node (its file is the source cache
                % file at this point) and display the result. ActiveTree
                % (see onSelectionChanged/onNodeDoubleClicked/
                % onContextMenuAction) is whichever of the two trees that
                % selection actually lives in -- Tree or GrandAveragesTree,
                % since a transformation can be run on a currently-selected
                % grand average too.
                displayBase = this.Workspace.ActiveTree.SelectedNodes.Name;
                this.persistResultNode(result.EEG, result.EEG.File, displayBase, ...
                    transformId, this.Workspace.ActiveTree.SelectedNodes);

                this.Plotter.plotCurrent();
                this.MainFigure.Pointer = "arrow";

            catch ME
                this.MainFigure.Pointer = "arrow";
                this.showTransformationError(transformId, ME);
            end
        end

        function showTransformationError(this, transformId, ME)
        %SHOWTRANSFORMATIONERROR  Calm, explanatory report of a failed
        %   transformation, instead of MATLAB's default raw stack trace.
        %   A failed transformation is almost always a data-format mismatch
        %   (this dataset is not yet segmented / averaged / in the frequency
        %   domain, whichever this step needs) rather than a real crash --
        %   the previous handler already showed a dialog with ME.message but
        %   then rethrew ME anyway, which is what dumped the full stack
        %   trace to the command window on top of it. There is nothing left
        %   to rethrow to: this is the top of the callback chain from the
        %   ribbon, so swallowing it here (after informing the user) is the
        %   right place to stop it.
            reason = ME.message;
            % Every Alakazam-authored guard clause writes 'Problem in
            % <Transform>: ...'; that prefix is redundant once the dialog's
            % own title already names the transform, so strip it for a
            % cleaner read. A plain MATLAB error (no such prefix, e.g. an
            % unguarded shape mismatch inside a transformation with no
            % explicit data-format check of its own) is shown as-is.
            prefix = sprintf('Problem in %s: ', transformId);
            if startsWith(reason, prefix)
                reason = extractAfter(reason, prefix);
            end

            message = { ...
                sprintf('%s could not run on this dataset:', transformId), ...
                '', ...
                reason};
            if ~startsWith(ME.identifier, 'Alakazam:')
                % An unguarded, "native" MATLAB error -- almost always still
                % a data-format mismatch in practice (this step expects a
                % shape the current dataset doesn't have), so add the same
                % general hint an explicit guard clause would have given.
                message{end + 1} = '';
                message{end + 1} = ['This usually means the selected dataset is not the ' ...
                    'right kind of data for this step -- for example, it needs segmented ' ...
                    '(epoched) data, an average, or frequency-domain data, and this ' ...
                    'dataset is not yet in that form.'];
            end

            uialert(this.MainFigure, message, sprintf('Couldn''t run %s', transformId), ...
                'Icon', 'warning');
        end

        function evaluateDroppedBranch(this, sourceFile, targetNode)
        %EVALUATEDROPPEDBRANCH  Re-apply a dragged branch onto a target dataset.
        %   EVALUATEDROPPEDBRANCH(THIS, SOURCEFILE, TARGETNODE) walks the branch
        %   rooted at SOURCEFILE and re-applies each stored transformation onto
        %   the dataset at TARGETNODE, chaining down the tree while the source
        %   branch has children.
        %
        %   Special case: dropping one AVERAGED dataset onto a matching AVERAGED
        %   dataset overlays their plots instead of transforming.
            atLeaf     = false;
            targetFile = targetNode.UserData;

            while ~atLeaf
                targetStruct = load(targetFile, "EEG");
                sourceStruct = load(sourceFile, "EEG");

                % Call is just the transformation id (see onTransformation); no
                % parsing needed.
                transformId = char(sourceStruct.EEG.Call);

                if this.isOverlayableAverage(targetStruct.EEG, sourceStruct.EEG)
                    % Overlay the dropped average on top of the target average.
                    this.overlayAverage(targetStruct.EEG, sourceStruct.EEG);
                    atLeaf = true;
                else
                    % General case: re-apply the stored transformation to the
                    % target, carrying over the source's call and parameters.
                    % The id is stored data (loaded from a .mat file that may
                    % predate a Transformations-folder cleanup), not something
                    % just derived from code on disk, so it's validated before
                    % feval rather than failing with a cryptic "undefined
                    % function" error.
                    if exist(transformId, "file") ~= 2
                        throw(MException('Alakazam:evaluateDroppedBranch', ...
                            ['Stored transformation ''%s'' no longer exists ' ...
                             '(its .m file is missing from the Transformations ' ...
                             'folder). Cannot replay this branch.'], transformId));
                    end
                    [result.EEG, ~] = feval(transformId, targetStruct.EEG, sourceStruct.EEG.params);
                    result.EEG.Call   = sourceStruct.EEG.Call;
                    result.EEG.params = sourceStruct.EEG.params;

                    [result.EEG, newNode] = this.persistResultNode(result.EEG, ...
                        targetStruct.EEG.File, sourceStruct.EEG.id, transformId, targetNode);

                    % Descend: if the source has a child dataset, continue the
                    % chain with it against the newly created node.
                    [srcDir, srcName] = fileparts(sourceFile);
                    childDir = fullfile(srcDir, srcName);
                    if exist(childDir, "dir")
                        targetNode = newNode;
                        targetFile = result.EEG.File;
                        childMat   = dir(fullfile(childDir, '*.mat'));
                        sourceFile = fullfile(childDir, childMat.name);
                    else
                        atLeaf = true;
                    end
                end
            end
        end

        function onListEvents(this)
        %ONLISTEVENTS  Context-menu callback: list unique event types and
        %   their occurrence counts for the selected dataset in a message
        %   box. The menu item is disabled for epoched/averaged data (its
        %   eligibility is baked into the node at creation time -- see
        %   WorkSpaceTree.optsFor), so this only ever runs for continuous
        %   data; root nodes are allowed here (unlike Rename/Delete), since a root
        %   node is normally the raw continuous import -- the most common
        %   case for wanting to see what events it contains.
            node = this.Workspace.ActiveTree.SelectedNodes;
            if isempty(node)
                return; % nothing selected
            end

            file = node.UserData;
            if isempty(file) || exist(file, "file") ~= 2
                return;
            end

            loaded = load(file, "EEG");
            EEG = loaded.EEG;
            titleText = sprintf('Events in "%s"', node.Name);

            if ~isfield(EEG, "event") || isempty(EEG.event)
                msgbox("This dataset has no events.", titleText);
                return;
            end

            % Event types may be numeric or char/string across loaders;
            % string() normalises both so unique() groups them correctly.
            types = strings(1, numel(EEG.event));
            for i = 1:numel(EEG.event)
                types(i) = string(EEG.event(i).type);
            end
            [uTypes, ~, ic] = unique(types);
            counts = accumarray(ic, 1);
            [counts, order] = sort(counts, "descend");
            uTypes = uTypes(order);

            lines = strings(numel(uTypes), 1);
            for i = 1:numel(uTypes)
                lines(i) = sprintf("%s: %d", uTypes(i), counts(i));
            end
            msgbox(char(strjoin(lines, newline)), titleText);
        end

        function onRenameNode(this)
        %ONRENAMENODE  Context-menu callback: rename the selected node.
        %   Prompts for a new label and persists it both to the tree (its
        %   display name) and to the underlying cached dataset's id
        %   (EEG.id, re-saved to its own file) -- not just the currently
        %   active dataset, since a right-click need not target it. Root
        %   nodes are not renamable here.
            node = this.Workspace.ActiveTree.SelectedNodes;
            if isempty(node) || node.IsRoot
                return; % nothing selected, or a root node
            end

            answer = inputdlg('New name:', 'Rename node', 1, {node.Name});
            if isempty(answer)
                return; % cancelled
            end
            newName = strtrim(answer{1});
            if isempty(newName)
                return;
            end

            file = node.UserData;
            loaded = load(file, "EEG");
            loaded.EEG.id = newName;
            EEG = loaded.EEG; % saved to disk under the variable name "EEG"
            save(file, "EEG");

            this.Workspace.ActiveTree.renameNode(node.Id, newName);

            % Keep the in-memory active dataset in sync if it is this node.
            if isequal(this.Workspace.EEG.File, file)
                this.Workspace.EEG.id = newName;
            end
        end

        function onDeleteNode(this)
        %ONDELETENODE  Context-menu callback: delete the selected node and
        %   every dataset computed from it, on disk and in the tree, after
        %   confirmation. Root nodes are not deletable here: that would also
        %   remove everything ever computed from the source recording, a
        %   much bigger action than pruning a single branch.
            node = this.Workspace.ActiveTree.SelectedNodes;
            if isempty(node) || node.IsRoot
                return; % nothing selected, or a root node
            end

            answer = questdlg( ...
                sprintf('Delete "%s" and everything computed from it? This cannot be undone.', node.Name), ...
                'Delete node', 'Delete', 'Cancel', 'Cancel');
            if ~strcmp(answer, 'Delete')
                return;
            end

            % A node's descendants are cached in a folder named after its own
            % stem, sibling to its own file (see persistResultNode).
            file = node.UserData;
            [folder, stem] = fileparts(file);
            childDir = fullfile(folder, stem);

            % Close any open tab for this node or one of its descendants
            % before their cache files disappear out from under them. Plots
            % are uitabs in PlotsTabGroup, found directly by their own Tag
            % (see AlakazamPlotter.plotCurrent). If tiled, the tab's content
            % has been reparented into TileGrid (see retile) and tagged the
            % same way -- that copy must be deleted too, or it becomes an
            % orphaned tile that outlives its own tree node.
            descendantFiles = {file};
            if exist(childDir, "dir")
                found = dir(fullfile(childDir, '**', '*.mat'));
                for k = 1:numel(found)
                    descendantFiles{end + 1} = fullfile(found(k).folder, found(k).name); %#ok<AGROW>
                end
            end
            for k = 1:numel(descendantFiles)
                if strcmp(this.PickedTileTag, descendantFiles{k})
                    this.PickedTileTag = ""; % avoid a stale picked-tag pointing at nothing
                end
                tiledContent = findobj(this.TileGrid.Children, 'flat', 'Tag', descendantFiles{k});
                if ~isempty(tiledContent)
                    delete(tiledContent);
                end
                tab = findobj(this.PlotsTabGroup.Children, 'flat', 'Tag', descendantFiles{k});
                if ~isempty(tab)
                    delete(tab);
                end
            end

            if exist(file, "file")
                delete(file);
            end
            if exist(childDir, "dir")
                rmdir(childDir, "s");
            end

            this.Workspace.ActiveTree.removeNode(node.Id);
        end

        function closeTab(this, tag)
        %CLOSETAB  Close just the view for TAG (a dataset's uitab and, if
        %   tiled, its tile) -- the underlying dataset and tree node are
        %   left untouched, so reopening it just means selecting its tree
        %   node again. Lighter than onDeleteNode, which also destroys the
        %   dataset on disk. Wired as the right-click "Close" menu on each
        %   plot tab (AlakazamPlotter.plotCurrent) and the close-x button
        %   on each tile handle (tileWrapperFor).
            if strcmp(this.PickedTileTag, tag)
                this.PickedTileTag = "";
            end
            this.TileOrder = this.TileOrder(this.TileOrder ~= tag);
            tiledContent = findobj(this.TileGrid.Children, 'flat', 'Tag', tag);
            if ~isempty(tiledContent)
                delete(tiledContent);
            end
            tab = findobj(this.PlotsTabGroup.Children, 'flat', 'Tag', tag);
            if ~isempty(tab)
                delete(tab);
            end
        end

        function onDefineGrandAverage(this)
        %ONDEFINEGRANDAVERAGE  Toolbar callback (Grand Average tab): define
        %   a brand new grand average. Lets the analyst pick which Averaged
        %   subject datasets to combine, name it, and choose weighted/
        %   unweighted combining (GrandAverageDialog), then computes and
        %   saves it as a new top-level node in the Grand Averages tree.
            [candidateFiles, candidateLabels] = this.findGrandAverageCandidates();
            if numel(candidateFiles) < 2
                msgbox(['A grand average needs at least two Averaged datasets ' ...
                        'to combine, and fewer than two were found in this ' ...
                        'workspace. Run the Average transformation on more ' ...
                        'subjects first.'], 'Not enough subjects');
                return;
            end

            spec = GrandAverageDialog(candidateFiles, candidateLabels, []);
            if isempty(spec)
                return; % cancelled
            end

            try
                this.saveGrandAverage(spec, []);
            catch err
                warndlg(err.message, 'Could not compute grand average');
            end
        end

        function onRecalculateNode(this)
        %ONRECALCULATENODE  Context-menu callback: revisit an existing grand
        %   average's membership. Reopens GrandAverageDialog pre-filled with
        %   its current sources/weighting (its name is fixed), lets the
        %   analyst add/remove subjects or change the weighting, then
        %   recomputes and re-saves it in place. Only ever reachable for a
        %   Grand Average node -- the menu item is disabled otherwise (its
        %   eligibility is baked into the node at creation time, see
        %   WorkSpaceTree.optsFor).
            node = this.Workspace.ActiveTree.SelectedNodes;
            if isempty(node)
                return;
            end

            file = node.UserData;
            loaded = load(file, "EEG");
            if ~isfield(loaded.EEG, "etc") || ~isfield(loaded.EEG.etc, "GrandAverage")
                return; % not a grand average; nothing to recalculate
            end

            existingSpec = struct('name', loaded.EEG.id, ...
                'sources', {loaded.EEG.etc.GrandAverage.sources}, ...
                'weighted', loaded.EEG.etc.GrandAverage.weighted);

            [candidateFiles, candidateLabels] = this.findGrandAverageCandidates();
            spec = GrandAverageDialog(candidateFiles, candidateLabels, existingSpec);
            if isempty(spec)
                return; % cancelled
            end

            try
                this.saveGrandAverage(spec, node);
            catch err
                warndlg(err.message, 'Could not compute grand average');
            end
        end

        function onNodeDropped(this, eventData, sourceTree)
        %ONNODEDROPPED  Tree callback: handle a node dropped onto another node.
        %   SOURCETREE is whichever of Workspace.Tree/GrandAveragesTree
        %   raised the event (see WorkSpace.CreateTreeComponent); recorded
        %   as Workspace.ActiveTree so evaluateDroppedBranch's
        %   persistResultNode call below adds the new node to the same
        %   tree the drop happened in. No modifier key (EVENTDATA.REPARENTED
        %   true) moves the node within the tree -- WorkSpaceTree has
        %   already mirrored this in its own bookkeeping, so there is
        %   nothing further to do here (it is never persisted to disk;
        %   treeTraverse rebuilds the tree from the cache folder structure
        %   on the next full reload, same as the old jTree behaviour). Ctrl
        %   held (REPARENTED false) re-applies the dragged branch onto the
        %   target via evaluateDroppedBranch instead. Root nodes are ignored.
            this.Workspace.ActiveTree = sourceTree;

            % Run from the repository root (historic behaviour): the drop
            % triggers plugins that may resolve resources relative to it.
            % Restore the previous directory when this callback returns.
            originalDir = cd(this.RepoRoot);
            restoreDir  = onCleanup(@() cd(originalDir)); % restores cwd at callback exit

            if eventData.Source.IsRoot
                return; % a root node was dropped; ignore
            end

            if ~eventData.Reparented % Ctrl held: re-apply the dragged branch to the target
                this.evaluateDroppedBranch(eventData.Source.UserData, eventData.Target);
            end
        end

        function onSelectionChanged(this, eventData, sourceTree)
        %ONSELECTIONCHANGED  Tree callback: load and plot the newly selected
        %   dataset. SOURCETREE (see onNodeDropped) becomes Workspace.
        %   ActiveTree, so later actions (rename/delete/run a
        %   transformation) act on whichever of the two trees this
        %   selection came from.
            this.Workspace.ActiveTree = sourceTree;
            loaded = load(eventData.UserData, "EEG");
            this.Workspace.EEG = loaded.EEG;
            this.Plotter.plotCurrent();
        end

        function onNodeDoubleClicked(this, eventData, sourceTree)
        %ONNODEDOUBLECLICKED  Tree callback: (re)load and plot the double-clicked
        %   dataset. Loads it itself rather than relying on a preceding single
        %   click's SelectionChangedFcn having already done so, since
        %   WorkSpaceTree does not guarantee that ordering. SOURCETREE: see
        %   onNodeDropped.
            this.Workspace.ActiveTree = sourceTree;
            loaded = load(eventData.UserData, "EEG");
            this.Workspace.EEG = loaded.EEG;
            this.Plotter.plotCurrent();
        end

        function onContextMenuAction(this, eventData, sourceTree)
        %ONCONTEXTMENUACTION  Tree callback: dispatch a right-click context
        %   menu action (List events / Rename / Recalculate / Delete) --
        %   WorkSpaceTree has already selected EVENTDATA.NODE before invoking
        %   this, matching the old right-click-selects-first behaviour, so
        %   each handler below can keep reading Workspace.ActiveTree.
        %   SelectedNodes; SOURCETREE (see onNodeDropped) is recorded as
        %   Workspace.ActiveTree first so that is always the tree the
        %   right-click actually happened in.
            this.Workspace.ActiveTree = sourceTree;
            switch eventData.Action
                case 'listEvents'
                    this.onListEvents();
                case 'rename'
                    this.onRenameNode();
                case 'recalculate'
                    this.onRecalculateNode();
                case 'delete'
                    this.onDeleteNode();
            end
        end

        function onRibbonAction(this, id)
        %ONRIBBONACTION  AlakazamRibbon.ItemPushedFcn: dispatch a ribbon
        %   button press. ID is either a fixed action string (the Home and
        %   Grand Average tab buttons) or "transform:<Entry>" (a Tools tab
        %   transformation button, see AlakazamRibbon.transformationGroups).
            switch id
                case 'openWorkspace'
                    this.Workspace.load();
                case 'saveWorkspace'
                    this.Workspace.save();
                case 'editWorkspace'
                    this.Workspace.edit();
                case 'clearWorkspace'
                    this.Workspace.rawclear();
                case 'settings'
                    this.openSettings();
                case 'defineGrandAverage'
                    this.onDefineGrandAverage();
                case 'viewTabs'
                    this.setPlotsViewMode("tabs");
                case 'viewGrid'
                    this.setPlotsViewMode("grid");
                case 'viewStack'
                    this.setPlotsViewMode("stack");
                otherwise
                    if startsWith(id, "transform:")
                        this.onTransformation(extractAfter(id, "transform:"));
                    end
            end
        end

        function setPlotsViewMode(this, mode)
        %SETPLOTSVIEWMODE  Switch the plots area between "tabs" (one dataset
        %   shown at a time, PlotsTabGroup) and the two tiled arrangements,
        %   "grid" and "stack" (every open dataset shown at once, TileGrid)
        %   -- see retile/untile. Switching directly between "grid" and
        %   "stack" just re-lays-out TileGrid in place, without dropping
        %   back to Tabs first.
            if strcmp(mode, this.PlotsViewMode)
                return;
            end
            this.PlotsViewMode = mode;
            if strcmp(mode, "tabs")
                this.untile();
                this.PlotsTabGroup.Visible = "on";
                this.TileGrid.Visible      = "off";
            else
                this.retile();
                this.TileGrid.Visible      = "on";
                this.PlotsTabGroup.Visible = "off";
            end
        end

        function refreshPlotsView(this)
        %REFRESHPLOTSVIEW  Re-tile the plots area if currently in a tiled
        %   mode ("grid" or "stack"). Called by AlakazamPlotter.plotCurrent
        %   after opening or selecting a tab, so a newly opened dataset
        %   appears in the tile grid immediately if tiling is already
        %   active. No-op in Tabs mode.
            if ~strcmp(this.PlotsViewMode, "tabs")
                this.retile();
            end
        end

        function onCloseRequest(this)
        %ONCLOSEREQUEST  MainFigure's CloseRequestFcn: destroy the app.
        %   delete(this) closes MainFigure directly (not via
        %   CloseRequestFcn again -- delete() bypasses close callbacks), so
        %   this cannot recurse.
            delete(this);
        end

        function registerTileClick(this, tag)
        %REGISTERTILECLICK  Record TAG (a tab's Tag) as the view last
        %   clicked/interacted with. Wired by AlakazamPlotter as every
        %   View's ActivatedFcn, so keyboard/wheel shortcuts keep tracking
        %   whichever tile the user is actually working in once several are
        %   visible at once in Grid/Stack mode -- see activeTileTag,
        %   dispatchWheel and dispatchKey.
            this.LastClickedTag = string(tag);
        end

        function tag = activeTileTag(this)
        %ACTIVETILETAG  The tab Tag that keyboard/wheel shortcuts should
        %   target. In Tabs mode that is unambiguous (PlotsTabGroup.
        %   SelectedTab): only one plot is ever visible. In Grid/Stack mode
        %   several tiles are visible at once and PlotsTabGroup.SelectedTab
        %   does not change as the user clicks between them (the tabgroup
        %   itself is hidden), so LastClickedTag (kept current by
        %   registerTileClick) is used instead.
            if strcmp(this.PlotsViewMode, "tabs")
                tab = this.PlotsTabGroup.SelectedTab;
                if isempty(tab) || ~isvalid(tab)
                    tag = "";
                else
                    tag = string(tab.Tag);
                end
            else
                tag = this.LastClickedTag;
            end
        end

        function dispatchWheel(this, eventData)
        %DISPATCHWHEEL  Forward a mouse-wheel event to the SignalView on the
        %   active tile (see activeTileTag), if any. Wheel events are
        %   figure-wide; every open dataset is a uitab on the one shared
        %   MainFigure, so they are dispatched centrally here rather than
        %   each SignalView wiring its own fig.WindowScrollWheelFcn (see
        %   SignalView.buildGraphics and setupMainWindow).
            tag = this.activeTileTag();
            if strcmp(tag, "")
                return;
            end
            tab = findobj(this.PlotsTabGroup.Children, 'flat', 'Tag', tag);
            if isempty(tab) || ~isvalid(tab(1))
                return;
            end
            view = getappdata(tab(1), "SignalView");
            if ~isempty(view) && isvalid(view)
                view.onWheel(eventData);
            end
        end

        function dispatchKey(this, eventData)
        %DISPATCHKEY  Forward a key-press event to whichever View (EpochView
        %   or AverageView -- the only two with keyboard navigation) is on
        %   the active tile (see activeTileTag), if any. See dispatchWheel.
            tag = this.activeTileTag();
            if strcmp(tag, "")
                return;
            end
            tab = findobj(this.PlotsTabGroup.Children, 'flat', 'Tag', tag);
            if isempty(tab) || ~isvalid(tab(1))
                return;
            end
            for viewName = ["EpochView", "AverageView", "FourierView"]
                view = getappdata(tab(1), char(viewName));
                if ~isempty(view) && isvalid(view)
                    view.onKey(eventData);
                    return;
                end
            end
        end

        function beginTreeResize(this)
        %BEGINTREERESIZE  Splitter panel's ButtonDownFcn (see setupMainWindow):
        %   start dragging the tree/plots divider. A plain uigridlayout has
        %   no built-in resizable divider, so this hand-rolls one: track the
        %   mouse via MainFigure's WindowButtonMotionFcn/WindowButtonUpFcn
        %   until release, live-updating MainGrid's tree column width.
            this.MainFigure.WindowButtonMotionFcn = @(~, ~) this.dragTreeResize();
            this.MainFigure.WindowButtonUpFcn     = @(~, ~) this.endTreeResize();
            this.MainFigure.Pointer = "left";
        end

        function dragTreeResize(this)
        %DRAGTREERESIZE  WindowButtonMotionFcn while dragging the splitter
        %   (see beginTreeResize): resize the tree column to track the
        %   mouse, clamped to a sane range.
            mousePos = this.MainFigure.CurrentPoint;
            treeLeft = this.TreeGrid.Position(1);
            newWidth = max(150, min(600, mousePos(1) - treeLeft));
            this.MainGrid.ColumnWidth{1} = newWidth;
        end

        function endTreeResize(this)
        %ENDTREERESIZE  WindowButtonUpFcn while dragging the splitter (see
        %   beginTreeResize): stop tracking the mouse.
            this.MainFigure.WindowButtonMotionFcn = [];
            this.MainFigure.WindowButtonUpFcn     = [];
            this.MainFigure.Pointer = "arrow";
        end

        function beginTreesSplitResize(this)
        %BEGINTREESSPLITRESIZE  Data/Grand-Averages splitter's ButtonDownFcn
        %   (see setupMainWindow): start dragging the divider between the two
        %   workspace trees -- the same hand-rolled pattern as
        %   beginTreeResize, tracking the mouse via MainFigure's
        %   WindowButtonMotionFcn/WindowButtonUpFcn until release.
            this.MainFigure.WindowButtonMotionFcn = @(~, ~) this.dragTreesSplitResize();
            this.MainFigure.WindowButtonUpFcn     = @(~, ~) this.endTreesSplitResize();
            this.MainFigure.Pointer = "top";
        end

        function dragTreesSplitResize(this)
        %DRAGTREESSPLITRESIZE  WindowButtonMotionFcn while dragging the tree
        %   splitter (see beginTreesSplitResize): resize the Data & Analyses
        %   row to track the mouse, leaving Grand Averages ('1x') to fill the
        %   remainder, clamped so neither panel can be dragged to nothing.
            mousePos  = this.MainFigure.CurrentPoint;
            treeTop   = this.TreeGrid.Position(2) + this.TreeGrid.Position(4);
            available = this.TreeGrid.Position(4) - 3; % minus the splitter row itself
            newHeight = max(60, min(available - 60, treeTop - mousePos(2)));
            this.TreeGrid.RowHeight{1} = newHeight;
        end

        function endTreesSplitResize(this)
        %ENDTREESSPLITRESIZE  WindowButtonUpFcn while dragging the tree
        %   splitter (see beginTreesSplitResize): stop tracking the mouse.
            this.MainFigure.WindowButtonMotionFcn = [];
            this.MainFigure.WindowButtonUpFcn     = [];
            this.MainFigure.Pointer = "arrow";
        end
    end
end
