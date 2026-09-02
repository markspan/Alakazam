function score = TfceScore(statmap, dim, edges, tfceE, tfceH, tail)
%TFCESCORE  Threshold-free cluster enhancement of a statistic map.
%   SCORE = TfceScore(STATMAP, DIM, EDGES, TFCEE, TFCEH, TAIL) transforms a
%   nSpace*nTime statistic map into its TFCE score, using the compiled
%   kernel (TransTools.EnsureTfceMex) over the lattice EDGES
%   (TransTools.TfceEdges).
%
%   A PORT OF tfce_exact IN FieldTrip's private/tfcestat.m. Each tail is
%   enhanced separately on the rectified map and the negative one is
%   negated back, which is what keeps the sign of an effect meaningful.
%
%   Errors rather than falling back if the kernel is unavailable: the
%   decision to use this path at all is made once, up front, by the caller
%   (see SourceClusterStats), so reaching here without a kernel is a bug
%   and not a machine without a compiler.
%
%   See also TRANSTOOLS.ENSURETFCEMEX, TRANSTOOLS.TFCEEDGES.
    if ~TransTools.EnsureTfceMex()
        throw(MException('Alakazam:TfceScore:noKernel', ...
            'The compiled TFCE kernel is not available on this machine.'));
    end
    statmap = statmap(:);
    score = zeros(prod(dim), 1);
    if tail == 0 || tail == 1
        score = score + alakazam_tfce(max(statmap, 0), edges, tfceE, tfceH);
    end
    if tail == 0 || tail == -1
        score = score - alakazam_tfce(max(-statmap, 0), edges, tfceE, tfceH);
    end
end
