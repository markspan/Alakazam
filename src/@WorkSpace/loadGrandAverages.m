function loadGrandAverages(this)
%LOADGRANDAVERAGES  Create the "Grand Averages" tree node (always present,
%   even when empty) and populate it from CacheDirectory/GrandAverages,
%   the flat folder every grand-average dataset is saved into (see
%   Alakazam.saveGrandAverage). Unlike a subject's own derived results,
%   grand averages do not nest under any single subject's branch -- they
%   combine several -- so they get their own place in the tree instead.
    this.GrandAveragesNode = uiextras.jTree.TreeNode('Name', 'Grand Averages', ...
        'Parent', this.Tree.Root);

    gaDir = fullfile(this.CacheDirectory, 'GrandAverages');
    if ~exist(gaDir, "dir")
        return; % nothing saved yet
    end

    found = dir(fullfile(gaDir, '*.mat'));
    for i = 1:numel(found)
        file = fullfile(found(i).folder, found(i).name);
        loaded = load(file, "EEG");
        node = uiextras.jTree.TreeNode('Name', loaded.EEG.id, ...
            'Parent', this.GrandAveragesNode, 'UserData', file);
        if isfield(loaded.EEG, "DataType") && strcmpi(loaded.EEG.DataType, "FREQUENCYDOMAIN")
            setIcon(node, this.FrequenciesIcon);
        else
            setIcon(node, this.TimeSeriesIcon);
        end
    end
end
