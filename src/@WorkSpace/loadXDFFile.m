function loadXDFFile(this, WS, name)
% loadXDFFile - Load an XDF file and convert it to a readable format for Alakazam.
%
% Syntax: loadXDFFile(this, WS, name)
%
% Inputs:
%   this - Reference to the current object
%   WS - Workspace containing cache and raw directories
%   name - Name of the XDF file to load
%
% Description:
%   This function loads an XDF file and converts it to a MATLAB-readable format
%   (EEG structure). It checks if a cached version of the file exists and is
%   up-to-date. If so, it loads the cached version. If not, it processes the
%   raw XDF file and caches the result. The function also integrates the loaded
%   EEG data into a tree structure for further processing.
    
    % Extract the file identifier (id) from the file name
    
    [~,id,~] = fileparts(name);
    
    % Construct paths for the .mat cache file and the raw XDF file
    matfilename = strcat(WS.CacheDirectory, id, '.mat');
    xdffilename = strcat(WS.RawDirectory, name);
    CacheLoad = [];
    % Check if the .mat cache file exists
    if exist(matfilename, 'file') == 2
        % If the .mat file exists, check if it is up-to-date with the raw XDF file
        matfile = dir(matfilename);
        xdffile = dir(xdffilename);
        if xdffile.datenum <= matfile.datenum
            % Load the cached .mat file if it is up-to-date
            CacheLoad = load(matfilename, 'EEG');
            this.EEG = CacheLoad.EEG;
            this.EEG.id = id;
            this.EEG.File = matfilename;
        end
    end 
    if isempty(CacheLoad)
        % no matfile: Read the RAW XDF and create the matfile
        try
            % Attempt to load the XDF file using eeg_load_xdf function
            EEG = eeg_load_xdf(xdffilename, 'streamtype', 'ECG');
            % Set the label for the first channel to "ECG"
            % EEG.chanlocs(1).labels = "ECG";
        catch 
            % If loading fails, create an empty EEG structure
             EEG = eeg_emptyset();
        end
    
        % Set EEG properties
        [EEG.nbchan,EEG.pnts,EEG.trials] = size(EEG.data);
        [EEG.filepath,fname,fext] = fileparts(xdffilename); EEG.filename = [fname fext];
       
        EEG=Tools.eeg_checkset(EEG);    % Validate and set EEG structure properties
        EEG.times = EEG.times./1000;    % Convert times from milliseconds to seconds
        EEG.DataType = 'TIMEDOMAIN';
        EEG.DataFormat = 'CONTINUOUS';
        EEG.id = id;
        EEG.File = matfilename;
    
         % Save the EEG structure to the .mat file
        save(matfilename, 'EEG', '-v7.3');
        this.EEG=EEG;
    end
    
    % Add the loaded EEG to the tree structure
    tn = uiextras.jTree.TreeNode('Name',id, 'UserData', matfilename, 'Parent', this.Tree.Root);
    setIcon(tn,this.RawFileIcon);
    
    % Recursively check for children files and read them if they exist
    this.treeTraverse(id, WS.CacheDirectory, tn);
end


