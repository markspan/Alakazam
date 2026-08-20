function loadMATFile(this, name)
%LOADMATFILE  Loads a previously-saved Alakazam .mat session (a plain
%   load('EEG'), not an EEGLAB reader -- see loadBVAFile/loadSETFile for
%   those). Unlike its siblings, this always rereads the raw file rather
%   than checking cache freshness by mtime: the "raw" file here already
%   IS an EEG-struct .mat, the exact shape the cache itself would be, so
%   there is no format-translation cost to avoid by preferring the cache
%   -- it only conditionally WRITES the cache, the first time one does
%   not exist yet. Looks for a subdirectory with the same name for tree
%   info on previously performed Transformations, and adds those too --
%   see registerRootNode.
    [id, matfilename, rawfilename] = this.resolveCachePaths(name);

    restoreBusy = beginBusy(this.Parent.MainFigure, sprintf("Loading %s...", name)); %#ok<NASGU>
    load(rawfilename, 'EEG');
    EEG.File = matfilename;
    EEG.FileName = rawfilename;
    EEG.id = id;

    if ~exist(matfilename, 'file')
        save(matfilename, 'EEG');
    end
    if ~isfield(EEG, 'DataFormat')
        EEG.DataFormat = 'CONTINUOUS';
    end
    if ~isfield(EEG, 'DataType')
        EEG.DataType = 'TIMEDOMAIN';
    end

    this.EEG = EEG;
    this.EEG.id = id;

    this.registerRootNode(id, matfilename, 'raw');
end
