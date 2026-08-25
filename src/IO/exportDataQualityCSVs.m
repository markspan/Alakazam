function [summaryCsv, trialCsv, smeCsv] = exportDataQualityCSVs(entries, targetStem)
%EXPORTDATAQUALITYCSVS  Write the two long-format CSVs
%   generateDataQualityReport.m's own R code reads: TARGETSTEM +
%   "_quality.csv" (one row per subject x bin x channel: rejection rates,
%   pre-stimulus noise and SME) and TARGETSTEM + "_trials.csv" (one row per
%   subject x bin x trial: that trial's own pre-stimulus noise, its z-score
%   within the subject, and whether it was rejected or flagged as a
%   baseline outlier).
%
%   A third, TARGETSTEM + "_sme.csv", carries one row per subject x
%   Measure window x bin x channel: the SME of that window's own score,
%   which estimator produced it, and the score itself (see erpScoreSME).
%   It is written even when no subject has a Measure result, as a
%   header-only file, so the report's own read_csv never has to be made
%   conditional on whether the file exists.
%
%   Three files rather than one because the three have genuinely different
%   grain: each plot in the report is a between-subject comparison of
%   summary rates (the first), a within-subject distribution across trials
%   (the second), or a per-window measurement error (the third), and
%   folding them together would repeat every coarser value once per finer
%   row.
%
%   ENTRIES is a struct array with .subject/.group/.session/.quality, where
%   .quality is one dataQualityMetrics() return -- see
%   Alakazam.collectDataQualityEntries.
%
%   See also DATAQUALITYMETRICS, ERPSCORESME, GENERATEDATAQUALITYREPORT.
    summaryCsv = [targetStem '_quality.csv'];
    trialCsv   = [targetStem '_trials.csv'];
    smeCsv     = [targetStem '_sme.csv'];

    writeSummaryCsv(summaryCsv, entries);
    writeTrialCsv(trialCsv, entries);
    writeSmeCsv(smeCsv, entries);
end

% ----------------------------------------------------------------------- %
function writeSummaryCsv(file, entries)
    fid = openOrThrow(file);
    closeFile = onCleanup(@() fclose(fid));
    fprintf(fid, ['dataset,group,session,bin,channel,n_trials,n_trials_rejected,' ...
        'pct_trials_rejected,n_flagged,pct_flagged,baseline_sd_uv,sme_uv,' ...
        'subject_pct_trials_rejected,subject_pct_channel_epochs_flagged,' ...
        'subject_pct_baseline_outlier_trials,subject_n_trials,subject_n_channels,' ...
        'subject_pct_trials_truncated,subject_max_truncated_pct,subject_rejection_ran\n']);
    for e = 1:numel(entries)
        entry = entries(e);
        s = entry.quality.subject;
        rows = entry.quality.byBinChannel;
        for r = 1:numel(rows)
            fprintf(fid, '%s,%s,%s,%s,%s,%d,%d,%s,%d,%s,%s,%s,%s,%s,%s,%d,%d,%s,%s,%s\n', ...
                csvField(entry.subject), csvField(entry.group), csvField(entry.session), ...
                csvField(rows(r).bin), csvField(rows(r).channel), ...
                rows(r).n_trials, rows(r).n_trials_rejected, num(rows(r).pct_trials_rejected), ...
                rows(r).n_flagged, num(rows(r).pct_flagged), ...
                num(rows(r).baseline_sd_uv), num(rows(r).sme_uv), ...
                num(s.pct_trials_rejected), num(s.pct_channel_epochs_flagged), ...
                num(s.pct_baseline_outlier_trials), s.n_trials, s.n_channels, ...
                num(s.pct_trials_truncated), num(s.max_truncated_pct_of_epoch), ...
                num(s.rejection_ran));
        end
    end
end

function writeTrialCsv(file, entries)
    fid = openOrThrow(file);
    closeFile = onCleanup(@() fclose(fid));
    fprintf(fid, 'dataset,group,session,bin,trial,baseline_sd_uv,baseline_z,rejected,baseline_outlier\n');
    for e = 1:numel(entries)
        entry = entries(e);
        rows = entry.quality.byTrial;
        for r = 1:numel(rows)
            fprintf(fid, '%s,%s,%s,%s,%d,%s,%s,%d,%d\n', ...
                csvField(entry.subject), csvField(entry.group), csvField(entry.session), ...
                csvField(rows(r).bin), rows(r).trial, ...
                num(rows(r).baseline_sd_uv), num(rows(r).baseline_z), ...
                rows(r).rejected, rows(r).baseline_outlier);
        end
    end
end

function writeSmeCsv(file, entries)
    fid = openOrThrow(file);
    closeFile = onCleanup(@() fclose(fid));
    fprintf(fid, 'dataset,group,session,window,bin,channel,measure,method,sme_uv,score\n');
    for e = 1:numel(entries)
        entry = entries(e);
        if ~isfield(entry.quality, 'byWindowChannel')
            continue;
        end
        rows = entry.quality.byWindowChannel;
        for r = 1:numel(rows)
            fprintf(fid, '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n', ...
                csvField(entry.subject), csvField(entry.group), csvField(entry.session), ...
                csvField(rows(r).window), csvField(rows(r).bin), csvField(rows(r).channel), ...
                csvField(rows(r).measure), csvField(rows(r).method), ...
                num(rows(r).sme_uv), num(rows(r).score));
        end
    end
end

% ----------------------------------------------------------------------- %
function s = num(v)
%NUM  A numeric CSV field, written as an empty field (not the literal text
%   "NaN") when there is no value -- readr's own default na = c("", "NA")
%   then reads it back as a real NA rather than coercing the whole column
%   to character.
    if isempty(v) || ~isfinite(v)
        s = '';
    else
        s = sprintf('%.6g', v);
    end
end

function fid = openOrThrow(file)
    fid = fopen(file, 'w');
    if fid < 0
        throw(MException('Alakazam:exportDataQualityCSVs', ...
            'I''m afraid I could not open "%s" for writing.', file));
    end
end
