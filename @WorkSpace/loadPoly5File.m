function loadPoly5File(this, WS, name)
%%
%   Loads the XDF file into an readeable format for Alakazam
%   Needs the EEGLAB to be in the path, and needs an installed Mobilab
%   plugin to be activated.....
%   
%
%%
[~,id,~] = fileparts(name);

% add the (semi)rootnode:

matfilename = strcat(WS.CacheDirectory, id, '.mat');
Poly5filename = strcat(WS.RawDirectory, name);

if exist(matfilename, 'file') == 2
    % if the file already exists:
    matfile = dir(matfilename);
    Poly5file = dir(Poly5filename);
    if Poly5file.datenum > matfile.datenum
    else
        % else read the rawfile
        a=load(strcat(WS.CacheDirectory, id, '.mat'), 'EEG');
        this.EEG = a.EEG;
        this.EEG.id = id;
        this.EEG.File = matfilename;
    end
else
    % no matfile: create the matfile
    [pathname,filename,extension] = fileparts(Poly5filename);
    %n = [pathname,'\',filename,extension]
    TMSIDATA = TMSi.Poly5.read([pathname,'\',filename,extension]);
    EEG = toEEGLab(TMSIDATA);

    EEG.DataType = 'TIMEDOMAIN';
    EEG.DataFormat = 'CONTINUOUS';
    EEG.id = id;
    EEG.File = matfilename;
    % EEG.lss = Tools.EEG2labeledSignalSet(this.EEG);
    save(matfilename, 'EEG', '-v7.3');
    this.EEG=EEG;
end

%% Adds the loaded 'EEG' to the tree.
tn = uiextras.jTree.TreeNode('Name',id, 'UserData', matfilename, 'Parent', this.Tree.Root);
setIcon(tn,this.RawFileIcon);

%% Now recursively check for children of this file, and read them if they are there there.
this.treeTraverse(id, WS.CacheDirectory, tn);
end

