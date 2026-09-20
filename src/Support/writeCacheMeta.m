function writeCacheMeta(matfilename, meta)
%WRITECACHEMETA  Write META (see eegCacheMeta) to <matfilename>.meta.
%   Best-effort, like writeCacheSidecar: a read-only cache folder or a full
%   disk costs the speed-up and nothing else, because readEegCacheMeta falls
%   back to loading the node.
%
%   The extension is deliberately not .mat. The tree finds a node's children
%   by listing *.mat in its folder, and a record named X.mat.meta.mat would
%   be taken for another node.
    try
        save([matfilename '.meta'], 'meta', '-mat');
    catch
        % Advisory only: readers fall back to a full load either way.
    end
end
