function keys = pathKey(paths)
%PATHKEY  Paths reduced to keys that compare as the files do.
%   KEYS = PATHKEY(PATHS) takes a path or a cell array of them and returns a
%   cell array of keys: separators unified, since a path may have been
%   recorded with either, and case folded on Windows, where the same file is
%   routinely named in different capitalisations. Case is kept elsewhere,
%   where it is significant. Compare keys with strcmp, ismember or
%   startsWith.
%
%   See also GRANDAVERAGESUSING, GRANDAVERAGESFORREPORT.
    keys = cellstr(paths);
    keys = strrep(strrep(keys, '/', filesep), '\', filesep);
    if ispc
        keys = lower(keys);
    end
end
