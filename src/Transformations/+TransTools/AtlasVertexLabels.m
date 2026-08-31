function [vertexLabel, labels] = AtlasVertexLabels(sourcemodel, atlasName)
%ATLASVERTEXLABELS  Which anatomical region each cortical vertex sits in.
%   [VERTEXLABEL, LABELS] = AtlasVertexLabels(SOURCEMODEL, ATLASNAME)
%   returns an nVertex x 1 index into LABELS, with 0 for vertices the atlas
%   does not label.
%
%   THE MAPPING IS A VOLUMETRIC LOOKUP, because FieldTrip ships no surface
%   parcellation: every template atlas is a labelled MRI volume, while the
%   source model is a cortical sheet. Each vertex's position is therefore
%   transformed into the atlas's own voxel grid and read off. Both are in
%   MNI space, which is what makes this legitimate rather than a
%   coincidence -- and it was checked rather than assumed: against
%   cortex_20484 and AAL, 100% of vertices land inside the atlas volume and
%   87.8% carry a non-zero label.
%
%   UNLABELLED VERTICES STAY UNLABELLED (0). The ~12% that miss are mostly
%   midline and boundary vertices falling in unlabelled voxels. Assigning
%   them to a nearest labelled neighbour would silently widen every region
%   by an unprincipled amount, so they are dropped instead: a smaller,
%   honest region beats a larger, invented one.
%
%   CACHED, because this is pure geometry. Both the template source model
%   and the template atlas are the same for every subject and every
%   session, so the lookup is computed once per (atlas, vertex count) and
%   reused -- reading and transforming a whole MRI volume per bin, per
%   subject, would be absurd for a result that cannot change.
%
%   See also TRANSTOOLS.PARCELLATESOURCE, TRANSTOOLS.BUILDSOURCEFORWARDMODEL.
    persistent cache
    if isempty(cache)
        cache = struct('key', {}, 'vertexLabel', {}, 'labels', {});
    end

    TransTools.ensureFieldTrip('Region time courses');

    if ~isstruct(sourcemodel) || ~isfield(sourcemodel, 'pos')
        throw(MException('Alakazam:AtlasVertexLabels', ...
            'Problem in AtlasVertexLabels: I need a source model with vertex positions.'));
    end

    key = sprintf('%s|%d', lower(atlasName), size(sourcemodel.pos, 1));
    hit = find(strcmp({cache.key}, key), 1);
    if ~isempty(hit)
        vertexLabel = cache(hit).vertexLabel;
        labels      = cache(hit).labels;
        return;
    end

    atlas = ft_convert_units(ft_read_atlas(atlasFile(atlasName)), 'mm');
    sm    = ft_convert_units(sourcemodel, 'mm');

    labels = atlas.tissuelabel(:);
    nVertex = size(sm.pos, 1);

    % Vertex position (mm) -> atlas voxel index. round(), not floor(): a
    % voxel's coordinate names its CENTRE, so the nearest voxel is the one
    % the vertex is actually in.
    vox = round(atlas.transform \ [sm.pos, ones(nVertex, 1)]');
    vox = vox(1:3, :)';

    inside = all(vox >= 1, 2) & vox(:, 1) <= atlas.dim(1) & ...
             vox(:, 2) <= atlas.dim(2) & vox(:, 3) <= atlas.dim(3);

    vertexLabel = zeros(nVertex, 1);
    vertexLabel(inside) = atlas.tissue(sub2ind(atlas.dim, ...
        vox(inside, 1), vox(inside, 2), vox(inside, 3)));

    cache(end + 1) = struct('key', key, 'vertexLabel', vertexLabel, 'labels', {labels});
end

% ======================================================================= %
function f = atlasFile(name)
%ATLASFILE  The atlas volume for NAME, under FieldTrip's own template/atlas.
%   Only atlases actually verified against the cortical sheet are offered:
%   naming a file that exists is not the same as knowing its labels land on
%   cortex, and an atlas that mapped onto nothing would produce an empty
%   report rather than an error.
    known = struct( ...
        'aal',         fullfile('aal', 'ROI_MNI_V4.nii'), ...
        'brainnetome', fullfile('brainnetome', 'BNA_MPM_thr25_1.25mm.nii'));

    field = lower(char(string(name)));
    if ~isfield(known, field)
        throw(MException('Alakazam:AtlasVertexLabels', ...
            ['Problem in AtlasVertexLabels: I do not have a verified mapping for an atlas ' ...
             'called "%s". I know about: %s.'], field, strjoin(fieldnames(known)', ', ')));
    end

    ftRoot = fileparts(which('ft_defaults'));
    f = fullfile(ftRoot, 'template', 'atlas', known.(field));
    if ~isfile(f)
        throw(MException('Alakazam:AtlasVertexLabels', ...
            ['Problem in AtlasVertexLabels: this FieldTrip install has no atlas file at ' ...
             '%s, so I cannot name any regions.'], f));
    end
end
