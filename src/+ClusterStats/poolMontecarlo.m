function stat = poolMontecarlo(results, counts, cfg)
%POOLMONTECARLO  Rebuild the one-run result from the chunks' null distributions.
%   STAT = poolMontecarlo(RESULTS, COUNTS, CFG) combines the per-chunk
%   results of a split permutation run into the single result one
%   unsplit run of sum(COUNTS) permutations would have produced.
%
%   Its own function, rather than a local one inside runMontecarlo, purely
%   so it can be tested directly: this is where a split run could silently
%   disagree with an unsplit one, and the test brute-forces the same counts
%   with FieldTrip's own literal loop and demands they match.
%
%   Reproduces ft_statistics_montecarlo's own arithmetic exactly, including
%   the +1 that keeps a Monte Carlo p-value from ever being 0 (the smallest
%   attainable p is 1/(N+1), because the observed labelling is itself one
%   of the possible ones).
    stat = results{1};
    statobs = stat.stat(:);

    posdist = [];
    negdist = [];
    for k = 1:numel(results)
        posdist = [posdist, results{k}.posdistribution(:)']; %#ok<AGROW>
        negdist = [negdist, results{k}.negdistribution(:)']; %#ok<AGROW>
    end
    Nrand = sum(counts);

    prbPos = 1 + countGreaterThan(posdist, statobs);
    prbNeg = 1 + countLessThan(negdist, statobs);
    Nrand  = Nrand + 1;

    switch cfg.tail
        case  1, prob = prbPos ./ Nrand;
        case -1, prob = prbNeg ./ Nrand;
        otherwise, prob = min(prbPos ./ Nrand, prbNeg ./ Nrand);
    end

    stat.prob            = reshape(prob, size(stat.prob));
    stat.mask            = stat.prob <= cfg.alpha;
    stat.posdistribution = posdist;
    stat.negdistribution = negdist;
end

function n = countGreaterThan(dist, x)
%COUNTGREATERTHAN  For each x, how many DIST entries exceed it, strictly.
%   Via a sorted-edge lookup rather than the obvious loop over
%   permutations. The loop is what FieldTrip does and is exactly right at
%   its scale, but here x is a couple of million vertex-by-time points and
%   DIST is a thousand permutations, and two billion element comparisons
%   would add a visible fraction of the runtime we just spent accelerating.
%   discretize is O(numel(x) log numel(dist)) and, written this way, agrees
%   on ties as well: bins are half-open [lo, hi), so counting entries <= x
%   and subtracting is exact even when a permutation lands exactly on an
%   observed value.
    dist = sort(dist(:));
    atMost = discretize(x, [-inf; dist; inf]) - 1;
    n = numel(dist) - atMost;
end

function n = countLessThan(dist, x)
%COUNTLESSTHAN  For each x, how many DIST entries fall below it, strictly.
%   Mirrored through negation: #(d < x) is #(-d > -x), so the same
%   half-open lookup gives the strict comparison on this side too, ties
%   included. An earlier version subtracted this from the total and then
%   subtracted a separate tie count as well, correcting twice for the same
%   thing; the test that brute-forces FieldTrip's own loop caught it.
    n = countGreaterThan(-dist, -x);
end
