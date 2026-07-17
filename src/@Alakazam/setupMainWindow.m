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
    % Keep Workspace.EEG (and the tree's own selection) in sync
    % when the user switches tabs by clicking a tab header
    % directly, not just by clicking a tree node -- see
    % syncActiveDataset for why this matters.
    this.PlotsTabGroup.SelectionChangedFcn = @(~, e) this.onPlotTabSelected(e);

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
