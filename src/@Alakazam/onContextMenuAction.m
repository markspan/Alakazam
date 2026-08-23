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
        case 'applyToAll'
            this.onApplyToAllRawFiles();
        case 'saveTemplate'
            this.onSaveTemplate();
        case 'applyTemplate'
            this.onApplyTemplate();
        case 'exportErpset'
            this.onExportErpset();
        case 'exportSet'
            this.onExportSet();
        case 'delete'
            this.onDeleteNode();
    end
end
