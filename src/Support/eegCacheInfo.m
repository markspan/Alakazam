function info = eegCacheInfo(EEG)
%EEGCACHEINFO  The handful of scalar/short fields that identify what kind
%   of cache node an EEG struct is, without needing its bulk contents
%   (EEG.data, EEG.event, ...) -- what a JSON sidecar (see saveEegCache /
%   readEegCacheInfo) stores next to a cache .mat file, so a scan like
%   findGrandAverageCandidates can tell what kind of node a file is
%   without paying to load it (these cache trees run to tens of GB, almost
%   all of it continuous data no such scan actually needs).
    info = struct();
    info.id             = charFieldOr(EEG, 'id', '');
    info.Call           = charFieldOr(EEG, 'Call', '');
    info.DataFormat     = charFieldOr(EEG, 'DataFormat', '');
    info.DataType       = charFieldOr(EEG, 'DataType', '');
    info.hasErsp        = isfield(EEG, 'ersp') && ~isempty(EEG.ersp);
    info.hasCoherence   = isfield(EEG, 'coherence') && ~isempty(EEG.coherence);
    info.isGrandAverage = isfield(EEG, 'etc') && isfield(EEG.etc, 'GrandAverage') ...
        && ~isempty(EEG.etc.GrandAverage);
    if isfield(EEG, 'bindesc') && ~isempty(EEG.bindesc)
        info.bindescLabels = {EEG.bindesc.label};
    else
        info.bindescLabels = {};
    end
    % Every top-level field name EEG carries -- generic enough to answer
    % any future "does this node have field X" check (e.g.
    % collectEntriesWithField's isfield(EEG, 'measurements' / 'spectralMeasures')
    % pre-filter for the ERP/spectral report exports) without needing a new
    % dedicated info.hasX flag added here every time one comes up.
    info.fieldNames = fieldnames(EEG)';
end

function v = charFieldOr(EEG, name, default)
%CHARFIELDOR  A CHAR accessor, not TransTools.FieldOr: it coerces through string() so
%   the sidecar records text whatever the field held.
    if isfield(EEG, name) && ~isempty(EEG.(name))
        v = char(string(EEG.(name)));
    else
        v = default;
    end
end
