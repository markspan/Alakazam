function bins = candidateBinLabels(this, candidateFiles) %#ok<INUSL>
%CANDIDATEBINLABELS  The union of every candidate's own bin labels, so
%   ClusterStatsDialog can build its bin picker(s) without doing any file
%   I/O itself (matching GrandAverageDialog's own no-I/O convention). A
%   subject actually missing a chosen bin is still caught, with a clear
%   error naming it, by ClusterStats' own validateCompatibility.
    bins = {};
    for i = 1:numel(candidateFiles)
        % From the JSON sidecar: a candidate is a full averaged or epoched
        % node, and only its bin labels are wanted.
        bins = union(bins, readEegCacheInfo(candidateFiles{i}).bindescLabels);
    end
end
