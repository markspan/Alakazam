function CreateTreeComponent(this)
% using a very slightly modified tree component, hence the copy in +uiextra
% the panel is the databrowsert
% this = workspace;
% parent = AlakazamObject

    this.Panel = javaObjectEDT('javax.swing.JPanel',javaObjectEDT('java.awt.BorderLayout'));   
    this.TreeRoot = figure('Visible', 'off');
%
% Prepare the tree node context menu: list events (read-only inspection,
% continuous datasets only -- greyed out for epoched/averaged data, see
% onMouseClicked), rename, recalculate (Grand Average nodes only -- greyed
% out otherwise, see onMouseClicked) and delete. This has to be a raw Java
% JPopupMenu, not an HG uicontextmenu:
% this.TreeRoot (the menu's would-be HG parent) is a hidden backing figure
% (only its Java tree component is ever actually shown, re-parented into
% the ToolGroup's data browser panel below), and an HG context menu cannot
% render on a figure that is never made visible. A raw Swing popup has no
% such dependency.
menuListEvents = javax.swing.JMenuItem('List events');
menuRename = javax.swing.JMenuItem('Rename');
menuRecalc = javax.swing.JMenuItem('Recalculate');
menuDelete = javax.swing.JMenuItem('Delete');
set(menuListEvents, 'ActionPerformedCallback', @(~,~) this.Parent.onListEvents());
set(menuRename, 'ActionPerformedCallback', @(~,~) this.Parent.onRenameNode());
set(menuRecalc, 'ActionPerformedCallback', @(~,~) this.Parent.onRecalculateNode());
set(menuDelete, 'ActionPerformedCallback', @(~,~) this.Parent.onDeleteNode());
this.jmenuListEvents = menuListEvents; % enabled state toggled per-node in onMouseClicked
this.jmenuRecalc     = menuRecalc;     % likewise -- only enabled for Grand Average nodes

this.jmenu = javax.swing.JPopupMenu;
this.jmenu.add(menuListEvents);
this.jmenu.addSeparator;
this.jmenu.add(menuRename);
this.jmenu.add(menuRecalc);
this.jmenu.addSeparator;
this.jmenu.add(menuDelete);

%


    % this.jmenu is shown manually from onMouseClicked's right-click case
    % (Tree.m's own auto-show is gated on the Java event's isMetaDown,
    % which does not reliably fire as a right-click indicator here; the
    % MouseClickedCallback's Button==3, built from getButton(), does).
    this.Tree = uiextras.jTree.Tree('DndEnabled', true, ...
        'Editable', true, ...
        'Parent', this.TreeRoot, ...
        'FontSize', 11, ...
        'RootVisible', 'off', ...
        'SelectionChangeFcn', @(h,e) this.Parent.onSelectionChanged(h,e), ...
        'MouseClickedCallback', @(h,e) this.Parent.onMouseClicked(h,e), ...
        'NodeDroppedCallback',  @(h,e) this.Parent.onNodeDropped(h,e), ...
        'NodeEditedCallback',  @(h,e) this.Parent.onNodeEdited(h,e) ...
    );
    
    %%
    this.ToolBox = javaObjectEDT('javax.swing.JPanel',javaObjectEDT('java.awt.GridLayout',3,2,0,10));    
    this.javaObjects = this.Tree.getJavaObjects();
    this.Panel.add(this.javaObjects.jScrollPane, 'Center');
    
    %% For no obvious reason I put the used icons within "this" class, the Workspace...
    
    root = this.Parent.RootDir;
    this.RawFileIcon = fullfile(root,'Icons','bookicon.gif');
    this.TimeSeriesIcon = fullfile(root,'Icons','pagesicon.gif');
    this.FrequenciesIcon = fullfile(root,'Icons','frequencyIcon.gif');
end
