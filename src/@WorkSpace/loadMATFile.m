function loadMATFile(this, WS, name)
%%
% Loads a previously-saved Alakazam .mat session (a plain load('EEG'),
% not an EEGLAB reader -- see loadBVAFile/loadSETFile for those).
% Reads only if no cached .mat file already exists, and reads the .mat file
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
    EEG.File = matfilename;
    EEG.FileName = rawfilename;
    EEG.id = id;

    if ~exist(matfilename, 'file')
        save(matfilename, 'EEG');
    end
    if (~isfield(EEG, 'DataFormat'))
        EEG.DataFormat = 'CONTINUOUS';
    end
    if (~isfield(EEG, 'DataType'))
        EEG.DataType = 'TIMEDOMAIN';
    end


    this.EEG = EEG;
    this.EEG.id = id;


%% Adds the loaded 'EEG' to the tree as a root (raw import) node.
opts = WorkSpaceTree.optsFor(EEG);
opts.isRoot = true;
tn = this.Tree.addNode(id, '', 'raw', matfilename, opts);

%% Now recursively check for children of this file, and read them if they are there there.
this.treeTraverse(id, WS.CacheDirectory, tn);
end