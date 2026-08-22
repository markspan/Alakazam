function writeCacheSidecar(matfilename, info)
%WRITECACHESIDECAR  Write INFO (see eegCacheInfo) as JSON to
%   <matfilename>.json. Best-effort: a failure here (read-only cache
%   folder, disk full, ...) is silently swallowed -- the sidecar is purely
%   an optimisation, callers (saveEegCache, readEegCacheInfo's self-heal
%   path) always still have the real .mat to fall back to.
    try
        fid = fopen([matfilename '.json'], 'w');
        if fid < 0
            return;
        end
        cleanupFid = onCleanup(@() fclose(fid));
        fprintf(fid, '%s', jsonencode(info));
    catch
        % Advisory only -- readers fall back to a full load either way.
    end
end
