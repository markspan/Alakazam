function attached = AttachToNode(nodeFile, estimates, maxBytes)
%ATTACHTONODE  Store source estimates on a cached node.
%
%   ATTACHED = AttachSourceEstimateToNode(NODEFILE, ESTIMATES, MAXBYTES)
%   merges ESTIMATES into whatever NODEFILE already carries and re-saves it.
%   Returns whether anything was written.
%
%   WHY THIS IS NOT IN THE REPORT THAT CALLS IT. Writing to the cache tree
%   is not a reporting concern, and a report generator that also maintains
%   the cache is two jobs in one file. Keeping it here puts it beside the
%   rest of the estimate machinery, where the next person looking for
%   "how does an estimate get stored" will find it.
%
%   BEST EFFORT, AND SILENT ON FAILURE. Callers reach here having already
%   produced whatever they were asked for; a read-only folder or a locked
%   file is a reason to skip an optimisation, not to fail the work.
%
%   SAVED WITH saveEegCache, NOT save. That writes the JSON sidecar
%   alongside the .mat, and the sidecar is what lets
%   Alakazam.collectEntriesWithField find a node carrying an estimate
%   without loading it. Writing the .mat alone would store the estimate
%   somewhere nothing would ever look for it.
%
%   MAXBYTES caps a single estimate. Attaching is implicit, and a
%   whole-epoch estimate is around 490 MB per method at the full-resolution
%   sheet against a few MB for an ordinary node, so an unbounded version
%   turns running a report into writing a gigabyte of cache nobody asked
%   for. Pass Inf to store regardless.
%
%   See also TRANSTOOLS.ATTACHSOURCEESTIMATE, TRANSTOOLS.STOREDSOURCEESTIMATE,
%   SAVEEEGCACHE.
    attached = false;
    if isempty(estimates) || isempty(nodeFile) || exist(nodeFile, 'file') ~= 2
        return;
    end
    if nargin < 3 || isempty(maxBytes)
        maxBytes = 250e6;
    end

    keep = estimates([]);
    for k = 1:numel(estimates)
        if numel(estimates(k).values) * 8 <= maxBytes
            keep = SourceCache.Attach(keep, estimates(k));
        end
    end
    if isempty(keep)
        return;
    end

    try
        loaded = load(nodeFile, 'EEG');
        existing = [];
        if isfield(loaded.EEG, 'sourceEstimate')
            existing = loaded.EEG.sourceEstimate;
        end
        for k = 1:numel(keep)
            existing = SourceCache.Attach(existing, keep(k));
        end
        loaded.EEG.sourceEstimate = existing;
        saveEegCache(nodeFile, loaded.EEG, '-v7.3');
        attached = true;
    catch
        % See the header: the caller's own work stands either way.
    end
end
