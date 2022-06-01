function ChangeToolBox(this, newTools)
%% ChangeTOOLBOX
% Creates the default toolbox in the toolbox pane of the databrowser
% part of ALAKAZAM
% m.m.span aug 2021
%% 

    this.Panel.removeAll()
    this.Panel.add(this.javaObjects.jScrollPane, 'Center');
    this.ToolBox = newTools;
    this.Panel.add(this.ToolBox, 'South')
    this.Panel.revalidate();
end

