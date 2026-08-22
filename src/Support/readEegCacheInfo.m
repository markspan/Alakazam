function info = readEegCacheInfo(matfilename)
%READEEGCACHEINFO  EEGCACHEINFO's fields for MATFILENAME, from its JSON
%   sidecar (see saveEegCache) when one exists and is at least as new as
%   the .mat itself, or from a full load otherwise -- self-healing by
%   writing the sidecar in that case, so only the very first scan of a
%   cache tree built before this existed (or a file some other code path
%   saved without going through saveEegCache) pays the full-load cost per
%   file; every scan after that reads a few hundred bytes of JSON instead.
%
%   See also: SAVEEEGCACHE, EEGCACHEINFO.
    jsonFile = [matfilename '.json'];
    if exist(jsonFile, 'file') == 2
        matInfo  = dir(matfilename);
        jsonInfo = dir(jsonFile);
        if ~isempty(matInfo) && ~isempty(jsonInfo) && jsonInfo.datenum >= matInfo.datenum
            try
                info = jsondecode(fileread(jsonFile));
                info.bindescLabels = normaliseCellstr(info.bindescLabels);
                info.fieldNames    = normaliseCellstr(info.fieldNames);
                return;
            catch
                % Corrupt/unreadable sidecar -- fall through to a full load.
            end
        end
    end
    loaded = load(matfilename, "EEG");
    info = eegCacheInfo(loaded.EEG);
    writeCacheSidecar(matfilename, info);
end

function c = normaliseCellstr(c)
%NORMALISECELLSTR  jsondecode hands back a cell array of char for a JSON
%   string array with one or more elements, but a genuinely EMPTY array
%   (e.g. most cache nodes have no bindesc at all) decodes as a plain
%   double [] instead -- cellstr([]) would throw on that, so it needs its
%   own branch rather than a blanket cellstr(...).
    if iscell(c)
        c = cellstr(c);
    else
        c = {};
    end
end
