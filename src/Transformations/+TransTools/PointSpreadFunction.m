function [psf, info] = PointSpreadFunction(vertex, leadfield, sourcemodel, elec, headmodel, method, opts)
%POINTSPREADFUNCTION  What this analysis's own inverse does to a single
%   active vertex.
%
%   [PSF, INFO] = PointSpreadFunction(VERTEX, LEADFIELD, SOURCEMODEL, ELEC,
%   HEADMODEL, METHOD, OPTS) returns one value per SOURCEMODEL vertex: the
%   source estimate that would be obtained if VERTEX, and nothing else in
%   the head, were active with unit strength.
%
%   THE WHOLE COMPUTATION IS THREE LINES, AND THAT IS THE POINT. A point
%   spread function is the source estimate of the scalp pattern a unit
%   source would produce, so it needs no algebra of its own:
%
%     1. the scalp pattern that vertex would produce is its own leadfield
%        column, projected onto the cortical normal (the orientation the
%        analysis itself assumes, see TransTools.SurfaceNormals);
%     2. that pattern is fed to TransTools.InverseSolution as if it were
%        measured data;
%     3. what comes back over the vertices IS the point spread function.
%
%   ROUTE (2) RATHER THAN THE RESOLUTION MATRIX. The textbook definition is
%   a column of R = M*L, so the obvious implementation asks for the inverse
%   operator M and multiplies. InverseSolution deliberately keeps its
%   spatial filter private: the projection through it, the per-method
%   scaling and the dSPM normalisation all live in one place there, and a
%   caller reimplementing "M times a leadfield column" would be a second,
%   drifting copy of exactly that. Feeding the pattern in as DATA reuses the
%   analysis's own inverse, including its own regularisation and its own
%   normalisation, so the answer is in the same units the report quotes and
%   cannot fall out of step with them.
%
%   OPTS is passed through to InverseSolution unchanged, so pass the
%   analysis's own (RegParam, Orientation, and Normals if it has them). The
%   surface normals are computed here when OPTS does not carry them.
%
%   ONE CONSEQUENCE WORTH KNOWING: because InverseSolution's spatial filter
%   depends only on the leadfield and the regularisation, and is cached on
%   exactly that, computing a point spread function straight after an
%   analysis that used the same model and settings costs a matrix-vector
%   product rather than another inverse solve.
%
%   INFO reports:
%     .Vertex        the vertex asked about
%     .PeakVertex    where the estimate actually peaks
%     .PeakErrorMm   the distance between those two, in mm
%     .DispersionMm  spatial dispersion, sqrt(sum(d^2 w) / sum(w)) with
%                    w = psf^2 and d the geodesic-free straight-line
%                    distance from VERTEX. The standard resolution metric
%                    (Molins et al., 2008; Hauk, Wakeman & Henson, 2011):
%                    how far, on average, the estimate of this vertex is
%                    actually drawn from.
%     .ScaleLabel    InverseSolution's own words for the units
%
%   PEAK ERROR AND DISPERSION ARE DIFFERENT FAILURES. A large peak error
%   means the estimate is in the wrong place; a large dispersion means it is
%   in roughly the right place and covers far too much of the cortex. A
%   template-based EEG inverse is expected to be good at neither, and a peak
%   error of essentially zero alongside a dispersion of tens of millimetres
%   is the normal picture: the map is centred correctly and is very much
%   smoother than it looks.
%
%   See also TRANSTOOLS.INVERSESOLUTION, TRANSTOOLS.SURFACENORMALS,
%   TRANSTOOLS.BUILDSOURCEFORWARDMODEL, GENERATESOURCECLUSTERASSETS.
    if nargin < 7 || isempty(opts); opts = struct(); end

    nVertex = size(sourcemodel.pos, 1);
    if ~isscalar(vertex) || ~isnumeric(vertex) || vertex < 1 || vertex > nVertex || ...
            vertex ~= fix(vertex)
        throw(MException('Alakazam:PointSpreadFunction', ...
            ['Problem in PointSpreadFunction: I was asked for the point spread of ' ...
             'vertex %s on a sheet of %d vertices.'], mat2str(vertex), nVertex));
    end
    if ~leadfield.inside(vertex) || isempty(leadfield.leadfield{vertex})
        throw(MException('Alakazam:PointSpreadFunction', ...
            ['Problem in PointSpreadFunction: vertex %d is outside the forward model, ' ...
             'so it has no scalp pattern to spread.'], vertex));
    end

    normals = TransTools.FieldOr(opts, 'Normals', []);
    if isempty(normals)
        normals = TransTools.SurfaceNormals(sourcemodel);
    end
    if size(normals, 1) ~= nVertex
        throw(MException('Alakazam:PointSpreadFunction', ...
            ['Problem in PointSpreadFunction: I was given %d surface normals for a ' ...
             'sheet of %d vertices. Those have to describe the same surface, or the ' ...
             'source would be oriented by somebody else''s cortex.'], ...
            size(normals, 1), nVertex));
    end
    opts.Normals = normals;

    % Step 1: the scalp pattern of a unit source at VERTEX, oriented along
    % its own cortical normal. leadfield.leadfield{i} is nChan x 3, one
    % column per dipole component, so this is a plain change of basis and
    % not a modelling choice: the analysis already assumes this orientation.
    pattern = leadfield.leadfield{vertex} * normals(vertex, :)';

    % Step 2 and 3: the analysis's own inverse, applied to that pattern.
    [psf, solveInfo] = TransTools.InverseSolution(pattern, leadfield, elec, ...
        headmodel, method, opts);
    psf = psf(:, 1);

    distance = vecnorm(sourcemodel.pos - sourcemodel.pos(vertex, :), 2, 2);

    % NaN is how InverseSolution marks a vertex outside the model, so it is
    % excluded from both metrics rather than being read as zero activity.
    % Getting this wrong is one of the two ways a point spread function goes
    % obviously wrong, the other being the orientation above.
    finite = isfinite(psf);
    weight = zeros(nVertex, 1);
    weight(finite) = psf(finite) .^ 2;

    [~, peak] = max(weight);
    total = sum(weight);

    info = struct();
    info.Vertex       = vertex;
    info.PeakVertex   = peak;
    info.PeakErrorMm  = distance(peak);
    if total > 0
        info.DispersionMm = sqrt(sum(distance .^ 2 .* weight) / total);
    else
        info.DispersionMm = NaN;
    end
    info.Method     = solveInfo.Method;
    info.ScaleLabel = solveInfo.ScaleLabel;
end
