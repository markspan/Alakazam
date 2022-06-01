function treeTraverse(this,id, branchDir, currentParentNode)
% Rebuild the Transformation tree from the directory structure that
% was created during the transformation.
% 

%% Does a subdir with the name 'ID' Exist?
% No: end of tree, return
if ~exist(fullfile(branchDir,id), 'dir')
    return
end
% Yes: 
% Are there files in there?

branchDir = fullfile(branchDir,id);
branches = dir(branchDir);
branches = branches(~strcmp({branches.name},'.') & ...
                        ~strcmp({branches.name},'..') & ...
                        ~[branches.isdir]); 

%   No: end of tree, return
if isempty(branches)
    return
end
%   Yes: what files are in there, 
for ib = 1:length(branches)
    b = branches(ib);
    if length(b.name) > 3 && strcmpi(b.name(end-2:end), 'mat')
        %        1) add them to the tree, **and**
        a = load(fullfile(b.folder,b.name), 'EEG');
        
        NewNode = uiextras.jTree.TreeNode('Name',a.EEG.id,'Parent', ...
            currentParentNode, 'UserData',a.EEG.File);
        if strcmpi(a.EEG.DataType, 'TIMEDOMAIN')
            setIcon(NewNode,this.TimeSeriesIcon);
        elseif strcmpi(a.EEG.DataType, 'FREQUENCYDOMAIN')
            setIcon(NewNode,this.FrequenciesIcon);
        end
        
        %        2) traverse into (each of) them.
        [~,n,~] = fileparts(fullfile(b.folder,b.name));
        treeTraverse(this, n, branchDir, NewNode);
    end
end
%                 NewNode=uiextras.jTree.TreeNode('Name',a.EEG.id,'Parent',this.Workspace.Tree.SelectedNodes, 'UserData',a.EEG.File);
%                 if strcmpi(a.EEG.DataType, 'TIMEDOMAIN')
%                     setIcon(NewNode,this.Workspace.TimeSeriesIcon);
%                 elseif strcmpi(a.EEG.DataType, 'FREQUENCYDOMAIN')
%                     setIcon(NewNode,this.Workspace.FrequenciesIcon);
%                 end
%                 NewNode.Parent.expand();
%                 this.Workspace.Tree.SelectedNodes = NewNode;
 
end

