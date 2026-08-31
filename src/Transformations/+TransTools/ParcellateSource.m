function [regionCourses, regionLabels, info] = ParcellateSource(sourceSigned, sourcemodel, opts)
%PARCELLATESOURCE  Anatomical region time courses from a vertex-wise source estimate.
%   [COURSES, LABELS, INFO] = ParcellateSource(SOURCESIGNED, SOURCEMODEL, OPTS)
%   reduces a nVertex x nTime source estimate to nRegion x nTime, one row per
%   anatomical region, with LABELS naming them.
%
%   SOURCESIGNED must be a SIGNED estimate (TransTools.InverseSolution with
%   Orientation 'normal'). A magnitude estimate would still run, but every
%   region time course would be strictly positive and the sign flipping
%   below would be meaningless -- so this is worth getting right rather than
%   defaulting quietly.
%
%   OPTS fields, all optional:
%     Atlas       atlas name under FieldTrip's template/atlas (default 'aal')
%     Mode        'mean_flip' | 'mean'        (default 'mean_flip')
%     MinVertices drop regions smaller than this (default 20)
%
%   WHY SIGN FLIPPING IS NOT OPTIONAL. Cortex is folded, so two vertices a
%   millimetre apart on opposite walls of a sulcus have nearly OPPOSING
%   normals. Averaging a signed estimate over such a region cancels most of
%   it, and a real effect comes out near zero for a purely geometric reason.
%   'mean_flip' takes the dominant orientation of the region's own normals
%   (the leading singular vector), flips each vertex to agree with it, then
%   averages. That is the standard remedy, and it is why 'mean' is offered
%   but is not the default.
%
%   WHAT THE SIGN THEN MEANS, stated plainly: it is relative to each
%   region's own dominant normal direction, which is a convention, not an
%   anatomical fact. It is NOT comparable between regions. It IS comparable
%   across bins, conditions and subjects WITHIN a region, because every
%   subject shares the same template source model, so the flips are
%   identical for everyone -- and that is exactly the comparison a
%   within-subjects design asks for.
%
%   THE ATLASES ARE VOLUMETRIC AND THE SOURCE MODEL IS A SURFACE.
%   FieldTrip ships no surface parcellation, so each cortical vertex is
%   looked up in the atlas volume by position. Measured against FieldTrip's
%   own cortex_20484 sheet and the AAL atlas: every vertex falls inside the
%   atlas volume, 87.8% get a non-zero label, and 93 of AAL's 116 regions
%   are hit. The 23 that are not are the cerebellum and the deep grey
%   structures -- a cortical sheet HAS no vertices there, so their being
%   empty is the mapping working, not failing. Unlabelled vertices are
%   dropped rather than guessed at.
%
%   CAVEAT WORTH REPEATING WHEREVER THIS IS SHOWN: this is a template head
%   model, template electrodes AND a template atlas. "Left middle temporal
%   gyrus" reads like an anatomical finding in a way "channel P7" never
%   does, and it is not one.
%
%   See also TRANSTOOLS.INVERSESOLUTION, TRANSTOOLS.SURFACENORMALS,
%   TRANSTOOLS.BUILDSOURCEFORWARDMODEL.
    if nargin < 3; opts = struct(); end
    atlasName   = char(string(TransTools.FieldOr(opts, 'Atlas', 'aal')));
    mode        = lower(char(string(TransTools.FieldOr(opts, 'Mode', 'mean_flip'))));
    minVertices = TransTools.FieldOr(opts, 'MinVertices', 20);

    [vertexLabel, allLabels] = TransTools.AtlasVertexLabels(sourcemodel, atlasName);
    normals = TransTools.SurfaceNormals(sourcemodel);

    nTime = size(sourceSigned, 2);
    keep = false(numel(allLabels), 1);
    courses = zeros(numel(allLabels), nTime);
    counts = zeros(numel(allLabels), 1);

    for r = 1:numel(allLabels)
        v = find(vertexLabel == r);
        % A vertex whose estimate is NaN (marked outside the head by the
        % inverse) cannot contribute; a region left with too few usable
        % vertices is dropped rather than reported from a handful.
        v = v(all(isfinite(sourceSigned(v, :)), 2));
        counts(r) = numel(v);
        if numel(v) < minVertices
            continue;
        end

        block = sourceSigned(v, :);
        if strcmp(mode, 'mean_flip')
            block = block .* flipSigns(normals(v, :));
        end
        courses(r, :) = mean(block, 1);
        keep(r) = true;
    end

    regionCourses = courses(keep, :);
    regionLabels  = allLabels(keep);

    info = struct();
    info.Atlas          = atlasName;
    info.Mode           = mode;
    info.VertexCounts   = counts(keep);
    info.NRegionsTotal  = numel(allLabels);
    info.NRegionsKept   = nnz(keep);
    info.NVertexLabelled = nnz(vertexLabel > 0);
    info.NVertexTotal   = numel(vertexLabel);
    info.ScaleNote = ['Sign is relative to each region''s own dominant cortical normal: ' ...
        'comparable across bins and subjects within a region, NOT between regions. ' ...
        'Template head model, template electrodes and template atlas -- a region name ' ...
        'here is an approximation, not a localization.'];
end

% ======================================================================= %
function s = flipSigns(regionNormals)
%FLIPSIGNS  +1/-1 per vertex, aligning a region's normals to their own
%   dominant direction. The leading left singular vector of the region's
%   normals IS that direction (the unit vector best aligned with all of
%   them); each vertex then agrees or opposes, and opposing ones are
%   flipped so a sulcal wall reinforces its gyral partner instead of
%   cancelling it.
    [~, ~, V] = svd(regionNormals, 'econ');
    dominant = V(:, 1);
    s = sign(regionNormals * dominant);
    s(s == 0) = 1;                     % a normal exactly orthogonal to it
end
