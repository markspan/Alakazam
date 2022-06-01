function CreateTreeComponent(this)
% using a very slightly modified tree component, hence the copy in +uiextra
% the panel is the databrowsert
    
    this.Panel = javaObjectEDT('javax.swing.JPanel',javaObjectEDT('java.awt.BorderLayout'));   
    
    Root = figure('Visible', 'off');
    this.Tree = uiextras.jTree.Tree('DndEnabled', true, ...
        'Editable', true, ...
        'Parent', Root, ...
        'RootVisible', 'off', ...
        'SelectionChangeFcn', @(h,e) this.Parent.SelectionChanged(h,e), ...
        'MouseClickedCallback', @(h,e) this.Parent.MouseClicked(h,e), ...
        'NodeDroppedCallback',  @(h,e) this.Parent.TreeDropNode(h,e) ...
    );
    
    %%
    this.ToolBox = javaObjectEDT('javax.swing.JPanel',javaObjectEDT('java.awt.GridLayout',3,2,0,10));    
    this.javaObjects = this.Tree.getJavaObjects();
    this.Panel.add(this.javaObjects.jScrollPane, 'Center');
%    this.DefaultToolBox();
    
    %% For no obvious reason I put the used icons within "this" class, the Workspace...
    
    this.RawFileIcon = fullfile(pwd,'Icons','bookicon.gif');
    this.TimeSeriesIcon = fullfile(pwd,'Icons','pagesicon.gif');
    this.FrequenciesIcon = fullfile(pwd,'Icons','frequencyIcon.gif');
end
