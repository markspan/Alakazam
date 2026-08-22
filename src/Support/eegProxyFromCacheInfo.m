function proxyEEG = eegProxyFromCacheInfo(info)
%EEGPROXYFROMCACHEINFO  A minimal stand-in for a fully-loaded EEG struct,
%   carrying only the fields WorkSpaceTree.optsFor/iconForResult actually
%   read (id, Call, DataFormat, DataType, etc.GrandAverage) -- built from
%   INFO (see eegCacheInfo/readEegCacheInfo) so a caller that only needs
%   to know what KIND of node this is, not its bulk data, never has to
%   pay for a full load just to get there.
    proxyEEG = struct('id', info.id, 'Call', info.Call, ...
        'DataFormat', info.DataFormat, 'DataType', info.DataType);
    if info.isGrandAverage
        proxyEEG.etc.GrandAverage = true;
    end
end
