function names = grandAveragesUsing(gaNodes, files)
%GRANDAVERAGESUSING  The grand averages made from any of FILES.
%   NAMES = GRANDAVERAGESUSING(GANODES, FILES) returns the names of the grand
%   averages among GANODES (the Grand Averages tree's nodes, as
%   WorkSpaceTree.allNodes gives them) whose recorded sources include any of
%   FILES, as a row cellstr in tree order. Only the tree's top-level nodes
%   are grand averages; a step run on one carries its record along, but is
%   not another. Used before a branch is deleted or moved, since a grand
%   average left without its sources keeps numbers nothing can recompute.
%
%   See also GRANDAVERAGERECORD, MOVEDROPPEDBRANCH, ONDELETENODE.
    names = {};
    if isempty(gaNodes) || isempty(files)
        return;
    end
    wanted = pathKey(files);
    for i = 1:numel(gaNodes)
        if ~gaNodes(i).IsRoot
            continue;
        end
        record = grandAverageRecord(gaNodes(i).UserData);
        if ~isempty(record.sources) && any(ismember(pathKey(record.sources), wanted))
            names{end + 1} = record.name; %#ok<AGROW>
        end
    end
end
