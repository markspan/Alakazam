function loadSETFile(this, name)
%LOADSETFILE  Wrapper for EEGLAB's own reader (pop_loadset) for .set
%   datasets. Reads only if no cached .mat file already exists, or the
%   raw .set is newer than the cache; otherwise reads the cached .mat
%   instead. Looks for a subdirectory with the same name for tree info on
%   previously performed Transformations, and adds those too -- see
%   registerRootNode.
    [id, matfilename, setfilename] = this.resolveCachePaths(name);

    if exist(matfilename, 'file') == 2 && dir(setfilename).datenum <= dir(matfilename).datenum
        % Cache is at least as new as the raw file: read the cache.
        loaded = load(matfilename, 'EEG');
        EEG = loaded.EEG;
    else
        % No cache yet, or the raw file is newer: (re)read it.
        restoreBusy = beginBusy(this.Parent.MainFigure, sprintf("Loading %s...", name)); %#ok<NASGU>
        EEG = pop_loadset(name, this.RawDirectory);
        EEG = eeg_checkset(EEG);
        EEG.times = ((1:EEG.pnts) - 1) / EEG.srate;
        EEG.DataType = 'TIMEDOMAIN';
        EEG.DataFormat = 'CONTINUOUS';
        EEG.id = id;
        EEG.File = matfilename;
        % -v7.3 on every save, not just the first one -- see loadBVAFile's
        % own comment for why (the same drift was present here too: only
        % the "no cache yet" branch passed it).
        save(matfilename, 'EEG', '-v7.3');
    end
    EEG.id = id;
    EEG.File = matfilename;
    this.EEG = EEG;

    this.registerRootNode(id, matfilename, 'raw');
end
