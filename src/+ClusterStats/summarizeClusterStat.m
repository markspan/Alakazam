function clusters = summarizeClusterStat(stat, alpha)
%SUMMARIZECLUSTERSTAT  Turn FieldTrip's raw cluster-statistics output into a
%   plain, sorted list a researcher can actually read.
%
%   STAT is ft_timelockstatistics'/ft_freqstatistics' own return struct
%   (cfg.correctm = 'cluster' or 'tfce'), documented and stable across
%   FieldTrip releases:
%     .label                 Nx1 cellstr channel labels
%     .time                  1xT vector, seconds
%     .prob                  chan x time p-values (each cluster's own p,
%                             propagated to every point in it; 1 elsewhere)
%     .mask                  chan x time logical, true inside a cluster
%                             significant at cfg.alpha
%     .posclusters           struct array, one per positive-going cluster,
%                             each with .prob (that cluster's p-value)
%     .posclusterslabelmat   chan x time, each point's cluster INDEX into
%                             .posclusters (0 = not in any positive cluster)
%     .negclusters / .negclusterslabelmat   the same for negative clusters
%   ALPHA is the significance level to report against (typically the same
%   cfg.alpha the test itself used).
%
%   CLUSTERS is a struct array, one row per cluster FOUND (positive and
%   negative together, regardless of significance -- a near-miss cluster is
%   still worth seeing), sorted by p-value ascending:
%     .sign          'positive' / 'negative'
%     .pValue
%     .significant   pValue < ALPHA
%     .channels      cellstr of every channel the cluster touches
%     .timeRangeMs   [first last], milliseconds (converted back from
%                    FieldTrip's own seconds)
%     .nPoints       number of chan x time points in the cluster (its
%                    spatiotemporal extent, not a test statistic)
%     .clusterIndex  this cluster's own index WITHIN ITS SIGN (i.e. into
%                    stat.posclusterslabelmat/stat.negclusterslabelmat,
%                    matching the sign in .sign) -- lets a caller rebuild
%                    this exact cluster's own per-point mask later (see
%                    exportClusterStatsCSVs.m) without re-deriving the
%                    ranking done here. NaN for a TFCE row (see below),
%                    which has no discrete per-cluster index to give.
%
%   TFCE (cfg.correctm = 'tfce') has no discrete clusters to report --
%   ft_statistics_montecarlo's own output for it carries .prob/.mask only,
%   no *clusters*/*clusterslabelmat fields -- so this returns a single
%   summary row per sign instead, built straight from the mask (see
%   summarizeFromMaskOnly below), rather than failing on the missing
%   fields.
    if nargin < 2 || isempty(alpha)
        alpha = 0.05;
    end

    hasClusterFields = isfield(stat, 'posclusters') || isfield(stat, 'negclusters');
    if ~hasClusterFields
        clusters = summarizeFromMaskOnly(stat, alpha);
        return;
    end

    clusters = struct('sign', {}, 'pValue', {}, 'significant', {}, ...
        'channels', {}, 'timeRangeMs', {}, 'nPoints', {}, 'clusterIndex', {});
    clusters = appendSignClusters(clusters, stat, alpha, 'positive');
    clusters = appendSignClusters(clusters, stat, alpha, 'negative');

    if ~isempty(clusters)
        [~, order] = sort([clusters.pValue]);
        clusters = clusters(order);
    end
end

function clusters = appendSignClusters(clusters, stat, alpha, sign)
    if strcmp(sign, 'positive')
        clusterList = getfieldOr(stat, 'posclusters', struct([]));
        labelMat    = getfieldOr(stat, 'posclusterslabelmat', []);
    else
        clusterList = getfieldOr(stat, 'negclusters', struct([]));
        labelMat    = getfieldOr(stat, 'negclusterslabelmat', []);
    end
    for c = 1:numel(clusterList)
        mask = labelMat == c;
        if ~any(mask(:))
            continue; % defensive: a cluster struct with no matching points
        end
        [chanIdx, timeIdx] = find(mask);
        entry.sign         = sign;
        entry.pValue       = clusterList(c).prob;
        entry.significant  = entry.pValue < alpha;
        entry.channels     = unique(stat.label(chanIdx), 'stable');
        entry.timeRangeMs  = [min(stat.time(timeIdx)), max(stat.time(timeIdx))] * 1000;
        entry.nPoints      = nnz(mask);
        entry.clusterIndex = c;
        clusters(end + 1) = entry; %#ok<AGROW>
    end
end

function clusters = summarizeFromMaskOnly(stat, alpha)
%SUMMARIZEFROMMASKONLY  TFCE (or any correctm with no discrete cluster
%   list) fallback: one row per sign actually present in the mask, built
%   from stat.stat's own sign at each masked point rather than a cluster
%   index, since TFCE has none.
    clusters = struct('sign', {}, 'pValue', {}, 'significant', {}, ...
        'channels', {}, 'timeRangeMs', {}, 'nPoints', {}, 'clusterIndex', {});
    if ~isfield(stat, 'mask') || ~any(stat.mask(:))
        return;
    end
    for sign = ["positive", "negative"]
        if sign == "positive"
            mask = stat.mask & stat.stat > 0;
        else
            mask = stat.mask & stat.stat < 0;
        end
        if ~any(mask(:))
            continue;
        end
        [chanIdx, timeIdx] = find(mask);
        entry.sign        = char(sign);
        entry.pValue       = min(stat.prob(mask));
        entry.significant  = entry.pValue < alpha;
        entry.channels     = unique(stat.label(chanIdx), 'stable');
        entry.timeRangeMs  = [min(stat.time(timeIdx)), max(stat.time(timeIdx))] * 1000;
        entry.nPoints       = nnz(mask);
        entry.clusterIndex = NaN;
        clusters(end + 1) = entry; %#ok<AGROW>
    end
end

function value = getfieldOr(s, field, default)
    if isfield(s, field)
        value = s.(field);
    else
        value = default;
    end
end
