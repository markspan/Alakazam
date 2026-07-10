function CreateTreeComponent(this)
%CREATETREECOMPONENT  Build the data-browser panel and its WorkSpaceTree.
%   WorkSpaceTree is a uihtml/CEF component (see WorkSpaceTree.m) and,
%   unlike the old Java-Swing uiextras.jTree.Tree, cannot be embedded in a
%   raw javax.swing.JPanel -- it needs a real uifigure-family host. A
%   matlab.ui.internal.FigurePanel supplies that (its .Figure is a lazily
%   created web-capable figure, the same mechanism FigureDocument uses for
%   docked plots -- see AlakazamPlotter.m); Alakazam's constructor docks it
%   into the AppContainer shell's left region via addPanel.
%
%   The context menu (List events / Rename / Recalculate / Delete) and its
%   per-node icons now live in WorkSpaceTree.html itself; per-node enable
%   state (canListEvents/canRecalculate) is computed once at addNode time
%   (see WorkSpaceTree.optsFor), not reactively on right-click as the old
%   raw Java JPopupMenu did.
    this.DataPanel = matlab.ui.internal.FigurePanel('Tag', 'dataBrowser', 'Title', 'Workspace');
    this.DataPanel.Region = 'left';
    this.DataPanel.PreferredWidth = 260;

    this.Tree = WorkSpaceTree(this.DataPanel.Figure, ...
        'SelectionChangedFcn',  @(e) this.Parent.onSelectionChanged(e), ...
        'NodeDoubleClickedFcn', @(e) this.Parent.onNodeDoubleClicked(e), ...
        'NodeDroppedFcn',       @(e) this.Parent.onNodeDropped(e), ...
        'ContextMenuActionFcn', @(e) this.Parent.onContextMenuAction(e));
end
