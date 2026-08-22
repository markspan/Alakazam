function loadSETFile(this, name)
%LOADSETFILE  Wrapper for EEGLAB's own reader (pop_loadset) for .set
%   datasets. Reads only if no cached .mat file already exists, or the
%   raw .set is newer than the cache; otherwise reads the cached .mat
%   instead. Looks for a subdirectory with the same name for tree info on
%   previously performed Transformations, and adds those too -- see
%   registerRootNode.
    [id, matfilename, setfilename] = this.resolveCachePaths(name);

    % Covers both branches below (an onCleanup handle, not scoped to the
    % if/else): reading the cache can itself be slow for a large dataset,
    % so it needs the same busy indicator as a fresh raw-file read, not
    % just the "no cache yet" path.
    restoreBusy = beginBusy(this.Parent.MainFigure, sprintf("Loading %s...", name)); %#ok<NASGU>

    if exist(matfilename, 'file') == 2 && dir(setfilename).datenum <= dir(matfilename).datenum
        % Cache is at least as new as the raw file: this.EEG only needs to
        % be a real, fully-loaded dataset once the analyst actually opens
        % this node (loadAndPlotNode does a fresh load then, overwriting
        % this regardless) -- registerRootNode itself only reads a
        % handful of scalar fields, so a cheap sidecar read is enough
        % here, sparing every already-cached root recording (these can run
        % to 100+ MB) a full load on every single startup.
        EEG = eegProxyFromCacheInfo(readEegCacheInfo(matfilename));
    else
        % No cache yet, or the raw file is newer: (re)read it.
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
        saveEegCache(matfilename, EEG, '-v7.3');
    end
    EEG.id = id;
    EEG.File = matfilename;
    this.EEG = EEG;

    this.registerRootNode(id, matfilename, 'raw');
end
