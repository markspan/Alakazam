function CreateTreeComponent(this)
% using a very slightly modified tree component, hence the copy in +uiextra
% the panel is the databrowsert
% this = workspace;
% parent = AlakazamObject

    this.Panel = javaObjectEDT('javax.swing.JPanel',javaObjectEDT('java.awt.BorderLayout'));   
    this.TreeRoot = figure('Visible', 'off');
%
% Prepare the context menu (note the use of HTML labels)
menuItem1 = javax.swing.JMenuItem('action #1');
menuItem2 = javax.swing.JMenuItem('<html><b>action #2');
menuItem3 = javax.swing.JMenuItem('<html><i>action #3');
% Set the menu items' callbacks
set(menuItem1,'ActionPerformedCallback',@myFunc1);
set(menuItem2,'ActionPerformedCallback',@myfunc2);
set(menuItem3,'ActionPerformedCallback','disp ''action #3...'' ');
% Add all menu items to the context menu (with internal separator)
this.jmenu = javax.swing.JPopupMenu;
this.jmenu.add(menuItem1);
this.jmenu.add(menuItem2);
this.jmenu.addSeparator;
this.jmenu.add(menuItem3);

%


    this.Tree = uiextras.jTree.Tree('DndEnabled', true, ...
        'Editable', true, ...
        'Parent', this.TreeRoot, ...
        'FontSize', 11, ...
        'RootVisible', 'off', ...
        'SelectionChangeFcn', @(h,e) this.Parent.SelectionChanged(h,e), ...
        'MouseClickedCallback', @(h,e, jmenu) this.Parent.MouseClicked(h,e, this.jmenu), ...
        'NodeDroppedCallback',  @(h,e) this.Parent.TreeDropNode(h,e), ...
        'NodeEditedCallback',  @(h,e) this.Parent.NodeEdited(h,e) ...
    );
    
    %%
    this.ToolBox = javaObjectEDT('javax.swing.JPanel',javaObjectEDT('java.awt.GridLayout',3,2,0,10));    
    this.javaObjects = this.Tree.getJavaObjects();
    this.Panel.add(this.javaObjects.jScrollPane, 'Center');
    
    %% For no obvious reason I put the used icons within "this" class, the Workspace...
    
    this.RawFileIcon = fullfile(pwd,'Icons','bookicon.gif');
    this.TimeSeriesIcon = fullfile(pwd,'Icons','pagesicon.gif');
    this.FrequenciesIcon = fullfile(pwd,'Icons','frequencyIcon.gif');
end
