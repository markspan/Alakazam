function loadSETFile(this, WS, name)
%%
% Wrapper for the eeglab function reading EEGLAB .set datasets.
% Reads only if no .mat file allready exists, and reads the .mat file
% if it does.
% Looks for a subdir with the same name for 'tree' info on previously
% performed Transformations. Adds these too.
%%

import matlab.ui.internal.toolstrip.*
[~,id,~] = fileparts(name);

% add the (semi)rootnode:

matfilename = strcat(WS.CacheDirectory, id, '.mat');
setfilename = strcat(WS.RawDirectory, name);

if exist(matfilename, 'file') == 2
    % if the file already exists:
    matfile = dir(matfilename);
    setfile = dir(setfilename);
    if setfile.datenum > matfile.datenum
        % if the raw file is newer then the Mat file reread it
        EEG = pop_loadset(name, WS.RawDirectory);
        EEG = eeg_checkset(EEG);
        EEG.times = (((1:EEG.pnts)-1)/EEG.srate);
        EEG.DataType = 'TIMEDOMAIN';
        EEG.DataFormat = 'CONTINUOUS';
        EEG.id = id;
        EEG.File = matfilename;
        save(matfilename, 'EEG');
        this.EEG = EEG;
    else
        % else read the rawfile
        a = load(strcat(WS.CacheDirectory, id, '.mat'), 'EEG');
        this.EEG = a.EEG;
        this.EEG.id = id;
        this.EEG.File = matfilename;
    end
else
    % no matfile: create the matfile
    EEG = pop_loadset(name, WS.RawDirectory);
    EEG = eeg_checkset(EEG);
    EEG.DataType = 'TIMEDOMAIN';
    EEG.DataFormat = 'CONTINUOUS';
    EEG.id = id;
    EEG.times = (((1:EEG.pnts)-1)/EEG.srate);
    EEG.File = matfilename;
    save(matfilename, 'EEG', '-v7.3');
    this.EEG = EEG;
end

%% Adds the loaded 'EEG' to the tree as a root (raw import) node.
opts = WorkSpaceTree.optsFor(this.EEG);
opts.isRoot = true;
tn = this.Tree.addNode(id, '', 'raw', matfilename, opts);

%% Now recursively check for children of this file, and read them if they are there there.
this.treeTraverse(id, WS.CacheDirectory, tn);
end
