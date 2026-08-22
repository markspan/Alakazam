function saveEegCache(matfilename, EEG, varargin)
%SAVEEEGCACHE  Save EEG to MATFILENAME under the variable name "EEG"
%   (every cache file's own convention) and write a small JSON sidecar
%   (<matfilename>.json) alongside it with just enough about EEG (see
%   eegCacheInfo) for a reader like findGrandAverageCandidates to tell
%   what kind of node this is without loading the .mat itself. Extra
%   arguments are forwarded to save() (e.g. '-v7.3').
%
%   The sidecar is advisory only: readEegCacheInfo falls back to a full
%   load, and re-writes it, if it is ever missing, stale, or unreadable --
%   so every existing cache tree built before this existed keeps working
%   unchanged, just without the speed-up until each file is next re-saved
%   or first re-scanned.
%
%   See also: READEEGCACHEINFO, EEGCACHEINFO.
    save(matfilename, 'EEG', varargin{:});
    writeCacheSidecar(matfilename, eegCacheInfo(EEG));
end
