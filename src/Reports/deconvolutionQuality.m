function q = deconvolutionQuality(averaged)
%DECONVOLUTIONQUALITY  Data-quality metrics for a deconvolved ERP, in
%   dataQualityMetrics' own shape, so the report reads it the same way.
%
%   Q = deconvolutionQuality(AVERAGED) describes a dataset Deconvolve
%   produced, using EEG.etc.alz.unfold and EEG.bindesc. The fields are
%   dataQualityMetrics' exactly, because the report and the CSV export
%   concatenate every subject's struct into one table and a differently
%   shaped one would not concatenate.
%
%   WHAT IS AND IS NOT REPORTED, and why the difference matters more here
%   than anywhere else in this report. Deconvolution has no trials. It fits
%   one waveform per bin against the whole continuous recording, so there is
%   no trial-to-trial distribution to describe: no rejection rate, no
%   per-trial baseline noise, no outlier trials, and no SME, which is the
%   spread of the trials that went into a mean. Those fields are NaN, which
%   the CSV writes as an empty field and the report reads as NA.
%
%   THEY ARE NOT ZERO. Zero would say "this subject lost no trials", which
%   is a claim about data quality; NaN says "this measure does not exist for
%   this dataset", which is the truth. A deconvolved subject printed with
%   0% rejection beside an averaged subject at 14% would read as the better
%   recording, when nothing was measured at all.
%
%   WHAT IT DOES HAVE is the count of events behind each bin (the closest
%   thing to trials per bin), and how much of the recording was left out of
%   the model as artefact or as a cut, which is the direct analogue of a
%   rejection rate: both say how much of the data did not contribute. Those
%   go where a reader of this report already looks for them, in
%   byBinChannel and in the provenance table.
%
%   See also DATAQUALITYMETRICS, COLLECTDATAQUALITYENTRIES, UNFOLD.FITBINS,
%   DECONVOLVE.
    info = unfoldInfo(averaged);
    labels = channelLabels(averaged);
    nChan = numel(labels);
    binLabels = cellstr(string({averaged.bindesc.label}));
    counts = binEventCounts(averaged, info, numel(binLabels));

    q.subject = struct( ...
        'n_channels', nChan, ...
        'n_trials', sum(counts, 'omitnan'), ...   % events modelled, not trials
        'n_trials_rejected', NaN, ...
        'pct_trials_rejected', NaN, ...
        'n_channel_epochs_flagged', NaN, ...
        'pct_channel_epochs_flagged', NaN, ...
        'n_channel_epochs_interpolated', NaN, ...
        'pct_channel_epochs_interpolated', NaN, ...
        'n_trials_truncated', NaN, ...
        'pct_trials_truncated', NaN, ...
        'max_truncated_pct_of_epoch', NaN, ...
        'rejection_ran', NaN, ...
        'n_baseline_outlier_trials', NaN, ...
        'pct_baseline_outlier_trials', NaN, ...
        'median_baseline_sd_uv', NaN, ...
        'n_bins', numel(binLabels));

    q.byBinChannel = struct('bin', {}, 'channel', {}, 'n_trials', {}, 'n_trials_rejected', {}, ...
        'pct_trials_rejected', {}, 'n_flagged', {}, 'pct_flagged', {}, ...
        'n_interpolated', {}, 'pct_interpolated', {}, 'baseline_sd_uv', {}, 'sme_uv', {});
    for b = 1:numel(binLabels)
        for c = 1:nChan
            q.byBinChannel(end + 1) = struct( ... %#ok<AGROW>
                'bin', binLabels{b}, ...
                'channel', labels{c}, ...
                'n_trials', counts(b), ...
                'n_trials_rejected', NaN, 'pct_trials_rejected', NaN, ...
                'n_flagged', NaN, 'pct_flagged', NaN, ...
                'n_interpolated', NaN, 'pct_interpolated', NaN, ...
                'baseline_sd_uv', NaN, 'sme_uv', NaN);
        end
    end

    % Windowed SME needs the trials a score varies over, so there is none.
    % Empty, but with windowSME's own columns in its own order: an empty
    % struct array still has to concatenate with the other subjects' rows.
    q.byWindowChannel = struct('window', {}, 'bin', {}, 'channel', {}, 'measure', {}, ...
        'method', {}, 'sme_uv', {}, 'score', {});
    q.byTrial = struct('bin', {}, 'trial', {}, 'baseline_sd_uv', {}, 'baseline_z', {}, ...
        'rejected', {}, 'baseline_outlier', {});
    template = blankRow(emptyProvenance(), '', '', NaN, NaN);
    q.provenance = deconvolutionRows(averaged, template, nChan);
    % A deconvolution often follows an eye-track join (fixation-related
    % potentials are what it is most used for), and that join's quality is
    % as much a fact about this subject's data as what the fit excluded.
    eye = eyeTrackingRow(averaged, template);
    if ~isempty(eye)
        q.provenance = [eye, q.provenance];
    end
