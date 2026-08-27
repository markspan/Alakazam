function q = dataQualityMetrics(epoched, averaged, windows, rejectionRan)
%DATAQUALITYMETRICS  Per-subject ERP data-quality metrics, adapted from the
%   pupillometry data-quality assessment of Mathot & Vilotijevic (2023,
%   Behav Res Methods, "Methods in cognitive pupillometry"). Their section
%   is built around four questions, each of which has a direct ERP
%   counterpart:
%
%     Pupillometry (Mathot & Vilotijevic)   ERP counterpart computed here
%     -----------------------------------   -----------------------------
%     % missing samples / blinks per trial   % trials rejected (all-NaN),
%                                            % channel-epochs flagged
%     blinks per trial BY CONDITION and by   rejection rate per BIN per
%     participant (their Fig. 9)             subject -- see below
%     histogram of baseline pupil size;      histogram of per-trial
%     z-score it, flag |z| > 2               pre-stimulus noise; same rule
%     gaze deviation over time               per-channel baseline SD
%
%   The condition-wise one is the point of the whole exercise, and the
%   reason this is worth a report rather than a single number: a rejection
%   rate that DIFFERS between bins biases the ERP contrast itself, exactly
%   as a condition-dependent blink rate biases a pupil contrast. A high
%   but even rejection rate costs power; an uneven one costs validity.
%
%   Two deliberate departures from the pupillometry original:
%
%   1. Their baseline metric is baseline pupil SIZE. The literal ERP
%      translation (mean pre-stimulus amplitude) is useless here, because
%      Alakazam's own Baseline transformation sets it to exactly zero by
%      construction. The pre-stimulus SD is used instead: it survives
%      baseline correction, and it is what ERP practice already treats as
%      the per-trial noise estimate.
%   2. SME (standardized measurement error, Luck et al. 2021) is reported
%      alongside. It has no pupillometry analogue but is the field's own
%      headline single-subject quality statistic, so leaving it out of an
%      ERP quality report would be perverse. It appears at two grains:
%      AVERAGED.aSME, the whole-epoch figure Average.m already computes,
%      and, when WINDOWS is supplied, the SME of each Measure window's own
%      score (see erpScoreSME). The second is the one Luck et al. actually
%      argue for, since SME is only interpretable as the error on the score
%      you report: a whole-epoch summary averages together a time range the
%      subject was clean in and one they were not.
%
%   Nothing here excludes anything. Mathot & Vilotijevic's own advice is
%   that exclusion criteria be specified in advance and reported
%   transparently; this reports, and leaves the decision with the analyst.
%
%   A NOTE ON WHAT "REJECTED" MEANS HERE. A trial counts as rejected when
%   every one of its channels is entirely NaN, which is what ArtefactDetect
%   and ManualReject both write. It is NOT, however, the only way to get
%   one: DefineBins/cutEpochs allocates the whole epoch stack as NaN and
%   fills only the part of each epoch that overlaps the recording, so an
%   anchor event past the end of the file (or one with no usable latency)
%   leaves a trial nobody rejected but which is empty all the same. The two
%   are indistinguishable from the data, so REJECTIONRAN says whether any
%   artefact step is actually in this dataset's processing chain, and the
%   report words the count accordingly rather than asserting a cause it
%   cannot check. An epoch that merely OVERLAPS the recording edge is a
%   different case and is counted separately, as truncated (see below).
%
%   AND WHAT "INTERPOLATED" MEANS. The NaN convention above can only ever
%   describe data that was REMOVED. ArtefactDetect and ManualReject can both
%   instead RECONSTRUCT a flagged channel-epoch from its neighbours, which
%   leaves real numbers in the cell -- invisible to every count here, and
%   indistinguishable from a channel that was never flagged at all. Those two
%   therefore record EEG.etc.alz.interpolated (logical nChan x nTrials), the
%   only trace reconstruction leaves, and it is reported separately: a
%   reconstructed cell is neither rejected nor clean, and rolling it into
%   either would misstate the recording. See
%   TransTools.InterpolateFlaggedCells.
%
%   EPOCHED is the segmented dataset (channels x samples x trials, with
%   rejected data already set to NaN by ArtefactDetect/ManualReject).
%   AVERAGED is its Average result, or [] when there is none (only the
%   whole-epoch SME column depends on it). WINDOWS is a cell array of
%   Measure window structs (a downstream Measure node's own
%   EEG.measurements), or {} when the subject has no Measure result yet.
%   REJECTIONRAN is true/false when the caller knows whether an
%   ArtefactDetect or ManualReject step is in this dataset's chain (see
%   Alakazam.collectDataQualityEntries, which reads it off the tree), or []
%   when it does not.
%
%   Returns a struct of four long-format tables, one row per unit of
%   analysis, ready for exportDataQualityCSVs:
%     q.subject         scalar struct: n_trials/n_rejected/pct_rejected/...
%     q.byBinChannel    struct array, one row per (bin, channel)
%     q.byTrial         struct array, one row per (trial, bin) membership
%     q.byWindowChannel struct array, one row per (window, bin, channel);
%                       empty when WINDOWS is empty
%
%   See also ERPSCORESME, EXPORTDATAQUALITYCSVS, GENERATEDATAQUALITYREPORT,
%   AVERAGE, MEASURE.
    if ~isfield(epoched, 'data') || isempty(epoched.data) || ndims(epoched.data) < 3
        throw(MException('Alakazam:dataQualityMetrics', ...
            ['I''m afraid data-quality metrics need segmented (epoched) data with more than one ' ...
             'trial, so there is a trial-to-trial distribution to describe.']));
    end
    if nargin < 2
        averaged = [];
    end
    if nargin < 3 || isempty(windows)
        windows = {};
    end
    if nargin < 4 || isempty(rejectionRan)
        rejectionRan = NaN;   % unknown: caller did not say
    else
        rejectionRan = double(logical(rejectionRan));
    end

    [nChan, ~, nTrials] = size(epoched.data);
    labels = channelLabels(epoched, nChan);
    baseIdx = baselineSamples(epoched);

    % Rejection state, straight off the NaN convention ArtefactDetect and
    % ManualReject both write (see their own Scope options): a whole-epoch
    % rejection NaNs every channel, a channel-scoped one NaNs just that
    % channel's row -- so the two are told apart by how many channels of a
    % trial are gone, not by a separate flag either of them records.
    chanGone = false(nChan, nTrials);
    for t = 1:nTrials
        for c = 1:nChan
            chanGone(c, t) = all(isnan(epoched.data(c, :, t)));
        end
    end
    trialRejected = all(chanGone, 1);
    chanFlagged = chanGone & ~repmat(trialRejected, nChan, 1);

    % INTERPOLATED cells cannot be read off the NaN convention at all: the
    % whole point of interpolation is that the cell holds real numbers again,
    % so a reconstructed channel-epoch is indistinguishable from one that was
    % never flagged. Counting it as clean would let a recording that had been
    % half rebuilt from its own neighbours report a spotless rejection rate.
    % The transformations that reconstruct data therefore leave a mask behind
    % (see TransTools.InterpolateFlaggedCells), and it is the only way to know.
    % Absent mask = nothing was interpolated, which is also the right answer
    % for every dataset produced before the mask existed.
    chanInterpolated = interpolatedMask(epoched, nChan, nTrials);

    % TRUNCATED trials: samples that are NaN across EVERY channel at once,
    % in a trial that still has usable data elsewhere. Neither detector
    % writes that pattern (ArtefactDetect and ManualReject NaN whole
    % channels or whole trials, never a sample range across all of them),
    % so it can only come from DefineBins/cutEpochs, which allocates the
    % epoch stack as NaN and fills only the part of each epoch that
    % overlaps the recording. An event too close to the start or end of the
    % file therefore yields a partly-empty epoch.
    %
    % Worth counting separately because it is otherwise invisible AND still
    % contributes: a truncated trial goes into the average through
    % Average's own omitnan, so its shortened span silently carries less
    % weight at the ends than the trials around it. If truncation clusters
    % in one condition (a block that ran up to the end of the recording),
    % it biases that condition's average exactly the way uneven rejection
    % would.
    sampleGone = squeeze(all(isnan(epoched.data), 1));   % samples x trials
    if nTrials == 1
        sampleGone = sampleGone(:);
    end
    trialTruncated = any(sampleGone, 1) & ~trialRejected;
    truncatedSamples = sum(sampleGone, 1);

    % Per-trial pre-stimulus noise: the SD over the baseline window, meaned
    % across channels. Channels flagged in THIS trial are NaN and drop out
    % via omitnan rather than poisoning the whole trial's value.
    baselineSd = nan(1, nTrials);
    baselineSdChan = nan(nChan, nTrials);
    for t = 1:nTrials
        if trialRejected(t)
            continue;
        end
        for c = 1:nChan
            baselineSdChan(c, t) = std(epoched.data(c, baseIdx, t), 0, 'omitnan');
        end
        baselineSd(t) = mean(baselineSdChan(:, t), 'omitnan');
    end

    % z over the KEPT trials only: including rejected (NaN) trials would
    % not change the mean/SD, but scoring a trial that is already gone as
    % an "outlier" would double-count it in every summary below.
    baselineZ = zScore(baselineSd);
    isOutlier = abs(baselineZ) > 2 & ~trialRejected;

    bins = binMemberships(epoched, nTrials);

    q.subject = struct( ...
        'n_channels', nChan, ...
        'n_trials', nTrials, ...
        'n_trials_rejected', sum(trialRejected), ...
        'pct_trials_rejected', pct(sum(trialRejected), nTrials), ...
        'n_channel_epochs_flagged', sum(chanFlagged(:)), ...
        'pct_channel_epochs_flagged', pct(sum(chanFlagged(:)), nChan * nTrials), ...
        'n_channel_epochs_interpolated', sum(chanInterpolated(:)), ...
        'pct_channel_epochs_interpolated', pct(sum(chanInterpolated(:)), nChan * nTrials), ...
        'n_trials_truncated', sum(trialTruncated), ...
        'pct_trials_truncated', pct(sum(trialTruncated), nTrials), ...
        'max_truncated_pct_of_epoch', maxTruncation(truncatedSamples, trialTruncated, size(epoched.data, 2)), ...
        'rejection_ran', rejectionRan, ...
        'n_baseline_outlier_trials', sum(isOutlier), ...
        'pct_baseline_outlier_trials', pct(sum(isOutlier), nTrials), ...
        'median_baseline_sd_uv', median(baselineSd, 'omitnan'), ...
        'n_bins', numel(bins));

    q.byBinChannel = struct('bin', {}, 'channel', {}, 'n_trials', {}, 'n_trials_rejected', {}, ...
        'pct_trials_rejected', {}, 'n_flagged', {}, 'pct_flagged', {}, ...
        'n_interpolated', {}, 'pct_interpolated', {}, 'baseline_sd_uv', {}, 'sme_uv', {});
    for b = 1:numel(bins)
        member = bins(b).trials;
        for c = 1:nChan
            inBinRejected = trialRejected(member);
            q.byBinChannel(end + 1) = struct( ... %#ok<AGROW>
                'bin', bins(b).label, ...
                'channel', labels{c}, ...
                'n_trials', numel(member), ...
                'n_trials_rejected', sum(inBinRejected), ...
                'pct_trials_rejected', pct(sum(inBinRejected), numel(member)), ...
                'n_flagged', sum(chanFlagged(c, member)), ...
                'pct_flagged', pct(sum(chanFlagged(c, member)), numel(member)), ...
                'n_interpolated', sum(chanInterpolated(c, member)), ...
                'pct_interpolated', pct(sum(chanInterpolated(c, member)), numel(member)), ...
                'baseline_sd_uv', median(baselineSdChan(c, member), 'omitnan'), ...
                'sme_uv', smeFor(averaged, c, bins(b).index));
        end
    end

    q.byWindowChannel = windowSME(epoched, windows, bins, labels, nChan);

    q.byTrial = struct('bin', {}, 'trial', {}, 'baseline_sd_uv', {}, 'baseline_z', {}, ...
        'rejected', {}, 'baseline_outlier', {});
    for b = 1:numel(bins)
        for t = bins(b).trials
            q.byTrial(end + 1) = struct( ... %#ok<AGROW>
                'bin', bins(b).label, ...
                'trial', t, ...
                'baseline_sd_uv', baselineSd(t), ...
                'baseline_z', baselineZ(t), ...
                'rejected', double(trialRejected(t)), ...
                'baseline_outlier', double(isOutlier(t)));
        end
    end
