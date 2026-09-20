function epochMs = candidateEpochMs(this, candidateFiles) %#ok<INUSL>
%CANDIDATEEPOCHMS  The latency range every candidate actually shares, in ms.
%
%   Returns [startMs stopMs], or [] if it cannot be determined. Gathered the
%   same way and for the same reason as candidateBinLabels: so that
%   ClusterStatsDialog can offer a sensible default without doing file I/O
%   of its own.
%
%   THE INTERSECTION, NOT THE UNION. A time window is only usable if every
%   selected subject has data across it, so the widest defensible default is
%   the narrowest epoch in the set. Offering the union would default to a
%   window some subject cannot supply.
%
%   This exists because the alternative was a hard-coded default. The source
%   cluster dialog previously defaulted to 0 to 500 ms regardless of the
%   data, which on a -200 to 800 ms epoch silently dropped both the baseline
%   and the last 300 ms from the analysis, and showed up only as an
%   unexplained axis range in the report.
    epochMs = [];
    starts = []; stops = [];
    for i = 1:numel(candidateFiles)
        % From the meta record, not a load of the whole node.
        range = readEegCacheMeta(candidateFiles{i}).timeRange;
        if isempty(range)
            continue;
        end
        starts(end + 1) = range(1); %#ok<AGROW>
        stops(end + 1)  = range(2); %#ok<AGROW>
    end
    if isempty(starts)
        return;
    end
    epochMs = [max(starts), min(stops)];
    if epochMs(2) <= epochMs(1)
        epochMs = [];
    end
end
