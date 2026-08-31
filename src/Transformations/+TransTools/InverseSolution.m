function [sourcePower, info] = InverseSolution(values, leadfield, elec, headmodel, method, opts)
%INVERSESOLUTION  A distributed inverse solution, computed by FieldTrip.
%   [SOURCEPOWER, INFO] = InverseSolution(VALUES, LEADFIELD, ELEC, HEADMODEL,
%   METHOD, OPTS) returns the same nVertex x nTime, NaN-outside contract
%   TransTools.ComputeSourceEstimate returns, for METHOD one of:
%
%     'mne'      noise-normalized minimum norm (dSPM, Dale et al. 2000)
%     'eloreta'  exact low-resolution tomography (Pascual-Marqui 2007)
%     'sloreta'  standardized low-resolution tomography (Pascual-Marqui 2002)
%
%   VALUES is nChan x nTime in BuildSourceForwardModel's own RESOLVEDLABELS
%   order (the same requirement, and the same silent-scrambling hazard, as
%   ComputeSourceEstimate -- see its header). ELEC and HEADMODEL are
%   BuildSourceForwardModel's 4th and 5th return values.
%
%   WHY A SHIM RATHER THAN MORE HAND-ROLLED ALGEBRA. ComputeSourceEstimate
%   computes its minimum norm directly, and its header gives two reasons:
%   (1) FieldTrip's cfg options "could not be verified without a FieldTrip
%   installation available while writing this", and (2) a transparent
%   closed-form formula is easier to audit than an opaque cfg struct.
%
%   Reason (1) has since expired -- FieldTrip is installed and its
%   behaviour verifiable. Reason (2) inverts for these methods: the
%   minimum norm genuinely is a one-line closed form, but eLORETA's
%   weighting is an iterative fixed-point solve. Hand-rolling that would be
%   materially HARDER to audit than calling the reference implementation,
%   not easier -- so the boundary moves for eLORETA and sLORETA, and
%   ComputeSourceEstimate stays exactly as it is.
%
%   WHAT IS SHIMMED, AND WHAT DELIBERATELY IS NOT. FieldTrip is asked only
%   for the SPATIAL FILTER ('keepfilter'), the mathematical object each
%   method actually defines. The projection through it, the per-method
%   scaling, the collapse of free-orientation moments and the NaN padding
%   all stay here, in one shared code path. Three things follow: the
%   methods differ ONLY in how their filter is obtained and scaled; every
%   method returns an identically shaped result; and the dSPM
%   normalization -- which is what Alakazam's colour scale MEANS -- stays
%   explicit and auditable here, rather than inferred from whichever
%   convention a given FieldTrip function happens to use for .pow. That
%   last point is reason (2) honoured rather than discarded.
%
%   OPTS fields, all optional:
%     RegParam     relative regularization       (default 0.05)
%     Lambda       override the absolute lambda  (default: from RegParam)
%     Orientation  'magnitude' | 'normal'        (default 'magnitude')
%     Normals      nVertex x 3, required for 'normal'
%
%   ORIENTATION decides how three free-orientation dipole components become
%   one number per vertex, and it is not a cosmetic choice:
%
%     'magnitude'  their L2 norm. Always positive. This is what the 3-D
%                  brain view shows, and what ComputeSourceEstimate has
%                  always returned, so it stays the default -- changing it
%                  would silently alter every existing source map.
%     'normal'     projected onto the cortical normal, KEEPING THE SIGN.
%                  Required for anything a polarity is read off (region
%                  time courses, ERP measures, reports), because a
%                  magnitude cannot express a negative component.
%
%   Pass Normals from TransTools.SurfaceNormals(sourcemodel); the leadfield
%   alone does not carry the .tri needed to compute them.
%
%   LAMBDA MEANS DIFFERENT THINGS PER METHOD, worth stating plainly rather
%   than hiding behind one option name: for 'mne' it is the Tikhonov term
%   in (L*L' + lambda*I); for 'eloreta' and 'sloreta' it is FieldTrip's own
%   relative regularization of that method's own solution. The values are
%   NOT comparable across methods, and neither are the resulting scales --
%   see INFO.ScaleLabel.
%
%   INFO reports .Method, .Lambda, .ScaleLabel (what to write on a
%   colorbar) and .ScaleNote (the caveat that belongs next to it).
%
%   See also TRANSTOOLS.COMPUTESOURCEESTIMATE (the hand-rolled dSPM path
%   this is validated against, see tests/SourceInverseTest.m),
%   TRANSTOOLS.BUILDSOURCEFORWARDMODEL, TRANSTOOLS.DRAWSOURCEMAP.
    if nargin < 6; opts = struct(); end
    method = lower(char(string(method)));

    regParam    = TransTools.FieldOr(opts, 'RegParam', 0.05);
    orientation = lower(char(string(TransTools.FieldOr(opts, 'Orientation', 'magnitude'))));
    normals     = TransTools.FieldOr(opts, 'Normals', []);

    insideIdx    = find(leadfield.inside);
    nVertexTotal = numel(leadfield.inside);
    nTime        = size(values, 2);
    values       = double(values);

    L      = cell2mat(leadfield.leadfield(insideIdx)); % nChan x (3*nInside)
    nChan  = size(L, 1);
    lambda = TransTools.FieldOr(opts, 'Lambda', regParam * trace(L * L') / nChan);

    % The data covariance eLORETA and sLORETA both take as their 5th
    % argument. On an already-averaged ERP (which is what this pipeline
    % feeds it, see ComputeSourceEstimate's own SIMPLIFICATION note) this is
    % the ERP's own covariance across time, not a single-trial one.
    C = (values * values') / max(1, nTime);

    % EACH METHOD CONTRIBUTES A SPATIAL FILTER AND NOTHING ELSE. The
    % projection through it, and the free-orientation collapse below, are
    % written once -- so the header's claim that the methods differ only in
    % how their filter is obtained is something the structure says, not just
    % something a comment asserts.
    switch method
        case 'mne'
            % noisecov = lambda*I with FieldTrip's own lambda at 1 gives
            % w = L'*(L*L' + lambda*I)^-1 -- algebraically IDENTICAL to
            % ComputeSourceEstimate's own M, because FieldTrip's operator is
            % w = R*A'*(A*R*A' + lambda_ft^2*C)^-1, and lambda_ft^2*C is
            % then exactly lambda*I. Passing 'lambda', sqrt(lambda) with
            % C = I would give the same FILTER but a projected noise smaller
            % by a factor lambda, so the dSPM scale would shift globally.
            % Written this way the two paths agree exactly, which is what
            % makes the equivalence testable at all.
            est = ft_inverse_mne(leadfield, elec, headmodel, values, ...
                'noisecov', lambda * eye(nChan), 'lambda', 1, 'keepfilter', 'yes');
            info.ScaleLabel = 'dSPM (noise-normalized)';
            info.ScaleNote  = ['A noise-normalized statistic, not microvolts: roughly how ' ...
                'many noise standard deviations above baseline.'];

        case 'eloreta'
            est = ft_inverse_eloreta(leadfield, elec, headmodel, values, C, ...
                'lambda', regParam, 'keepfilter', 'yes');
            info.ScaleLabel = 'eLORETA (source amplitude)';
            info.ScaleNote  = ['eLORETA source amplitude. Exact zero-error localization of a ' ...
                'single source, but NOT noise-normalized -- not comparable to the dSPM scale.'];

        case 'sloreta'
            est = ft_inverse_sloreta(leadfield, elec, headmodel, values, C, ...
                'lambda', regParam, 'keepfilter', 'yes');
            info.ScaleLabel = 'sLORETA (standardized)';
            info.ScaleNote  = ['sLORETA is standardized by its own resolution matrix, so it is ' ...
                'already a statistic rather than an amplitude -- but standardized differently ' ...
                'from dSPM, and not comparable to it.'];

        otherwise
            throw(MException('Alakazam:InverseSolution', ...
                ['Problem in InverseSolution: I do not know an inverse method called "%s". ' ...
                 'I can do mne, eloreta or sloreta.'], method));
    end

    M = stackFilters(est, insideIdx, nChan);
    J = M * values;

    if strcmp(method, 'mne')
        % dSPM (Dale et al. 2000): divide each dipole-moment row by its own
        % noise standard deviation under Cnoise = lambda*I, i.e.
        % noiseVar = diag(M*Cnoise*M') = lambda*sum(M.^2, 2). Only the
        % minimum norm gets this: eLORETA is an un-normalized amplitude and
        % sLORETA is already standardized, by its own resolution matrix
        % rather than by projected noise.
        J = J ./ sqrt(max(lambda * sum(M .^ 2, 2), eps));
    end

    % Collapse the 3 free-orientation components to one value per vertex per
    % instant. reshape rather than squeeze, for the same reason
    % ComputeSourceEstimate gives.
    nIn   = numel(insideIdx);
    Jresh = reshape(J, 3, nIn, nTime);

    switch orientation
        case 'magnitude'
            % L2 norm: the same convention ComputeSourceEstimate uses (and
            % FieldTrip's own source.avg.pow). Always positive, so ERP
            % polarity is not represented -- fine for a 3-D magnitude map,
            % wrong for anything a sign is read off.
            powInside = reshape(sqrt(sum(Jresh .^ 2, 1)), nIn, nTime);

        case 'normal'
            % Project onto the cortical normal, keeping the sign. See
            % TransTools.SurfaceNormals for why the normal specifically.
            if isempty(normals)
                throw(MException('Alakazam:InverseSolution', ...
                    ['Problem in InverseSolution: a signed (normal-projected) estimate ' ...
                     'needs the cortical surface normals, and none were given. Pass ' ...
                     'opts.Normals from TransTools.SurfaceNormals(sourcemodel).']));
            end
            if size(normals, 1) ~= nVertexTotal || size(normals, 2) ~= 3
                throw(MException('Alakazam:InverseSolution', ...
                    ['Problem in InverseSolution: I was given %dx%d surface normals but ' ...
                     'this source model has %d vertices. Those two have to describe the ' ...
                     'same surface, or the sign would be taken from the wrong vertex.'], ...
                    size(normals, 1), size(normals, 2), nVertexTotal));
            end
            powInside = reshape(sum(Jresh .* normals(insideIdx, :)', 1), nIn, nTime);

        otherwise
            throw(MException('Alakazam:InverseSolution', ...
                ['Problem in InverseSolution: Orientation must be "magnitude" or ' ...
                 '"normal", not "%s".'], orientation));
    end

    sourcePower = nan(nVertexTotal, nTime);
    sourcePower(insideIdx, :) = powInside;

    info.Method = method;
    info.Lambda = lambda;
end

% ======================================================================= %
function M = stackFilters(est, insideIdx, nChan)
%STACKFILTERS  FieldTrip returns one 3 x nChan filter per source point, in a
%   cell array indexed over ALL vertices. Stack the inside ones into the
%   single (3*nInside) x nChan operator the shared projection wants, in
%   exactly insideIdx's order so the reshape further down lines up.
%
%   LEADFIELD is passed to ft_inverse_* as the source model itself:
%   ft_prepare_leadfield's own output already IS a FieldTrip source model
%   carrying a precomputed leadfield (.pos/.inside/.leadfield), and all
%   three functions check isfield(sourcemodel,'leadfield') and use it
%   rather than recomputing. That is what keeps ELEC and HEADMODEL from
%   triggering a second, expensive forward computation; they are still
%   required positionally, and are what the leadfield was built from.
    if ~isfield(est, 'filter') || isempty(est.filter)
        throw(MException('Alakazam:InverseSolution', ...
            ['Problem in InverseSolution: FieldTrip did not return a spatial filter, ' ...
             'so there is nothing to project this data through.']));
    end
    n = numel(insideIdx);
    M = zeros(3 * n, nChan);
    for k = 1:n
        w = est.filter{insideIdx(k)};
        if size(w, 1) ~= 3 || size(w, 2) ~= nChan
            throw(MException('Alakazam:InverseSolution', ...
                ['Problem in InverseSolution: FieldTrip returned a %dx%d filter where I ' ...
                 'expected 3x%d. That usually means the leadfield and the electrode set ' ...
                 'have got out of step.'], size(w, 1), size(w, 2), nChan));
        end
        M(3 * (k - 1) + (1:3), :) = w;
    end
end
