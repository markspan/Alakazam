function loadBVAFile(this, name)
%LOADBVAFILE  Wrapper for EEGLAB's BrainVision reader (pop_loadbv). Reads
%   only if no cached .mat file already exists, or the raw .vhdr is newer
%   than the cache; otherwise reads the cached .mat instead. Looks for a
%   subdirectory with the same name for tree info on previously performed
%   Transformations, and adds those too -- see registerRootNode.
    [id, matfilename, bvafilename] = this.resolveCachePaths(name);

    if exist(matfilename, 'file') == 2 && dir(bvafilename).datenum <= dir(matfilename).datenum
        % Cache is at least as new as the raw file: read the cache.
        loaded = load(matfilename, 'EEG');
        EEG = loaded.EEG;
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
        save(matfilename, 'EEG', '-v7.3');
    end
    EEG.id = id;
    EEG.File = matfilename;
    this.EEG = EEG;

    this.registerRootNode(id, matfilename, 'raw');
end
