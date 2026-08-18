function brainPatch = DrawBrainMap(ax, values, chanlocs, mapLimit, mesh, brainPatch)
%DRAWBRAINMAP  Project scalp ERP VALUES onto a 3D brain MESH and draw (or
%   update) it in AX as a coloured, rotatable patch.
%
%   VALUES is one value per channel in CHANLOCS, in the same order (both
%   length n) -- CHANLOCS a struct array with resolved .X/.Y/.Z position
%   fields, as produced by TransTools.ResolveScalpDistribution's own 10-5
%   template lookup (the same CHANLOCS DrawScalpMap takes). MESH is a
%   struct with .Vertices (Nx3 mm) / .Faces (Mx3, 1-based), as produced by
%   TransTools.ReadBrainMeshNV. MAPLIMIT is a single positive scalar; the
%   colour scale is fixed to [-MAPLIMIT, MAPLIMIT], matching
%   ResolveScalpDistribution's own shared, symmetric colour scale.
%
%   BRAINPATCH, if given and still a valid patch graphics object, is
%   updated in place instead of being rebuilt (the bundled BrainMesh_ICBM152
%   mesh has 81,924 vertices / 163,840 faces, rebuilt on every slider tick
%   would visibly lag) -- the actual create-vs-update/lighting/starting-view
%   drawing is TransTools.DrawBrainPatch, shared with DrawSourceMap's own
%   source-estimate mesh; see its own header comment for the full
%   reasoning. This function's own job is only the scalp->mesh projection
%   math below.
%
%   Coordinate alignment: CHANLOCS.X/Y/Z (from the standard_1005.elc
%   template) and MESH.Vertices (from BrainMesh_ICBM152.nv) are both
%   real-world mm Cartesian coordinates, both already centred on the
%   origin with a comparable head radius (~85-90mm electrodes enclosing a
%   ~70mm-radius brain -- verified directly against both files, see
%   src/Meshes/README.md) -- so no separate registration/rescaling step is
%   applied here. Good enough for a striking, roughly anatomically
%   plausible rendering; not a validated coregistration or a source
%   localisation of any kind (this is still scalp-measured amplitude, only
%   painted onto a brain-shaped surface for legibility).
%
%   Interpolation: spherical (angular) inverse-distance weighting --
%   Shepard's method using the angle between unit vectors from the origin
%   to each electrode and each mesh vertex, rather than flat Euclidean
%   distance, since both point sets sit roughly on concentric spherical
%   shells around the head centre. This is NOT topoplot.m's biharmonic
%   spherical spline (DrawScalpMap's own 'v4' griddata), nor a port of
%   EEGLAB's headplot.m (which needs its own precomputed .spl file per
%   montage/mesh pair, out of scope for an 81,924-vertex mesh headplot was
%   never set up for) -- a simpler, direct approximation. Smooth, and
%   exact at each electrode's own location; a legitimate approximation,
%   not a claim of matching either method bit-for-bit:
%       w_i(v) = 1 / (1 - cos(theta_i(v)) + EPSILON) ^ POWER
%   normalised so the weights across electrodes sum to 1 at every vertex.
%
%   See also READBRAINMESHNV, DRAWSCALPMAP, BRAIN3DVIEW.
    EPSILON = 1e-6;
    POWER = 4;   % higher = more localised around each electrode; lower = smoother/blurrier

    elecXYZ  = [chanlocs.X; chanlocs.Y; chanlocs.Z]';   % nElec x 3
    elecUnit = elecXYZ ./ vecnorm(elecXYZ, 2, 2);

    vertXYZ  = mesh.Vertices;                            % nVert x 3
    vertUnit = vertXYZ ./ vecnorm(vertXYZ, 2, 2);

    cosTheta = vertUnit * elecUnit';                      % nVert x nElec
    w = 1 ./ (1 - cosTheta + EPSILON) .^ POWER;
    vertexValues = (w * double(values(:))) ./ sum(w, 2);  % nVert x 1

    if nargin < 6
        brainPatch = [];
    end
    brainPatch = TransTools.DrawBrainPatch(ax, mesh.Vertices, mesh.Faces, vertexValues, ...
        TransTools.DivergingColormap(), [-mapLimit, mapLimit], brainPatch);   % same diverging scale as DrawScalpMap
end
