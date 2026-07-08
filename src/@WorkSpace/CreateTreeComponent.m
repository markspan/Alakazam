function CreateTreeComponent(this)
% using a very slightly modified tree component, hence the copy in +uiextra
% the panel is the databrowsert
% this = workspace;
% parent = AlakazamObject

    this.Panel = javaObjectEDT('javax.swing.JPanel',javaObjectEDT('java.awt.BorderLayout'));   
    this.TreeRoot = figure('Visible', 'off');
%
% Prepare the tree node context menu: rename, recalculate (not yet
% implemented, greyed out) and delete. Tree.UIContextMenu requires a
% genuine HG uicontextmenu (ishghandle), not a raw Java JPopupMenu, so this
% is built with uicontextmenu/uimenu rather than javax.swing classes.
this.jmenu = uicontextmenu(this.TreeRoot);
uimenu(this.jmenu, 'Text', 'Rename', ...
    'MenuSelectedFcn', @(~,~) this.Parent.onRenameNode());
uimenu(this.jmenu, 'Text', 'Recalculate', 'Enable', 'off'); % not implemented yet
uimenu(this.jmenu, 'Text', 'Delete', 'Separator', 'on', ...
    'MenuSelectedFcn', @(~,~) this.Parent.onDeleteNode());

%


    % UIContextMenu wires the popup menu through the tree's own right-click
    % handling (Tree.onMouseClick), which positions it correctly at the click
    % (accounting for scroll offset); showing it manually from
    % onMouseClicked used to hardcode a (10,10) position instead.
    this.Tree = uiextras.jTree.Tree('DndEnabled', true, ...
        'Editable', true, ...
        'Parent', this.TreeRoot, ...
        'FontSize', 11, ...
        'RootVisible', 'off', ...
        'UIContextMenu', this.jmenu, ...
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
