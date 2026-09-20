function meta = eegCacheMeta(EEG)
%EEGCACHEMETA  The small fields of EEG that callers keep loading a whole cache
%   node to read: what produced it, with what settings, and what shape it is.
%
%   WHY THIS EXISTS, AND WHY IT IS NOT THE JSON SIDECAR. EEGCACHEINFO already
%   records what kind of node a file is, as JSON, so a scan need not load it.
%   It cannot carry PARAMS, which is what replaying or recalculating a branch
%   needs: jsondecode returns every array as a column, turns a cell array of
%   same-shaped structs into a struct array, and loses the difference between
%   a scalar and a one-element list. Several transformations already have to
%   repair those changes when a template comes back through JSON, so putting
%   parameters through it again for every replay would trade a disk read for a
%   correctness risk. This record is a MAT file, so PARAMS comes back exactly
%   as it went in.
%
%   Applying a branch to a dozen recordings used to load every step of the
%   source branch in full (about 1.7 GB per target for the RIFT chain) to read
%   .Call and .params from each. This is what it reads instead.
%
%   FIELDS
%     version              format number, so a later change is healed, not misread
%     Call, params, id, Label, DataFormat, DataType   as stored on EEG
%     dataSize             size(EEG.data), which is all an overlay test needs
%     timeRange            [min max] of EEG.times, or [] (epoch range scans)
%     hasGrandAverage      whether EEG.etc.GrandAverage exists
%     grandAverage         that record (sources, weighting), or []
%     hasRejectionBreakdown  whether etc.alz.artefactDetectors exists
%     hasDesignCell, designCell   etc.DesignCell (which cell of the design a
%                          grand average was built for), or []
%
%   See also SAVEEEGCACHE, READEEGCACHEMETA, EEGCACHEINFO.
    meta = struct();
    meta.version    = 1;
    meta.Call       = valueOr(EEG, 'Call', '');
    meta.params     = valueOr(EEG, 'params', []);
    meta.id         = charOr(EEG, 'id', '');
    meta.Label      = charOr(EEG, 'Label', '');
    meta.DataFormat = charOr(EEG, 'DataFormat', '');
    meta.DataType   = charOr(EEG, 'DataType', '');

    meta.dataSize = [];
    if isfield(EEG, 'data')
        meta.dataSize = size(EEG.data);
    end

    meta.timeRange = [];
    if isfield(EEG, 'times') && isnumeric(EEG.times) && ~isempty(EEG.times)
        t = double(EEG.times(:));
        meta.timeRange = [min(t), max(t)];
    end

    meta.hasGrandAverage = isfield(EEG, 'etc') && isstruct(EEG.etc) ...
        && isfield(EEG.etc, 'GrandAverage');
    meta.grandAverage = [];
    if meta.hasGrandAverage
        meta.grandAverage = EEG.etc.GrandAverage;
    end

    meta.hasDesignCell = isfield(EEG, 'etc') && isstruct(EEG.etc) ...
        && isfield(EEG.etc, 'DesignCell');
    meta.designCell = [];
    if meta.hasDesignCell
        meta.designCell = EEG.etc.DesignCell;
    end

    meta.hasRejectionBreakdown = isfield(EEG, 'etc') && isstruct(EEG.etc) ...
        && isfield(EEG.etc, 'alz') && isstruct(EEG.etc.alz) ...
        && isfield(EEG.etc.alz, 'artefactDetectors');
end

function v = valueOr(EEG, name, default)
    if isfield(EEG, name)
        v = EEG.(name);
    else
        v = default;
    end
end

function v = charOr(EEG, name, default)
%CHAROR  A char accessor: text stored as a string, char or number reads back as char.
    if isfield(EEG, name) && ~isempty(EEG.(name))
        v = char(string(EEG.(name)));
    else
        v = default;
    end
end
