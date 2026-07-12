function loadGrandAverages(this)
%LOADGRANDAVERAGES  Populate the Grand Averages tree (this.GrandAveragesTree,
%   its own WorkSpaceTree instance -- see WorkSpace.CreateTreeComponent)
%   from CacheDirectory/GrandAverages, the flat folder every grand-average
%   dataset is saved into (see Alakazam.saveGrandAverage). Grand averages
%   are always top-level nodes here (parentId '') -- they never nest under
%   any single subject's branch, since they combine several, and now have
%   their own tree instead of a single always-present "Grand Averages" root
%   node inside the data & analyses tree.
    gaDir = fullfile(this.CacheDirectory, 'GrandAverages');
    if ~exist(gaDir, "dir")
        return; % nothing saved yet
    end

    found = dir(fullfile(gaDir, '*.mat'));
    for i = 1:numel(found)
        file = fullfile(found(i).folder, found(i).name);
        loaded = load(file, "EEG");
        % 'grandAverage', matching Alakazam.saveGrandAverage's own fresh-
        % creation path -- its own dedicated icon regardless of the
        % underlying data's time/frequency domain, not a borrowed
        % time/freq badge (see alakazam-tree.js's ICONS map comment).
        this.GrandAveragesTree.addNode(loaded.EEG.id, '', 'grandAverage', file, ...
            WorkSpaceTree.optsFor(loaded.EEG));
    end
end
