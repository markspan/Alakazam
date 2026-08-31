function normals = SurfaceNormals(sourcemodel)
%SURFACENORMALS  Outward unit normal at every vertex of a cortical sheet.
%   NORMALS = SurfaceNormals(SOURCEMODEL) returns nVertex x 3 unit vectors
%   for a surface carrying .pos and .tri (BuildSourceForwardModel's own
%   second return value).
%
%   WHY THIS EXISTS. A free-orientation inverse gives three dipole
%   components per vertex, and something has to reduce them to one number.
%   Taking their L2 norm gives a magnitude, which is always positive -- so
%   an ERP's polarity disappears, and "the N170 is negative" stops having
%   any expression at all. Projecting onto the cortical normal instead
%   keeps the sign, and is not merely a convenience: pyramidal cells are
%   oriented perpendicular to the cortical sheet and are what EEG mostly
%   measures, so the normal is the physically motivated direction, not an
%   arbitrary one. This is the standard orientation constraint.
%
%   AREA WEIGHTING comes for free. The cross product of two triangle edges
%   has magnitude twice that triangle's area, so accumulating the RAW face
%   normals onto their vertices (rather than normalising each face first)
%   weights each face by its own area, which is what stops a fan of many
%   tiny triangles from outvoting one large neighbour.
%
%   SIGN CONVENTION. Per-vertex normals are only consistent with each other
%   if the mesh's triangle winding is consistent, and "outward" is then
%   still a global choice of which way round. This orients the whole
%   surface so normals point away from its centroid ON AVERAGE. A folded
%   cortex has plenty of individual vertices -- every sulcal wall -- whose
%   normal points back toward the centroid, which is correct and expected;
%   the average over an entire closed sheet is what disambiguates the
%   global flip, and no individual vertex is moved by it.
%
%   The convention matters less than its STABILITY. Alakazam's source
%   models are templates, identical for every subject, so whatever sign a
%   vertex gets here it gets for everyone, and a signed source map means the
%   same thing from one recording to the next.
%
%   See also TRANSTOOLS.BUILDSOURCEFORWARDMODEL, TRANSTOOLS.INVERSESOLUTION.
    if ~isstruct(sourcemodel) || ~isfield(sourcemodel, 'pos') || ~isfield(sourcemodel, 'tri')
        throw(MException('Alakazam:SurfaceNormals', ...
            ['Problem in SurfaceNormals: I need a surface with .pos and .tri to work out ' ...
             'which way the cortex faces. A volumetric grid has no normals, so a signed ' ...
             'orientation is not available for one.']));
    end

    pos = double(sourcemodel.pos);
    tri = double(sourcemodel.tri);
    nVertex = size(pos, 1);

    e1 = pos(tri(:, 2), :) - pos(tri(:, 1), :);
    e2 = pos(tri(:, 3), :) - pos(tri(:, 1), :);
    faceNormals = cross(e1, e2, 2);   % NOT normalised: see AREA WEIGHTING above

    normals = zeros(nVertex, 3);
    for corner = 1:3
        for axis = 1:3
            normals(:, axis) = normals(:, axis) + ...
                accumarray(tri(:, corner), faceNormals(:, axis), [nVertex, 1]);
        end
    end

    len = vecnorm(normals, 2, 2);
    len(len == 0) = 1;                % an unreferenced vertex keeps a zero normal
    normals = normals ./ len;

    % Global outward orientation, decided by the whole surface rather than
    % by any one vertex -- see SIGN CONVENTION above.
    outward = pos - mean(pos, 1);
    if sum(sum(normals .* outward, 2)) < 0
        normals = -normals;
    end
end
