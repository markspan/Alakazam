function record = grandAverageRecord(file)
%GRANDAVERAGERECORD  What a grand average says about itself: its name and
%   the cache files it was made from, read from its meta record rather than
%   by loading it.
%
%   RECORD = GRANDAVERAGERECORD(FILE) returns a struct with
%     .name     the grand average's own name (its EEG.id)
%     .sources  the files it was computed from, a row cellstr; {} when it
%               records none (written before the record existed, or not a
%               grand average at all)
%     .missing  which of them no longer exist, a logical row
%
%   A grand average is a fixed list of datasets, computed once. Recalculating
%   one of them refreshes it (recalculateAffectedGrandAverages); deleting one
%   leaves it with its numbers and a source that is gone, which .missing
%   tells.
%
%   See also GRANDAVERAGESUSING, GRANDAVERAGESFORREPORT, GRANDAVERAGELABEL.
    record = struct('name', '', 'sources', {{}}, 'missing', false(1, 0));
    if isempty(file) || exist(file, 'file') ~= 2
        return;
    end
    proxy = eegProxyFromCacheMeta(readEegCacheMeta(file));
    if isfield(proxy, 'id') && ~isempty(proxy.id)
        record.name = char(string(proxy.id));
    end
    % Where they are now, should the workspace's folders have moved.
    record.sources = grandAverageSources(proxy, file);
    record.missing = ~cellfun(@(s) exist(s, 'file') == 2, record.sources);
end
