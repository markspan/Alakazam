function names = AtlasRegionsAt(pos)
%ATLASREGIONSAT  The AAL region at or near each position (MNI millimetres).
%   NAMES = TransTools.AtlasRegionsAt(POS) returns one name per row of POS,
%   by FieldTrip's ft_volumelookup over its AAL atlas, searching up to five
%   voxels (10 mm) away when the position itself carries no label: a fitted
%   dipole, or the peak of a beamformer map on a volume grid, often lies
%   just beneath the cortex, in white matter no atlas labels. '' where there
%   is no labelled region within that range.
%
%   NOT TransTools.AtlasVertexLabels, which caches its answer by the number
%   of positions and is meant for a fixed cortical sheet: one or two
%   arbitrary positions would share a count with every other one or two.
%
%   Naming is a courtesy: if the atlas cannot be read, every name is ''.
%
%   See also DIPOLEFIT, BEAMFORMER, FT_VOLUMELOOKUP.
    names = repmat({''}, 1, size(pos, 1));
    if isempty(pos)
        return;
    end
    try
        ftRoot = fileparts(which('ft_defaults'));
        atlas = ft_convert_units(ft_read_atlas(fullfile(ftRoot, 'template', 'atlas', 'aal', ...
            'ROI_MNI_V4.nii')), 'mm');
        cfg = struct('roi', pos, 'atlas', atlas, 'output', 'multiple', 'maxqueryrange', 5); %#ok<NASGU> used in evalc
        [~, found] = evalc('ft_volumelookup(cfg, atlas);');
        for k = 1:min(numel(found), numel(names))
            [count, at] = max(found(k).count);
            if ~isempty(count) && count > 0
                names{k} = found(k).name{at};
            end
        end
    catch
        % A map without names is still a map.
    end
end
