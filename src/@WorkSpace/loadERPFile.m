function loadERPFile(this, name)
%LOADERPFILE  Read an ERPLAB erpset (.erp) as a root Averaged dataset.
%   An .erp file is a plain MAT-file holding an ERP struct (ERPLAB's averaged,
%   binned, time-domain waveform set). It is mapped to Alakazam's own Averaged
%   format by erpsetToAveraged -- structurally the same thing -- so the ERP is
%   read directly with load('-mat'), with no dependency on ERPLAB being
%   installed. Mirrors loadSETFile: caches the mapped dataset as a .mat and
%   adds it as a root node. An erpset arrives already at the ERP stage, so it
%   is a terminal node -- no raw/epoched data to re-run the front of the
%   pipeline on -- but the ERP-domain tools (Measure, ScalpDistribution, Grand
%   Average, plotting, and export back to .erp) all work on it.
%
%   See also ERPSETTOAVERAGED, LOADSETFILE, AVERAGEDTOERPSET.
    [id, matfilename, erpfilename] = this.resolveCachePaths(name);

    reread = true;
    if exist(matfilename, 'file') == 2
        reread = dir(erpfilename).datenum > dir(matfilename).datenum; % raw newer than cache
    end

    % Covers both branches below (an onCleanup handle, not scoped to the
    % if/else): reading the cache can itself be slow for a large dataset,
    % so it needs the same busy indicator as a fresh raw-file read, not
    % just the "no cache yet" path.
    restoreBusy = beginBusy(this.Parent.MainFigure, sprintf("Loading %s...", name)); %#ok<NASGU>

    if reread
        loaded = load(erpfilename, '-mat');
        if ~isfield(loaded, 'ERP')
            error('Alakazam:loadERPFile', ...
                'File "%s" is not an ERPLAB erpset (no ERP variable inside).', name);
        end
        EEG = erpsetToAveraged(loaded.ERP);
        EEG.id   = id;
        EEG.File = matfilename;
        saveEegCache(matfilename, EEG, '-v7.3');
        this.EEG = EEG;
    else
        % Cache is at least as new as the raw file: this.EEG only needs to
        % be a real, fully-loaded dataset once the analyst actually opens
        % this node (loadAndPlotNode does a fresh load then, overwriting
        % this regardless) -- registerRootNode itself only reads a
        % handful of scalar fields, so a cheap sidecar read is enough here.
        this.EEG = eegProxyFromCacheInfo(readEegCacheInfo(matfilename));
        this.EEG.id   = id;
        this.EEG.File = matfilename;
    end

    % The 'time' kind marks this as averaged time-domain data (as a
    % per-subject Average result gets), rather than the 'raw' person
    % badge a continuous recording gets -- see registerRootNode.
    this.registerRootNode(id, matfilename, 'time');
end
