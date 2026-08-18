function seed = mergeSeedFields(seed, stored)
%MERGESEEDFIELDS  Overlay STORED's non-empty fields onto SEED, field by
%   field (SEED's own field list, so STORED can carry stale/extra fields
%   from an older options-struct shape harmlessly). A no-op when STORED is
%   not a struct at all (e.g. the 'Init' sentinel, or no stored options
%   for this transformation yet).
%
%   This is the flat-struct case only; SelectDataDialog.m and
%   FilterDialog.m each have their own differently-shaped mergeSeed
%   (recursing into a fixed set of named sub-structs, with FilterDialog's
%   also doing per-field type validation) -- genuinely different logic,
%   not consolidated here. Previously reimplemented, identically, in
%   ReRefDialog.m and InterpolateDialog.m; consolidated here.
    if ~isstruct(stored); return; end
    f = fieldnames(seed);
    for j = 1:numel(f)
        if isfield(stored, f{j}) && ~isempty(stored.(f{j}))
            seed.(f{j}) = stored.(f{j});
        end
    end
end
