function loadSETFile(this, WS, name)
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
if exist(matfilename, 'file') == 2
    % if the file already exists:
    matfile = dir(matfilename);
    SETfile = dir(rawfilename);
    if SETfile.datenum > matfile.datenum
    else
        % else read the rawfile
        a=load(strcat(WS.CacheDirectory, id, '.mat'), 'EEG');
        this.EEG = a.EEG;
        this.EEG.id = id;
        this.EEG.File = matfilename;
    end
else
    % no matfile: create the matfile
    EEG=pop_loadset(strcat(id, '.set'), WS.RawDirectory);
    EEG.times = EEG.times/1000;
    EEG.File = matfilename;
    EEG.FileName = rawfilename;
    EEG.id = id;
    if (~isfield(EEG, 'DataFormat'))
        EEG.DataFormat = 'CONTINUOUS';
    end
    if (~isfield(EEG, 'DataType'))
        EEG.DataType = 'TIMEDOMAIN';
    end
    this.EEG = EEG;
    this.EEG.id = id;
    save(matfilename, 'EEG', '-v7.3');
end



%% Adds the loaded 'EEG' to the tree.
tn = uiextras.jTree.TreeNode('Name',id, 'UserData', matfilename, 'Parent', this.Tree.Root);
setIcon(tn,this.RawFileIcon);

%% Now recursively check for children of this file, and read them if they are there there.
this.treeTraverse(id, WS.CacheDirectory, tn);
end