function loadMATFile(this, WS, name)
%%
% Wrapper for the eeglab function reading Brainvision files.
% Reads only if no .mat file allready exists, and reads the .mat file
% if it does. 
% Looks for a subdir with the same name for 'tree' info on previously 
% performed Transformations. Adds these too.
%%

import matlab.ui.internal.toolstrip.*
[~,id,~] = fileparts(name);

% add the (semi)rootnode:

matfilename = strcat(WS.CacheDirectory, id, '.mat');
rawfilename = strcat(WS.RawDirectory, name);

    load(rawfilename, 'EEG');
    if ~exist(matfilename, 'file')
        save(matfilename, 'EEG');
    end
    EEG.File = matfilename;
    if (~isfield(EEG, 'DataFormat'))
        EEG.DataFormat = 'CONTINUOUS';
    end
    if (~isfield(EEG, 'DataType'))
        EEG.DataType = 'TIMEDOMAIN';
    end


    this.EEG = EEG;
    this.EEG.id = id;
    this.EEG.File = matfilename;


%% Adds the loaded 'EEG' to the tree.
tn = uiextras.jTree.TreeNode('Name',id, 'UserData', matfilename, 'Parent', this.Tree.Root);
setIcon(tn,this.RawFileIcon);

%% Now recursively check for children of this file, and read them if they are there there.
this.treeTraverse(id, WS.CacheDirectory, tn);
end