end

% ======================================================================= %
function rows = windowSME(EEG, windows, bins, labels, nChan)
%WINDOWSME  One row per (Measure window, bin, channel): the SME of that
%   window's own score, computed from the single trials belonging to that
%   bin (see erpScoreSME for the analytic-vs-bootstrap choice).
%
%   A "Peak" window yields TWO scores, amplitude and latency, and so two
%   rows: Measure reports both from one window, but their SMEs are
%   different numbers in different units and cannot share a row.
%
%   A window whose peak is found in a REFERENCE channel is skipped rather
%   than approximated: the score then depends on another channel and is not
%   a per-channel function of the waveform erpScoreSME sees, so scoring it
%   per-channel anyway would report an SME for a measurement nobody made.
%
%   A window restricted to a subset of CHANNELS emits rows for exactly
%   those channels, for the same reason in miniature: the others were never
%   measured, so an SME for them describes nothing.
    rows = struct('window', {}, 'bin', {}, 'channel', {}, 'measure', {}, ...
        'method', {}, 'sme_uv', {}, 'score', {});
    if isempty(windows) || ~isfield(EEG, 'times') || isempty(EEG.times)
        return;
    end
    times = EEG.times;

    for w = 1:numel(windows)
        win = windows{w};
        if ~isempty(fieldOrEmpty(win, 'refChannel'))
            continue;
        end
        winLabel = char(string(fieldOrEmpty(win, 'label')));
        measured = measuredChannels(win, labels);
        for scored = scoreVariants(win)
            variant = scored{1};
            for b = 1:numel(bins)
                member = bins(b).trials;
                if isempty(member)
                    continue;
                end
                [sme, method, score] = erpScoreSME(EEG.data(:, :, member), times, variant);
                for c = 1:nChan
                    if isnan(sme(c)) || ~measured(c)
                        continue;
                    end
                    rows(end + 1) = struct( ... %#ok<AGROW>
                        'window', winLabel, 'bin', bins(b).label, 'channel', labels{c}, ...
                        'measure', char(string(variant.measure)), 'method', char(method), ...
                        'sme_uv', sme(c), 'score', score(c));
                end
            end
        end
    end
