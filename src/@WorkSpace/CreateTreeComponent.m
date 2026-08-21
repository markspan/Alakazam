function CreateTreeComponent(this)
%CREATETREECOMPONENT  Build the three WorkSpaceTree components: Tree (data
%   & analyses) into Alakazam.DataTreePanel, GrandAveragesTree into
%   Alakazam.GrandAveragesTreePanel, ReportsTree into
%   Alakazam.ReportsTreePanel (top/middle/bottom thirds of the reserved
%   TreeGrid area -- see Alakazam.setupMainWindow). WorkSpaceTree is a
%   uihtml/CEF component and, unlike the old Java-Swing uiextras.jTree.Tree,
%   needs a real uifigure-family host; each is built directly into its own
%   panel, no separate wrapper object needed.
%
%   All three trees wire back to the SAME Alakazam callback methods
%   (onSelectionChanged, onNodeDoubleClicked, onNodeDropped,
%   onContextMenuAction, onTreeRenderError) -- those only ever need the
%   node struct the event already carries, so nothing about their bodies
%   is tree-specific. The
%   source WorkSpaceTree instance is passed as each callback's second
%   argument (captured as this.Tree / this.GrandAveragesTree /
%   this.ReportsTree at call time, not construction time, since these
%   anonymous functions run long after all three properties are assigned)
%   so those handlers can update this.ActiveTree -- the tree a later
%   action (rename/delete/recalculate/run a transformation) should act
%   on, since only one of the three trees can have a real "selection" at
%   a time in the underlying WorkSpaceTree/yy-tree model.
%
%   The context menu (List events / Rename / Recalculate / Delete) and its
%   per-node icons now live in WorkSpaceTree.html itself; per-node enable
%   state (canListEvents/canRecalculate) is computed once at addNode time
%   (see WorkSpaceTree.optsFor), not reactively on right-click as the old
%   raw Java JPopupMenu did.
    this.Tree = WorkSpaceTree(this.Parent.DataTreePanel, ...
        'SelectionChangedFcn',  @(e) this.Parent.onSelectionChanged(e, this.Tree), ...
        'NodeDoubleClickedFcn', @(e) this.Parent.onNodeDoubleClicked(e, this.Tree), ...
        'NodeDroppedFcn',       @(e) this.Parent.onNodeDropped(e, this.Tree), ...
        'ContextMenuActionFcn', @(e) this.Parent.onContextMenuAction(e, this.Tree), ...
        'RenderErrorFcn',       @(e) this.Parent.onTreeRenderError(e, this.Tree));

    this.GrandAveragesTree = WorkSpaceTree(this.Parent.GrandAveragesTreePanel, ...
        'SelectionChangedFcn',  @(e) this.Parent.onSelectionChanged(e, this.GrandAveragesTree), ...
        'NodeDoubleClickedFcn', @(e) this.Parent.onNodeDoubleClicked(e, this.GrandAveragesTree), ...
        'NodeDroppedFcn',       @(e) this.Parent.onNodeDropped(e, this.GrandAveragesTree), ...
        'ContextMenuActionFcn', @(e) this.Parent.onContextMenuAction(e, this.GrandAveragesTree), ...
        'RenderErrorFcn',       @(e) this.Parent.onTreeRenderError(e, this.GrandAveragesTree));

    this.ReportsTree = WorkSpaceTree(this.Parent.ReportsTreePanel, ...
        'SelectionChangedFcn',  @(e) this.Parent.onSelectionChanged(e, this.ReportsTree), ...
        'NodeDoubleClickedFcn', @(e) this.Parent.onNodeDoubleClicked(e, this.ReportsTree), ...
        'NodeDroppedFcn',       @(e) this.Parent.onNodeDropped(e, this.ReportsTree), ...
        'ContextMenuActionFcn', @(e) this.Parent.onContextMenuAction(e, this.ReportsTree), ...
        'RenderErrorFcn',       @(e) this.Parent.onTreeRenderError(e, this.ReportsTree));

    this.ActiveTree = this.Tree;
end
