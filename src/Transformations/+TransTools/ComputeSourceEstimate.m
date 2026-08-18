function sourcePower = ComputeSourceEstimate(values, leadfield)
%COMPUTESOURCEESTIMATE  A noise-normalized (dSPM-style) minimum-norm
%   source estimate: per-vertex, per-instant statistic at every column of
%   VALUES.
%
%   VALUES is nChan x nTime (scalp amplitude), its ROWS in EXACTLY
%   BuildSourceForwardModel's own RESOLVEDLABELS order -- not necessarily
%   a caller's own original channel order. Getting this wrong silently
%   scrambles the result with no error to catch it; see
%   BuildSourceForwardModel's own header comment. LEADFIELD is
%   BuildSourceForwardModel's own return value (FieldTrip's leadfield
%   struct: .leadfield, a 1xN cell array of nChan x 3 free-orientation
%   gain matrices, one per candidate source point; .inside, which of the
%   N are usable).
%
%   Returns SOURCEPOWER, nVertex x nTime (nVertex = numel(leadfield.inside),
%   i.e. every one of the sourcemodel's own vertices, in the same order --
%   1:1 with TransTools.DrawSourceMap's mesh), NaN at any vertex
%   LEADFIELD marked outside.
%
%   METHOD: a Tikhonov-regularized minimum-norm inverse, computed directly
%   with the standard closed-form formula --
%       M = L' * inv(L*L' + lambda*I),   J = M * VALUES
%   -- rather than calling FieldTrip's own ft_sourceanalysis. Two reasons:
%   (1) ft_prepare_leadfield's own output shape (.leadfield/.inside) is
%   one of FieldTrip's oldest, most stable structures, used identically
%   for decades; ft_sourceanalysis's own cfg options for MNE regularisation
%   have shifted somewhat across versions, and could not be verified
%   without a FieldTrip installation available while writing this. (2) a
%   direct, transparent formula is easier to audit and debug than trusting
%   an opaque cfg struct's exact expected shape.
%
%   NOISE NORMALIZATION (dSPM, Dale et al. 2000): raw minimum-norm J is
%   biased toward superficial sources (electrically closer to the
%   electrodes, so a larger leadfield, so more sensitive to noise), and its
%   absolute scale has no principled meaning on its own. dSPM corrects
%   both: divide each dipole-moment ROW of J by that row's own noise
%   standard deviation under the SAME assumed noise covariance the
%   regularization itself already uses (see SIMPLIFICATION below) --
%       noiseVar = diag(M * Cnoise * M'),   dSPM = J ./ sqrt(noiseVar)
%   -- giving an approximately unit-variance-under-the-null statistic per
%   vertex (roughly "how many noise standard deviations above baseline"),
%   comparable ACROSS vertices regardless of depth. This is still NOT on a
%   µV-like physical scale -- it is a statistic, not an amplitude -- see
%   Brain3DView's own Source-estimate mode UI for how this is labelled.
%
%   SIMPLIFICATION, stated plainly: Cnoise = lambda*I (the SAME lambda the
%   regularization above already uses, not a separately estimated
%   quantity) -- Alakazam's Brain3D/ScalpDistribution pipeline runs on
%   already-averaged ERPs (post Average.m), not single-trial epoched data,
%   so there is no pre-stimulus baseline available at this stage to
%   estimate a real noise covariance from. This is the same "assume
%   white/identity noise" simplification widely used when no separate
%   baseline/empty-room recording exists; it is a coarser assumption than
%   a real noise-covariance-based inverse (dSPM normally uses an
%   independently estimated Cnoise, not the regularization's own
%   assumption reused for both jobs), and this should be labelled as such
%   wherever the result is shown.
%
%   Free-orientation dipole moments (raw J and the noise-normalized
%   statistic alike) are collapsed to a single per-vertex, per-instant
%   value by their L2 norm across the 3 orientation components (matching
%   FieldTrip's own source.avg.pow convention for a free-orientation MNE
%   solution).
%
%   NOTE: written without a FieldTrip installation available to validate
%   against -- see BuildSourceForwardModel's own header comment.
%
%   See also TRANSTOOLS.BUILDSOURCEFORWARDMODEL, TRANSTOOLS.DRAWSOURCEMAP.
    % lambda as a fraction of L*L''s own average diagonal power. Placeholder:
    % this has not been validated against any real FieldTrip run or known
    % tutorial output (see this file's own NOTE below) -- a too-small value
    % under-regularizes (noisy, spiky source maps), too-large over-smooths
    % (a blurry map that still LOOKS plausible, with no error to catch it
    % either way). Revisit once real end-to-end output is available to
    % check against.
    RegParam = 0.05;

    insideIdx = find(leadfield.inside);
    nVertexTotal = numel(leadfield.inside);
    nTime = size(values, 2);

    L = cell2mat(leadfield.leadfield(insideIdx)); % nChan x (3 * numel(insideIdx))
    nChan = size(L, 1);

    LLt = L * L';
    lambda = RegParam * trace(LLt) / nChan;
    M = L' / (LLt + lambda * eye(nChan)); % (3*nInside) x nChan

    J = M * double(values); % (3*nInside) x nTime

    % dSPM noise normalization: noiseVar(i) = diag(M * (lambda*I) * M')(i)
    % = lambda * (M*M')(i,i) = lambda * sum(M(i,:).^2) -- the row-wise sum
    % of squares, cheap to compute directly (no (3*nInside)-square matrix
    % multiply needed for just the diagonal). Floored well above zero:
    % with Cnoise = lambda*I, noiseVar cannot be exactly zero for any
    % non-degenerate leadfield row, but a floor keeps this safe from a
    % near-singular one regardless.
    noiseVar = max(lambda * sum(M .^ 2, 2), eps); % (3*nInside) x 1
    Jnorm = J ./ sqrt(noiseVar); % broadcasts down the rows; still (3*nInside) x nTime

    Jresh = reshape(Jnorm, 3, numel(insideIdx), nTime);
    % reshape, not squeeze: squeeze can't tell which singleton dimension to
    % drop, so sum(...,1)'s 1 x nInside x nTime would come out nTime x 1
    % instead of the intended nInside x 1 in the (currently unreachable,
    % since BuildSourceForwardModel always marks every vertex inside --
    % see its own header comment) degenerate nInside==1 case.
    powInside = reshape(sqrt(sum(Jresh .^ 2, 1)), numel(insideIdx), nTime);

    sourcePower = nan(nVertexTotal, nTime);
    sourcePower(insideIdx, :) = powInside;
end
