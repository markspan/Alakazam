function v = FieldOr(s, name, default)
%FIELDOR  S.(NAME) if S is a struct with that field non-empty, else DEFAULT.
%   The "read an options struct field with a fallback" one-liner every
%   transformation needs when parsing its own OPTS -- previously
%   reimplemented, identically, as a private local function under six
%   different names (getField/fieldOr/getf) in CoherenceMap.m,
%   CoherenceTopography.m, Resample.m, SpectralMeasure.m, ArtefactDetect.m
%   and +TransTools/ComputeCoherenceTopography.m; consolidated here so
%   there is one definition instead of six copies to keep in sync.
    if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
        v = s.(name);
    else
        v = default;
    end
end