end

function mask = measuredChannels(win, labels)
%MEASUREDCHANNELS  Logical mask over LABELS of the channels this window was
%   actually measured on. A computed measurement carries .channels as the
%   resolved list Measure produced (see computeWindow's {specs.label}); a
%   window with none, or with an unrecognisable one, is treated as
%   all-channels, which is what Measure itself does with a blank selection.
    mask = true(1, numel(labels));
    if ~isstruct(win) || ~isfield(win, 'channels') || isempty(win.channels)
        return;
    end
    wanted = win.channels;
    if ischar(wanted) || isstring(wanted)
        wanted = cellstr(string(wanted));
    end
    if ~iscell(wanted)
        return;
    end
    wanted = cellfun(@(x) char(string(x)), wanted, 'UniformOutput', false);
    candidate = ismember(labels, wanted);
    if any(candidate)
        mask = candidate;
    end
end

function variants = scoreVariants(win)
%SCOREVARIANTS  The window structs to score, one per number the window
%   actually produces: a "Peak" window produces an amplitude AND a latency
%   (mirroring measureRowTypes' own peak -> {peak_amplitude, peak_latency}
%   split), everything else produces one.
    variants = {win};
    if strcmpi(strtrim(char(string(fieldOrEmpty(win, 'measure')))), 'peak')
        latencyWin = win;
        latencyWin.measure = 'Peak Latency';
        variants = {win, latencyWin};
    end
end

function v = fieldOrEmpty(s, name)
    if isstruct(s) && isfield(s, name)
        v = s.(name);
    else
        v = '';
    end
end

% ======================================================================= %
function idx = baselineSamples(EEG)
%BASELINESAMPLES  The pre-stimulus sample indices (times < 0). Falls back
%   to the first fifth of the epoch when the dataset carries no usable time
%   axis, or when the epoch starts at/after zero so there is no pre-stimulus
%   period to measure at all -- a noise estimate from the front of the
%   epoch is still far better than none, and is flagged as such nowhere
%   else, so it deliberately never silently claims to be pre-stimulus.
    nSamp = size(EEG.data, 2);
    if isfield(EEG, 'times') && numel(EEG.times) == nSamp
        idx = find(EEG.times < 0);
        if numel(idx) >= 2
            return;
        end
    end
    idx = 1:max(2, round(nSamp / 5));
end

function bins = binMemberships(EEG, nTrials)
%BINMEMBERSHIPS  One entry per ordinary (non-combination) bin, .label /
%   .index / .trials. Combination bins are skipped: they have no trials of
%   their own (Average.m computes them from the other bins' averages), so
%   a rejection rate for one would be meaningless. A dataset with no bins
%   at all reports a single implicit "all" bin over every trial.
    bins = struct('label', {}, 'index', {}, 'trials', {});
    if ~isfield(EEG, 'bindesc') || isempty(EEG.bindesc)
        bins(1) = struct('label', 'all', 'index', NaN, 'trials', 1:nTrials);
        return;
    end
    for b = 1:numel(EEG.bindesc)
        if isfield(EEG.bindesc, 'combo') && ~isempty(EEG.bindesc(b).combo)
            continue;
        end
        bins(end + 1) = struct('label', char(string(EEG.bindesc(b).label)), ... %#ok<AGROW>
            'index', b, 'trials', binTrialIndices(EEG, b, nTrials)); %#ok<AGROW>
    end
    if isempty(bins)
        bins(1) = struct('label', 'all', 'index', NaN, 'trials', 1:nTrials);
    end
end

function idx = binTrialIndices(EEG, b, nTrials)
%BINTRIALINDICES  Trial indices belonging to bin B -- the explicit list
%   DefineBins stores, else the per-epoch .bini membership tags. Mirrors
%   Average.binTrials, which resolves the same two sources the same way.
    idx = [];
    if isfield(EEG.bindesc, 'trials') && ~isempty(EEG.bindesc(b).trials)
        idx = EEG.bindesc(b).trials(:).';
    elseif isfield(EEG, 'epoch') && ~isempty(EEG.epoch) && isfield(EEG.epoch, 'bini')
        binIndex = EEG.bindesc(b).index;
        idx = find(arrayfun(@(e) any(e.bini == binIndex), EEG.epoch));
    end
    idx = idx(idx >= 1 & idx <= nTrials);
end

function v = smeFor(averaged, c, binIndex)
%SMEFOR  Average.m's own analytic SME for channel C in bin BINDEX, or NaN
%   when there is no Average result to read it from. Average stores aSME as
%   channels x bins for a binned dataset and channels x 1 for an unbinned
%   one, so an unbinned dataset (binIndex NaN) reads the single column.
    v = NaN;
    if isempty(averaged) || ~isfield(averaged, 'aSME') || isempty(averaged.aSME)
        return;
    end
    aSME = averaged.aSME;
    if c > size(aSME, 1)
        return;
    end
    if isnan(binIndex)
        v = aSME(c, 1);
    elseif binIndex <= size(aSME, 2)
        v = aSME(c, binIndex);
    end
end

function labels = channelLabels(EEG, nChan)
    labels = arrayfun(@(c) sprintf('Ch%d', c), 1:nChan, 'UniformOutput', false);
    if isfield(EEG, 'chanlocs') && numel(EEG.chanlocs) >= nChan
        for c = 1:nChan
            name = strtrim(char(string(EEG.chanlocs(c).labels)));
            if ~isempty(name)
                labels{c} = name;
            end
        end
    end
end

function mask = interpolatedMask(EEG, nChan, nTrials)
%INTERPOLATEDMASK  The nChan x nTrials logical written by whichever
%   transformation reconstructed data, or all-false when there is none.
%
%   Read defensively and deliberately NOT through TransTools: EEG.etc is
%   EEGLAB's free-form field and may be absent, empty or not a struct, and
%   this file is IO code that must stay usable without the Transformations
%   package on the path. The field name is the contract with
%   TransTools.InterpolateFlaggedCells; if it changes, it changes in both.
%
%   A mask of the wrong shape is discarded rather than misapplied: it was
%   written for a differently shaped dataset (a resample, a channel edit)
%   and there is no honest way to map it onto this one.
    mask = false(nChan, nTrials);
    if ~isfield(EEG, 'etc') || ~isstruct(EEG.etc) || isempty(EEG.etc)
        return;
    end
    if ~isfield(EEG.etc, 'alz') || ~isstruct(EEG.etc.alz) || isempty(EEG.etc.alz)
        return;
    end
    if ~isfield(EEG.etc.alz, 'interpolated')
        return;
    end
    stored = EEG.etc.alz.interpolated;
    if islogical(stored) && isequal(size(stored), [nChan, nTrials])
        mask = stored;
    end
end

function z = zScore(x)
    z = nan(size(x));
    mu = mean(x, 'omitnan');
    sd = std(x, 0, 'omitnan');
    if isnan(sd) || sd == 0
        z(~isnan(x)) = 0;
        return;
    end
    z = (x - mu) / sd;
end

function p = maxTruncation(truncatedSamples, trialTruncated, nSamples)
%MAXTRUNCATION  How much of an epoch was missing in the worst truncated
%   trial, as a percentage. One number is enough to tell a rounding-error
%   truncation (a sample or two off the end, harmless) from a trial that
%   lost half its window and should probably not be in the average at all.
    if ~any(trialTruncated) || nSamples == 0
        p = 0;
        return;
    end
    p = 100 * max(truncatedSamples(trialTruncated)) / nSamples;
end

function p = pct(numerator, denominator)
    if denominator == 0
        p = NaN;
    else
        p = 100 * numerator / denominator;
    end
end