end

% ======================================================================= %
function rows = emptyProvenance()
%EMPTYPROVENANCE  The provenance table's columns, as an empty struct array.
%   The rows themselves come from deconvolutionRows, which the epoched path
%   (overlap-corrected trials) shares.
    rows = struct('step', {}, 'item', {}, 'n', {}, 'n_total', {}, 'pct', {}, ...
        'n_unique', {}, 'channel_epochs', {}, 'channels_tested', {}, 'scope', {}, ...
        'threshold', {}, 'components', {}, 'n_samples_rejected', {}, 'n_samples', {}, ...
        'sensai', {}, 'enova_epoch_max', {}, 'enova_epoch_median', {}, ...
        'enova_channel_max', {}, 'n_excluded', {}, 'pct_within_one', {}, ...
        'mean_offset_ms', {}, 'detail', {});
end

function row = blankRow(template, step, item, n, nTotal)
%BLANKROW  One row of the provenance table with everything blank but the
%   five columns every step fills, matching blankProvenanceRow's own rule:
%   NaN for a number, '' for text, so both export as an empty CSV field.
    names = fieldnames(template);
    values = cell(size(names));
    for k = 1:numel(names)
        if any(strcmp(names{k}, {'step', 'item', 'scope', 'components', 'detail'}))
            values{k} = '';
        else
            values{k} = NaN;
        end
    end
    row = cell2struct(values, names, 1);
    row.step = step;
    row.item = item;
    row.n = n;
    row.n_total = nTotal;
    if isfinite(n) && isfinite(nTotal) && nTotal > 0
        row.pct = 100 * n / nTotal;
    end
end

function info = unfoldInfo(EEG)
    info = [];
    if isfield(EEG, 'etc') && isstruct(EEG.etc) && isfield(EEG.etc, 'alz') ...
            && isstruct(EEG.etc.alz) && isfield(EEG.etc.alz, 'unfold')
        info = EEG.etc.alz.unfold;
    end
end

function counts = binEventCounts(EEG, info, nBins)
%BINEVENTCOUNTS  Events behind each bin. bindesc.n is what fitBins wrote
%   there; the model's own counts are the fallback, and a combination bin
%   has no events of its own either way.
    counts = nan(1, nBins);
    for b = 1:nBins
        if isfield(EEG.bindesc, 'n') && ~isempty(EEG.bindesc(b).n)
            counts(b) = double(EEG.bindesc(b).n);
        end
    end
    if all(isnan(counts)) && ~isempty(info) && isfield(info, 'binCounts')
        n = min(nBins, numel(info.binCounts));
        counts(1:n) = double(info.binCounts(1:n));
    end
end

function labels = channelLabels(EEG)
    if isfield(EEG, 'chanlocs') && ~isempty(EEG.chanlocs)
        labels = cellstr(string({EEG.chanlocs.labels}));
    else
        labels = arrayfun(@(k) sprintf('ch%d', k), 1:size(EEG.data, 1), 'UniformOutput', false);
    end
end
