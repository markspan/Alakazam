function sources = grandAverageSources(EEG, file)
%GRANDAVERAGESOURCES  The cache files a grand average was made from, where
%   they are now.
%
%   SOURCES = GRANDAVERAGESOURCES(EEG, FILE) is EEG.etc.GrandAverage.sources
%   as a row cellstr, {} when it records none, each one looked up under the
%   Cache directory FILE lies in (relocatedCachePath): the folder holding
%   its GrandAverages folder. FILE is the grand average's own file, or that
%   of a step run on it, which lies below it. A file outside any
%   GrandAverages folder has its sources returned as recorded.
%
%   Every reader of a grand average's sources goes through this, so a
%   workspace whose folders were moved lists its grand averages, draws them
%   in its reports, and recalculates them from the files where they are.
%
%   See also RELOCATEDCACHEPATH, GRANDAVERAGERECORD, LOADGRANDAVERAGES.
    sources = {};
    if ~isstruct(EEG) || ~isfield(EEG, 'etc') || ~isstruct(EEG.etc) ...
            || ~isfield(EEG.etc, 'GrandAverage') || ~isstruct(EEG.etc.GrandAverage) ...
            || ~isfield(EEG.etc.GrandAverage, 'sources') || isempty(EEG.etc.GrandAverage.sources)
        return;
    end
    sources = reshape(cellstr(EEG.etc.GrandAverage.sources), 1, []);
    cacheDir = cacheOf(file);
    if ~isempty(cacheDir)
        sources = cellfun(@(s) relocatedCachePath(s, cacheDir), sources, 'UniformOutput', false);
    end
end

function cacheDir = cacheOf(file)
%CACHEOF  The folder holding the GrandAverages folder FILE lies in, or ''.
    cacheDir = '';
    folder = fileparts(char(file));
    while ~isempty(folder)
        [parent, name] = fileparts(folder);
        if strcmpi(name, 'GrandAverages')
            cacheDir = parent;
            return;
        end
        if strcmp(parent, folder)
            return;
        end
        folder = parent;
    end
end
