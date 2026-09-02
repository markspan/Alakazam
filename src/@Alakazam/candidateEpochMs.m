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
        loaded = load(candidateFiles{i}, 'EEG');
        if ~isfield(loaded.EEG, 'times') || isempty(loaded.EEG.times)
            continue;
        end
        t = double(loaded.EEG.times);
        starts(end + 1) = min(t); %#ok<AGROW>
        stops(end + 1)  = max(t); %#ok<AGROW>
    end
    if isempty(starts)
        return;
    end
    epochMs = [max(starts), min(stops)];
    if epochMs(2) <= epochMs(1)
        epochMs = [];
    end
end
