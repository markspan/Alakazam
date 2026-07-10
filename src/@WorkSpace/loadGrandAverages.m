function loadGrandAverages(this)
%LOADGRANDAVERAGES  Create the "Grand Averages" tree node (always present,
%   even when empty) and populate it from CacheDirectory/GrandAverages,
%   the flat folder every grand-average dataset is saved into (see
%   Alakazam.saveGrandAverage). Unlike a subject's own derived results,
%   grand averages do not nest under any single subject's branch -- they
%   combine several -- so they get their own place in the tree instead.
    this.GrandAveragesNode = this.Tree.addNode('Grand Averages', '', 'default', '', struct('isRoot', true));

    gaDir = fullfile(this.CacheDirectory, 'GrandAverages');
    if ~exist(gaDir, "dir")
        return; % nothing saved yet
    end

    found = dir(fullfile(gaDir, '*.mat'));
    for i = 1:numel(found)
        file = fullfile(found(i).folder, found(i).name);
        loaded = load(file, "EEG");
        if isfield(loaded.EEG, "DataType") && strcmpi(loaded.EEG.DataType, "FREQUENCYDOMAIN")
            iconKey = 'freq';
        else
            iconKey = 'time';
        end
        this.Tree.addNode(loaded.EEG.id, this.GrandAveragesNode.Id, iconKey, file, ...
            WorkSpaceTree.optsFor(loaded.EEG));
    end
end
