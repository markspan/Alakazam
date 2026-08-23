function [statCsv, waveformCsv, outlineCsv] = exportClusterStatsCSVs(summary, targetStem)
%EXPORTCLUSTERSTATSCSVS  Write the three long-format CSVs
%   generateClusterStatsReport.m's own R plots read from: TARGETSTEM +
%   "_stat.csv" (one row per channel x time point: the raw test
%   statistic, its 2D plotting position, and -- if that point is part of
%   a cluster -- that cluster's own rank/sign/p-value/significance),
%   TARGETSTEM + "_waveform.csv" (one row per subject x channel x time x
%   condition: the actual per-subject waveforms the test ran on, for a
%   time-course plot), and TARGETSTEM + "_outline.csv" (head/nose/ears
%   contour line segments, for drawing a recognisable scalp outline
%   behind the electrode positions).
%
%   SUMMARY is a ClusterStats() return struct. Unlike
%   exportMeasurementsCSV (which walks the whole workspace), this exports
%   just the one test SUMMARY already holds -- there is no bulk/multi-test
%   variant of a cluster test the way there is for Measure windows.
    statCsv     = [targetStem '_stat.csv'];
    waveformCsv = [targetStem '_waveform.csv'];
    outlineCsv  = [targetStem '_outline.csv'];

    writeStatCsv(statCsv, summary);
    writeWaveformCsv(waveformCsv, summary);
    writeOutlineCsv(outlineCsv, summary.layout);
end

% ----------------------------------------------------------------------- %
function writeStatCsv(file, summary)
    stat = summary.stat;
    nChan = numel(stat.label);
    nTime = numel(stat.time);

    % One rank/sign/p/significant per (channel,time) point, 0/''/'NaN'/0 if
    % not part of any cluster -- built as chan x time arrays first (one
    % pass per cluster, using its own clusterIndex to rebuild exactly the
    % mask summarizeClusterStat found it from), then flattened below.
    rank = zeros(nChan, nTime);
    sign = repmat({''}, nChan, nTime);
    pVal = nan(nChan, nTime);
    sig  = false(nChan, nTime);
    for r = 1:numel(summary.clusters)
        c = summary.clusters(r);
        mask = clusterMask(stat, c);
        rank(mask) = r;
        sign(mask) = {c.sign};
        pVal(mask) = c.pValue;
        sig(mask)  = c.significant;
    end

    xOf = positionLookup(summary.layout, stat.label, 1);
    yOf = positionLookup(summary.layout, stat.label, 2);

    fid = openOrThrow(file);
    closeFile = onCleanup(@() fclose(fid));
    fprintf(fid, 'channel,time_ms,statistic,x,y,cluster_rank,sign,cluster_p,significant\n');
    for ch = 1:nChan
        for t = 1:nTime
            fprintf(fid, '%s,%.4g,%.6g,%.4g,%.4g,%s,%s,%s,%d\n', ...
                csvField(stat.label{ch}), stat.time(t) * 1000, stat.stat(ch, t), ...
                xOf(ch), yOf(ch), rankField(rank(ch, t)), csvField(sign{ch, t}), ...
                pField(pVal(ch, t)), sig(ch, t));
        end
    end
end

function mask = clusterMask(stat, cluster)
%CLUSTERMASK  Rebuild CLUSTER's own chan x time membership mask. A
%   discrete cluster (cluster.clusterIndex a real index) is rebuilt from
%   the matching pos/negclusterslabelmat; a TFCE row (clusterIndex NaN,
%   see summarizeClusterStat's own header) has no discrete index to
%   rebuild from, so falls back to stat.mask restricted to this row's own
%   sign, the same derivation summarizeFromMaskOnly itself used.
    if isnan(cluster.clusterIndex)
        if strcmp(cluster.sign, 'positive')
            mask = stat.mask & stat.stat > 0;
        else
            mask = stat.mask & stat.stat < 0;
        end
        return;
    end
    if strcmp(cluster.sign, 'positive')
        mask = stat.posclusterslabelmat == cluster.clusterIndex;
    else
        mask = stat.negclusterslabelmat == cluster.clusterIndex;
    end
end

function pos = positionLookup(layout, labels, column)
%POSITIONLOOKUP  LAYOUT.pos(:,COLUMN) for each of LABELS, in that order;
%   NaN for a label layout has no position for (should not happen in
%   practice -- every channel a cluster test ran on already passed
%   ClusterStats' own "every channel has a 10-5 position" check -- but a
%   plotting CSV degrading to a blank point beats a hard error).
    pos = nan(numel(labels), 1);
    for i = 1:numel(labels)
        match = find(strcmp(layout.label, labels{i}), 1);
        if ~isempty(match)
            pos(i) = layout.pos(match, column);
        end
    end
end

function s = rankField(r)
    if r == 0
        s = 'NA';
    else
        s = sprintf('%d', r);
    end
end

function s = pField(p)
    if isnan(p)
        s = 'NA';
    else
        s = sprintf('%.6g', p);
    end
end

% ----------------------------------------------------------------------- %
function writeWaveformCsv(file, summary)
    fid = openOrThrow(file);
    closeFile = onCleanup(@() fclose(fid));
    fprintf(fid, 'subject,channel,time_ms,condition,value\n');
    for i = 1:numel(summary.timelocks)
        tl = summary.timelocks{i};
        subject   = csvField(summary.timelockSubjects{i});
        condition = csvField(summary.timelockConditions{i});
        for ch = 1:numel(tl.label)
            for t = 1:numel(tl.time)
                fprintf(fid, '%s,%s,%.4g,%s,%.6g\n', ...
                    subject, csvField(tl.label{ch}), tl.time(t) * 1000, condition, tl.avg(ch, t));
            end
        end
    end
end

% ----------------------------------------------------------------------- %
function writeOutlineCsv(file, layout)
    fid = openOrThrow(file);
    closeFile = onCleanup(@() fclose(fid));
    fprintf(fid, 'outline_id,x,y\n');
    for i = 1:numel(layout.outline)
        segment = layout.outline{i};
        for k = 1:size(segment, 1)
            fprintf(fid, '%d,%.4g,%.4g\n', i, segment(k, 1), segment(k, 2));
        end
    end
end

% ----------------------------------------------------------------------- %
function fid = openOrThrow(file)
    fid = fopen(file, 'w');
    if fid < 0
        throw(MException('Alakazam:exportClusterStatsCSVs', 'I''m afraid I could not open "%s" for writing.', file));
    end
end

% csvField lives in src/Support/, shared with exportMeasurementsCSV.m/
% exportSpectralCSV.m/exportGrandAveragesCSV.m.
