function files = subjectAverageFiles(this)
%SUBJECTAVERAGEFILES  The cache file of every subject's Average in the Data &
%   Analyses tree: an averaged dataset that a subject-averaging step made
%   (producesSubjectAverage), read from each node's small sidecar. The
%   datasets a data-quality report describes, found before any is loaded,
%   so that the report can first ask which analysis it is of
%   (chooseAnalysisBranches).
%
%   See also COLLECTDATAQUALITYENTRIES, ONEXPORTDATAQUALITY.
    files = {};
    nodes = this.Workspace.Tree.allNodes();
    for i = 1:numel(nodes)
        file = nodes(i).UserData;
        if isempty(file) || exist(file, 'file') ~= 2
            continue; % a node can outlive its file -- see loadNodeEEG's own note
        end
        info = readEegCacheInfo(file);
        if strcmpi(info.DataFormat, 'Averaged') && producesSubjectAverage(info.Call)
            files{end + 1} = file; %#ok<AGROW>
        end
    end
end
