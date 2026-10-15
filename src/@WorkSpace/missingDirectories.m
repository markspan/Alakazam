function missing = missingDirectories(this)
%MISSINGDIRECTORIES  The folders this workspace names that do not exist on
%   this computer, as a struct array with .label ('Raw data', 'Cache',
%   'Exports') and .path; empty when all three are there.
%
%   A folder that is not set at all counts as missing too. Nothing is
%   created here: open() makes a missing Cache or Exports folder when it
%   can, which is right for a new workspace and wrong for one whose data
%   have moved, so the question is asked before open() is (openOrAsk).
%
%   See also WORKSPACE.OPENORASK, WORKSPACE.OPEN.
    missing = struct('label', {}, 'path', {});
    folders = {'RawDirectory', 'Raw data'; 'CacheDirectory', 'Cache'; 'ExportsDirectory', 'Exports'};
    for k = 1:size(folders, 1)
        folder = char(string(this.(folders{k, 1})));
        if isempty(folder) || ~isfolder(folder)
            missing(end + 1) = struct('label', folders{k, 2}, 'path', folder); %#ok<AGROW>
        end
    end
end
