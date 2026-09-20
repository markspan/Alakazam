function proxyEEG = eegProxyFromCacheMeta(meta)
%EEGPROXYFROMCACHEMETA  A stand-in for a cache node's EEG that carries just
%   what the tree and the grand-average scans read from it, so they need not
%   load the node. Gives WorkSpaceTree.optsFor the same answer as the real EEG
%   would: it looks only at Call, DataFormat, etc.GrandAverage and
%   etc.alz.artefactDetectors. Also carries etc.DesignCell, which the
%   analysis-script export reads.
%
%   Unlike EEGPROXYFROMCACHEINFO, whose GrandAverage is only a flag, this
%   carries the record itself, because loadGrandAverages needs its sources.
%
%   See also EEGCACHEMETA, EEGPROXYFROMCACHEINFO.
    proxyEEG = struct('id', meta.id, 'Call', meta.Call, 'Label', meta.Label, ...
        'DataFormat', meta.DataFormat, 'DataType', meta.DataType);
    if meta.hasGrandAverage
        proxyEEG.etc.GrandAverage = meta.grandAverage;
    end
    if meta.hasDesignCell
        proxyEEG.etc.DesignCell = meta.designCell;
    end
    if meta.hasRejectionBreakdown
        proxyEEG.etc.alz.artefactDetectors = true;
    end
end
