function loadBVAFile(this, WS, name)
%%
%
%
%
%
%%

import matlab.ui.internal.toolstrip.*
[~,id,~] = fileparts(name);

% add the (semi)rootnode:

matfilename = strcat(WS.CacheDirectory, id, '.mat');
bvafilename = strcat(WS.RawDirectory, name);

if exist(matfilename, 'file') == 2
    % if the file already exists:
    matfile = dir(matfilename);
    bvafile = dir(bvafilename);
    if bvafile.datenum > matfile.datenum
        % if the raw file is newer then the Mat file reread it
        EEG=Tools.pop_loadbv(WS.RawDirectory,name);
        EEG=eeg_checkset(EEG);
        EEG.times = 1000*(((1:EEG.pnts)-1)/EEG.srate);
        EEG.DataType = 'TIMEDOMAIN';
        EEG.DataFormat = 'CONTINUOUS';

        EEG.id = id;
        EEG.File = matfilename;
        save(matfilename, 'EEG');
        this.EEG=EEG;
    else
        % else read the rawfile
        a=load(strcat(WS.CacheDirectory, id, '.mat'), 'EEG');
        this.EEG = a.EEG;
        this.EEG.id = id;
        this.EEG.File = matfilename;
    end
else
    % no matfile: create the matfile
    EEG=Tools.pop_loadbv(WS.RawDirectory,name);
    EEG=eeg_checkset(EEG);
    EEG.DataType = 'TIMEDOMAIN';
    EEG.DataFormat = 'CONTINUOUS';

    EEG.id = id;
    EEG.times = 1000*(((1:EEG.pnts)-1)/EEG.srate);
    EEG.File = matfilename;
    save(matfilename, 'EEG');
    this.EEG=EEG;
end

tn = uiextras.jTree.TreeNode('Name',id, 'UserData', matfilename, 'Parent', this.Tree.Root);
setIcon(tn,this.RawFileIcon);

end