function loadBVAFile(this, name)
%LOADBVAFILE  Wrapper for EEGLAB's BrainVision reader (pop_loadbv). Reads
%   only if no cached .mat file already exists, or the raw .vhdr is newer
%   than the cache; otherwise reads the cached .mat instead. Looks for a
%   subdirectory with the same name for tree info on previously performed
%   Transformations, and adds those too -- see registerRootNode.
    [id, matfilename, bvafilename] = this.resolveCachePaths(name);

    % Covers both branches below (an onCleanup handle, not scoped to the
    % if/else): reading the cache can itself be slow for a large dataset,
    % so it needs the same busy indicator as a fresh raw-file read, not
    % just the "no cache yet" path.
    restoreBusy = beginBusy(this.Parent.MainFigure, sprintf("Loading %s...", name)); %#ok<NASGU>

    if exist(matfilename, 'file') == 2 && dir(bvafilename).datenum <= dir(matfilename).datenum
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
        EEG = pop_loadbv(this.RawDirectory, name);
        % eeg_checkset on every fresh read, not just a cache refresh: this
        % used to be commented out on the "no cache yet" path only, so a
        % freshly-imported recording silently skipped EEGLAB's structure
        % validation/fixup that a re-imported (stale-cache) one got.
        EEG = eeg_checkset(EEG);
        EEG.times = ((1:EEG.pnts) - 1) / EEG.srate;
        EEG.DataType = 'TIMEDOMAIN';
        EEG.DataFormat = 'CONTINUOUS';
        EEG.id = id;
        EEG.File = matfilename;
        % -v7.3 on every save, not just the first one: this used to only
        % be passed on the "no cache yet" branch: a recording large enough
        % to need it would save fine on first import, then fail (or
        % silently hit the default format's 2GB variable limit) the first
        % time its cache went stale and got refreshed.
        saveEegCache(matfilename, EEG, '-v7.3');
    end
    EEG.id = id;
    EEG.File = matfilename;
    this.EEG = EEG;

    this.registerRootNode(id, matfilename, 'raw');
end
