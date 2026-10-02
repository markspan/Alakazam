function files = branchCacheFiles(file)
%BRANCHCACHEFILES  A node's cache file and every result computed from it.
%   FILES = BRANCHCACHEFILES(FILE) is a row cellstr: FILE first, then every
%   .mat cached under the folder named after it, where a node's results
%   live (see persistResultNode), at any depth. What deleting or moving the
%   node removes.
%
%   See also GRANDAVERAGESUSING, ONDELETENODE, MOVEDROPPEDBRANCH.
    files = {char(file)};
    [folder, stem] = fileparts(char(file));
    childDir = fullfile(folder, stem);
    if isfolder(childDir)
        found = dir(fullfile(childDir, '**', '*.mat'));
        for k = 1:numel(found)
            files{end + 1} = fullfile(found(k).folder, found(k).name); %#ok<AGROW>
        end
    end
end
