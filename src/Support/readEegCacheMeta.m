function meta = readEegCacheMeta(matfilename)
%READEEGCACHEMETA  EEGCACHEMETA's fields for MATFILENAME, from its .meta record
%   when one exists and is at least as new as the .mat itself, or from a full
%   load otherwise, healing by writing the record in that case. Only the first
%   read of a cache node saved before this existed pays for a load.
%
%   Mirrors READEEGCACHEINFO, including its staleness rule, so a node saved
%   by any route that does not go through SAVEEEGCACHE is noticed and
%   re-read rather than trusted.
%
%   See also EEGCACHEMETA, SAVEEEGCACHE, READEEGCACHEINFO.
    metaFile = [matfilename '.meta'];
    if exist(metaFile, 'file') == 2
        matInfo  = dir(matfilename);
        metaInfo = dir(metaFile);
        if ~isempty(matInfo) && ~isempty(metaInfo) && metaInfo.datenum >= matInfo.datenum
            try
                loaded = load(metaFile, '-mat', 'meta');
                if isfield(loaded, 'meta') && isstruct(loaded.meta) ...
                        && isfield(loaded.meta, 'version') && loaded.meta.version == 1
                    meta = loaded.meta;
                    return;
                end
            catch
                % Unreadable or from another format: fall through to a full load.
            end
        end
    end
    loaded = load(matfilename, 'EEG');
    meta = eegCacheMeta(loaded.EEG);
    writeCacheMeta(matfilename, meta);
end
