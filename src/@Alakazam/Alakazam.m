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
        RibbonBaseHeight   = 120  % fixed ribbon row height (px); see setupMainWindow. Never grows: an
                                  % overflowing group now opens as a floating popup instead (see
                                  % AlakazamRibbon's PopupComponent), so this stays constant.
        TreeGrid        % uigridlayout cell reserved for the workspace tree area (split top/bottom)
        DataTreePanel           % uipanel hosting WorkSpace.Tree (data & analyses), top third of TreeGrid
        GrandAveragesTreePanel  % uipanel hosting WorkSpace.GrandAveragesTree, middle third of TreeGrid
        ReportsTreePanel        % uipanel hosting WorkSpace.ReportsTree, bottom third of TreeGrid
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
        % Implementations live in @Alakazam/<name>.m; declared here
        % only so their private access is preserved.
        setupDirectories(this)
        setupMainWindow(this)
        [resultEEG, newNode] = persistResultNode(this, resultEEG, sourceFile, ~, transformId, parentTreeNode)
        nodes = collectBranchTree(~, sourceFile)
        p = templateParams(~, p)
        newNode = applyStepToTarget(this, transformId, params, targetNode)
        steps = readTemplate(~, file)
        tf = isOverlayableAverage(~, targetEEG, sourceEEG)
        overlayAverage(this, targetEEG, sourceEEG)
        [files, labels, kinds] = findGrandAverageCandidates(this)
        deleteBranchFiles(this, file)
        bins = candidateBinLabels(this, candidateFiles)
        groups = candidateGroupLabels(this, candidateFiles)
        entries = collectMeasurementEntries(this)
        entries = collectSpectralEntries(this)
        entries = collectEntriesWithField(this, fieldName)
        restoreDir = enterRepoRoot(this)
        loadAndPlotNode(this, eventData, sourceTree, action)
        dispatchToActiveView(this, eventData, viewNames, methodName)
        saveGrandAverage(this, spec, existingNode)
        retile(this)
        wrapper = tileWrapperFor(this, tab)
        untile(this)
        onTileHandleClicked(this, tag)
        highlightTile(this, tag, picked)
    end

    methods
        % Public methods; implementations live in @Alakazam/<name>.m.
        % The constructor and destructor stay inline below.
        openSettings(this)
        onSettingsChanged(this)
        onTransformation(this, entry)
        restoreFocus(this)
        showTransformationError(this, transformId, ME)
        evaluateDroppedBranch(this, sourceFile, targetNode)
        onListEvents(this)
        onRenameNode(this)
        onDeleteNode(this)
        closeTab(this, tag)
        onDefineGrandAverage(this)
        onClusterStats(this)
        onClearOtherAnalyses(this)
        onExportGrandAverages(this)
        onExportErpset(this)
        onExportMeasurements(this)
        onExportSpectral(this)
        onRecalculateNode(this)
        recalculateTransformNode(this, node, ownEEG)
        recalculateAffectedGrandAverages(this, touchedFiles)
        plan = planDescendantRecalc(this, parentFile, parentEEG)
        onNodeDropped(this, eventData, sourceTree)
        onTreeRenderError(this, eventData, sourceTree)
        onSelectionChanged(this, eventData, sourceTree)
        onNodeDoubleClicked(this, eventData, sourceTree)
        EEG = loadNodeEEG(this, file, action)
        onContextMenuAction(this, eventData, sourceTree)
        onApplyToAllRawFiles(this)
        onSaveTemplate(this)
        onApplyTemplate(this)
        onRibbonAction(this, id)
        setPlotsViewMode(this, mode)
        refreshPlotsView(this)
        onCloseRequest(this)
        registerTileClick(this, tag)
        onPlotTabSelected(this, eventData)
        syncActiveDataset(this, file)
        tag = activeTileTag(this)
        dispatchWheel(this, eventData)
        dispatchKey(this, eventData)
        beginTreeResize(this)
        dragTreeResize(this)
        endTreeResize(this)
        beginTreesSplitResize(this)
        dragTreesSplitResize(this)
        endTreesSplitResize(this)

        function this = Alakazam(varargin)
        %ALAKAZAM  Construct and open the application.
        %   ALAKAZAM() opens with the repository's default workspace
        %   (DefaultWorkSpace.wksp). ALAKAZAM(workspaceFile) opens with a
        %   specific workspace instead -- see startAlakazam and
        %   WorkSpace's own constructor for what WORKSPACEFILE may be (a
        %   bare name resolved next to DefaultWorkSpace.wksp, or any
        %   relative/absolute path to a .wksp file).
        %
        %   Resolves the application roots, makes sure EEGLAB and its plugins
        %   are available, sets up the paths, builds the single main window
        %   (toolbar strip + reserved tree cell + plots tabgroup), creates
        %   the plotter and the workspace (which builds the tree into the
        %   reserved TreeGrid cell and loads the data), and only then shows
        %   the window -- built hidden, revealed once populated.
            this.RootDir  = fileparts(fileparts(mfilename('fullpath')));  % up from @Alakazam to src
            this.RepoRoot = fileparts(this.RootDir);

            % Close any figures left over from a previous session in this
            % same MATLAB session (a leftover from the old Java-Swing
            % ToolGroup shell's docking mechanism, see migration.md, which
            % could leave stray windows behind on a crash) -- done here,
            % not inside setupDirectories (which is otherwise purely about
            % putting the source tree on the path), so this genuinely
            % figure-wide side effect is visible at the one call site that
            % matters, rather than hidden inside a method whose name gives
            % no hint of it.
            close all;
            EEGLabEnvironment.ensure();
            this.setupDirectories();
            this.setupMainWindow();
            this.Plotter = AlakazamPlotter(this);

            % Create the workspace (its constructor builds the tree into
            % TreeGrid; .open() below is the separate step that actually
            % loads the data).
            if isempty(varargin)
                this.Workspace = WorkSpace(this);
            else
                this.Workspace = WorkSpace(this, varargin{1});
            end

            % Shown here, not after .open(): the tree is already attached
            % to TreeGrid (setupMainWindow's own "build hidden, reveal once
            % populated" requirement, satisfied by the constructor above),
            % so nothing further needs to stay hidden -- and showing the
            % window now is what lets beginBusy (called by every loader
            % .open() runs, e.g. loadSETFile) put up a real "Loading
            % <file>..." progress dialog for each raw file during startup,
            % instead of silently falling back to a watch cursor on a
            % figure nobody can see yet.
            this.MainFigure.Visible = "on";
            this.Workspace.open();

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
    end
end
