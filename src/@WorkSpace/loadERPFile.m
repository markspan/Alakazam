function loadERPFile(this, WS, name)
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
    [~, id, ~] = fileparts(name);

    matfilename = strcat(WS.CacheDirectory, id, '.mat');
    erpfilename = strcat(WS.RawDirectory, name);

    reread = true;
    if exist(matfilename, 'file') == 2
        matfile = dir(matfilename);
        erpfile = dir(erpfilename);
        reread = erpfile.datenum > matfile.datenum; % raw newer than cache
    end

    if reread
        loaded = load(erpfilename, '-mat');
        if ~isfield(loaded, 'ERP')
            error('Alakazam:loadERPFile', ...
                'File "%s" is not an ERPLAB erpset (no ERP variable inside).', name);
        end
        EEG = erpsetToAveraged(loaded.ERP);
        EEG.id   = id;
        EEG.File = matfilename;
        save(matfilename, 'EEG', '-v7.3');
        this.EEG = EEG;
    else
        a = load(matfilename, 'EEG');
        this.EEG = a.EEG;
        this.EEG.id   = id;
        this.EEG.File = matfilename;
    end

    %% Add the loaded erpset as a root (Averaged) node. The 'time' badge marks
    %  it as averaged time-domain data (as a per-subject Average result gets),
    %  rather than the 'raw' person badge a continuous recording gets.
    opts = WorkSpaceTree.optsFor(this.EEG);
    opts.isRoot = true;
    tn = this.Tree.addNode(id, '', 'time', matfilename, opts);

    %% Read any children previously computed from this erpset.
    this.treeTraverse(id, WS.CacheDirectory, tn);
end
