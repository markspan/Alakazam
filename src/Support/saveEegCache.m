function saveEegCache(matfilename, EEG, varargin)
%SAVEEEGCACHE  Save EEG to MATFILENAME under the variable name "EEG"
%   (every cache file's own convention) and write two small records beside it:
%   a JSON sidecar (<matfilename>.json, see eegCacheInfo) so a reader like
%   findGrandAverageCandidates can tell what kind of node this is without
%   loading the .mat, and a MAT record (<matfilename>.meta, see eegCacheMeta)
%   holding the settings and shape that replaying a branch reads. Extra
%   arguments are forwarded to save() (e.g. '-v7.3').
%
%   Both records are advisory only: readEegCacheInfo and readEegCacheMeta fall
%   back to a full load, and re-write them, if either is ever missing, stale,
%   or unreadable, so every cache tree built before they existed keeps working
%   unchanged, just without the speed-up until each file is next re-saved or
%   first re-scanned.
%
%   EEG.icaact IS NOT SAVED. The activations are weights * sphere * data, so
%   they are derived, and they are the same size as the data they were derived
%   from: 60 MB of a 127 MB node on a real RIFT recording, repeated in every
%   node below it. EEGLAB recomputes them when a function needs them
%   (eeg_checkset does, and RemoveComponents does when it finds them missing),
%   and it already had to for any node whose time range was cropped, since the
%   stored copy no longer matched. The caller's EEG is not changed, so a chain
%   held in memory still carries them until it is next loaded.
%
%   See also: READEEGCACHEINFO, EEGCACHEINFO, READEEGCACHEMETA, EEGCACHEMETA.
    if isfield(EEG, 'icaact') && ~isempty(EEG.icaact)
        EEG.icaact = [];
    end
    save(matfilename, 'EEG', varargin{:});
    writeCacheSidecar(matfilename, eegCacheInfo(EEG));
    writeCacheMeta(matfilename, eegCacheMeta(EEG));
end
