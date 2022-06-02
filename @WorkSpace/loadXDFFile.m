function loadXDFFile(this, WS, name)
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
xdffilename = strcat(WS.RawDirectory, name);

if exist(matfilename, 'file') == 2
    % if the file already exists:
    matfile = dir(matfilename);
    xdffile = dir(xdffilename);
    if xdffile.datenum > matfile.datenum
    else
        % else read the rawfile
        a=load(strcat(WS.CacheDirectory, id, '.mat'), 'EEG');
        this.EEG = a.EEG;
        this.EEG.id = id;
        this.EEG.File = matfilename;
    end
else
    % no matfile: create the matfile
    EEG = loadXDF(xdffilename);
    % DAMN YOU!!
    %rmdir([tempdir 'tmpXDF'], 's')

    [EEG.nbchan,EEG.pnts,EEG.trials] = size(EEG.data);
    [EEG.filepath,fname,fext] = fileparts(xdffilename); EEG.filename = [fname fext];
    EEG.times = EEG.times/1000;
    EEG=Tools.eeg_checkset(EEG);
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

function EEG = loadXDF(filename)
    td = tempdir;
    tnf = tempname(td);
    mkdir (tnf)
    data = dataSourceXDF( filename , tnf );
    sr=[]; ns=[]; 
    maxsr=-1;
    polar = [];
    for i = 1:length(data.item)
        sr(i) = data.item{i}.samplingRate; %#ok<AGROW> 
        ns(i) = size(data.item{i},1); %#ok<AGROW> 
        if strcmp(class(data.item{i}), 'markerStream') %#ok<STISA> 
            sr(i)=0; %#ok<AGROW> 
        end
        if sr(i) > maxsr 
            maxsr=sr(i);
            maxsrchan = i;
        end
        if sr(i) == 130
            %polarband
            polar = [polar i]; %#ok<AGROW> 
        end
    end

    ismarker = (sr==0);
    datachannels = find(~ismarker);

    datachannels = datachannels(datachannels ~= maxsrchan);
    datachannels = [datachannels maxsrchan];

    EEG = data.export2eeglab(datachannels, find(ismarker), [],false);

    if polar
        polarchannels = data.export2eeglab(polar, find(ismarker), [],false);
        for c = 1:size(polarchannels.data,1)
            polarchannels.data(c,isnan(polarchannels.data(c,:))) = mean(polarchannels.data(c,:), 'omitnan');
        end
        
    end

    for c = 1:size(EEG.data,1)
            EEG.data(c,isnan(EEG.data(c,:))) = mean(EEG.data(c,:), 'omitnan');
    end
    if polar
        EEG.Polarchannels = polarchannels;
    end
end