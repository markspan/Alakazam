function [s, cfg, dat] = tfceStatfun(cfg, dat, design)
%TFCESTATFUN  Any FieldTrip statistic, TFCE-enhanced, as a statfun.
%   Wraps whichever base statistic the contrast calls for (dependent
%   samples, independent samples, ...) and returns its TFCE score, so that
%   FieldTrip's own permutation machinery treats the enhanced map as "the
%   statistic".
%
%   WHY THIS EXISTS: IT MAKES THE ACCELERATION NEED NO PATCHING. FieldTrip
%   applies TFCE inside ft_statistics_montecarlo, by calling a function in
%   its own private/ folder, which cannot be shadowed from outside. But its
%   two correction branches are literally the same code:
%
%       if strcmp(cfg.correctm, 'max') || strcmp(cfg.correctm, 'tfce')
%         prb_pos = prb_pos + (statobs<max(statrand(:)));
%
%   so correctm='max' with a statfun that has ALREADY applied TFCE is
%   algebraically identical to correctm='tfce', while putting our compiled
%   kernel (TransTools.TfceScore) in the loop. FieldTrip stays stock, we own
%   only the transform, and the equivalence is asserted rather than assumed:
%   SourceClusterMexTest runs both routes under one seed and requires the
%   p-values to be identical.
%
%   The one piece of hidden state this could have depended on is cfg.height,
%   which tfcestat computes from the observed map and reuses across
%   permutations. It is read only by the 'discrete' method; 'exact', which
%   this reproduces, never touches it.
%
%   A SECOND REASON TO PREFER THIS ROUTE: correctm='max' returns
%   .posdistribution/.negdistribution and correctm='tfce' does not, and
%   those are exactly what pooling permutations across parallel workers
%   needs (see ClusterStats.runMontecarlo).
%
%   Parameters arrive under cfg.alakazamTfce rather than FieldTrip's own
%   cfg.tfce_* names, which montecarlo actively marks unused when correctm
%   is not 'tfce':
%     .base   the underlying statistic ('depsamplesT', ...)
%     .edges  the lattice, from TransTools.TfceEdges
%     .E, .H  TFCE extent and height exponents
%
%   Returns .stat (the TFCE map, which drives the inference) and .statraw
%   (the underlying statistic). FieldTrip copies unrecognised fields of the
%   OBSERVED call's result onto its output, so .statraw survives and the
%   caller can present the raw statistic exactly as the unaccelerated path
%   does.
%
%   See also SOURCECLUSTERSTATS, CLUSTERSTATS.RUNMONTECARLO,
%   TRANSTOOLS.TFCESCORE, TRANSTOOLS.TFCEEDGES.
    opt = cfg.alakazamTfce;

    raw = feval(baseFun(opt.base), cfg, dat, design);
    if isstruct(raw)
        raw = raw.stat;
    end

    s = struct();
    s.stat    = TransTools.TfceScore(raw, cfg.dim, opt.edges, opt.E, opt.H, cfg.tail);
    s.statraw = raw;
end

function fun = baseFun(name)
%BASEFUN  FieldTrip's own naming convention, applied the way it applies it.
    if isa(name, 'function_handle')
        fun = name;
        return;
    end
    name = char(name);
    if ~startsWith(name, 'ft_statfun_')
        name = ['ft_statfun_' name];
    end
    fun = str2func(name);
end
