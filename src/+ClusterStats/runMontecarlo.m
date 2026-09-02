function stat = runMontecarlo(cfg, timelocks, workers)
%RUNMONTECARLO  ft_timelockstatistics, optionally with the permutations
%   split across parallel workers.
%
%   STAT = runMontecarlo(CFG, TIMELOCKS, WORKERS). With WORKERS <= 1 this is
%   a plain call and nothing below applies.
%
%   WHY THIS IS STATISTICALLY THE SAME TEST, not an approximation of it. A
%   Monte Carlo permutation test draws N independent random relabellings
%   and builds a null distribution from them. Drawing them as one run of N
%   or as K runs of N/K gives the same distribution, provided the draws are
%   independent, so the only real requirement is that each worker permutes
%   DIFFERENTLY. That is not automatic: FieldTrip seeds its RNG per call,
%   so K workers with the same seed would produce K identical copies of the
%   same permutations and a null distribution built from N/K distinct
%   values pretending to be N. Each chunk is therefore given its own
%   cfg.randomseed, and this is the single thing that would silently
%   invalidate the result if it were wrong.
%
%   REQUIRES correctm='max' (which is how the accelerated TFCE route runs,
%   see ClusterStats.tfceStatfun). That branch returns .posdistribution and
%   .negdistribution, the per-permutation extremes, which is what makes
%   pooling possible at all; correctm='tfce' does not return them, so it
%   cannot be split this way.
%
%   The observed statistic is deterministic, so every chunk computes the
%   same one; that duplicated work is one statfun evaluation per worker,
%   against N/K permutations each.
%
%   PARALLELISM IS NOT FREE AND IS NOT ALWAYS WORTH IT. Every worker needs
%   its own copy of every subject's timelock, and the pool has to start.
%   Measured on 18 subjects over the 5124-vertex sheet, 100 permutations
%   took 31 s serially and 58 s across 8 workers: the broadcast cost more
%   than the permutations saved. It pays only once the permutation work is
%   large against that fixed cost, which is why the setting is left to the
%   analyst with a runtime estimate beside it rather than switched on
%   automatically.
%
%   See also SOURCECLUSTERSTATS, CLUSTERSTATS.TFCESTATFUN.
    if nargin < 3 || isempty(workers) || workers <= 1
        stat = ft_timelockstatistics(cfg, timelocks{:});
        return;
    end
    if ~strcmp(cfg.correctm, 'max')
        throw(MException('Alakazam:runMontecarlo:correctm', ...
            'Splitting permutations needs correctm=''max'', which returns the null distributions.'));
    end

    total  = cfg.numrandomization;
    counts = chunkSizes(total, workers);
    workers = numel(counts);

    % Seeds derived once, in the client, so the set is reproducible and
    % visibly distinct rather than left to whatever state each worker starts in.
    seeds = cfg.randomseedBase + (1:workers);

    cfgs = cell(1, workers);
    for k = 1:workers
        c = cfg;
        c.numrandomization = counts(k);
        c.randomseed       = seeds(k);
        cfgs{k} = c;
    end

    % The client's search path is pushed to the workers explicitly. A local
    % pool usually inherits it, but "usually" is not a property to rely on
    % when the failure mode is a worker that cannot see FieldTrip and dies
    % mid-analysis; setting it is cheap and happens once per worker.
    clientPath = path;
    results = cell(1, workers);
    parfor k = 1:workers
        path(clientPath);
        results{k} = ft_timelockstatistics(cfgs{k}, timelocks{:}); %#ok<PFBNS>
    end

    stat = ClusterStats.poolMontecarlo(results, counts, cfg);
end

% ======================================================================= %
function counts = chunkSizes(total, workers)
%CHUNKSIZES  Permutations per worker, as evenly as they divide.
    workers = min(workers, total);
    counts  = repmat(floor(total / workers), 1, workers);
    counts(1:mod(total, workers)) = counts(1:mod(total, workers)) + 1;
    counts = counts(counts > 0);
end
