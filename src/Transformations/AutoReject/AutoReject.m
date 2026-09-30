function [EEG, options] = AutoReject(input, varargin)
%% AutoReject  Rejection thresholds learnt from the data, per channel, with
%   bad channels interpolated where an epoch can be saved.
%
%   An implementation of the local autoreject algorithm (Jas, Engemann,
%   Bekhti, Raimondo & Gramfort, 2017, NeuroImage 159:417), which replaces a
%   fixed threshold chosen by eye (+/-100 uV) with thresholds chosen by
%   cross-validation:
%     1. for every scalp channel, the peak-to-peak threshold whose kept
%        epochs average closest to the robust (median) average of held-out
%        epochs (autorejectThresholds);
%     2. a channel-epoch is bad when its peak-to-peak amplitude exceeds its
%        channel's threshold;
%     3. an epoch with at least kappa x nChannels bad channels is rejected;
%        in the others, up to rho of the bad channels (the worst) are
%        interpolated from the rest of the epoch; kappa and rho are chosen
%        by the same cross-validation (autorejectConsensus).
%   The folds are autoreject's (ten contiguous blocks, no shuffling), so the
%   result is deterministic and a replay reproduces it.
%
%   WHERE IT DIFFERS FROM THE PYTHON PACKAGE, deliberately: each channel's
%   threshold is the exact minimum of the cross-validation error over every
%   candidate, where autoreject samples 50 candidates by Bayesian
%   optimisation; and the candidates for rho are each scored from the
%   thresholded labels, where autoreject's cross-validation lets one
%   candidate's interpolation labels carry into the next. Both are the
%   algorithm as the paper states it.
%
%   WHICH CHANNELS AND EPOCHS. The scalp EEG channels with a 10-5 position
%   (TransTools.ScalpChannels) are thresholded and interpolated, each from
%   the others; peripherals are not tested, as autoreject tests only the
%   EEG. Epochs already rejected (any NaN on those channels) are left as
%   they are and are not counted. Rejected epochs are NaN on every channel,
%   Alakazam's convention; interpolated channel-epochs are recorded in
%   EEG.etc.alz.interpolated, as ArtefactDetect's are.
%
%   WHAT IT RECORDS, in EEG.etc.alz.autoreject: the thresholds per channel,
%   the chosen kappa and rho and the loss grid they were chosen from, and
%   which epochs were examined, rejected and repaired.
%
%   Signature (Alakazam transformation contract):
%     [EEG, options] = AutoReject(input)        % interactive dialog
%     [EEG, options] = AutoReject(input, opts)  % replay a stored options struct
%
%   See also ARTEFACTDETECT, AUTOREJECTTHRESHOLDS, AUTOREJECTCONSENSUS,
%   TRANSTOOLS.INTERPOLATEFLAGGEDCELLS.
[opts, interactive] = TransTools.InitGuard(nargin, 'Alakazam:AutoReject', varargin{:});

if ndims(input.data) < 3 || ~strcmpi(TransTools.FieldOr(input, 'DataFormat', 'EPOCHED'), 'EPOCHED')
    throw(MException('Alakazam:AutoReject', ['I''m afraid AutoReject learns its thresholds ' ...
        'from epochs, and this dataset is not epoched. Would you run DefineBins first?']));
end

if interactive
    stored = TransformSettings.get('AutoReject');
    if isempty(stored) || ~isstruct(stored)
        stored = struct();
    end
    d = @(f, v) TransTools.FieldOr(stored, f, v);
    options = TransformOptionsDialog( ...
        'title', 'AutoReject options', ...
        'Description', ['Learns a peak-to-peak rejection threshold per channel by ' ...
            'cross-validation, then rejects the epochs with too many bad channels and ' ...
            'interpolates the bad channels of the rest (Jas et al., 2017). Blank ' ...
            '"interpolate at most" uses autoreject''s own candidates.'], ...
        'separator', 'Cross-validation:', ...
        {'Folds'; 'Folds'}, d('Folds', 10), ...
        {'Interpolate at most (candidates)'; 'Interpolate'}, d('Interpolate', ''));
    if isempty(options)
        EEG = [];   % cancelled: no node, no compute
        return;
    end
    TransformSettings.set('AutoReject', options);
else
    options = opts;
end

[EEG, fitIdx] = TransTools.ScalpChannels(input, 'Alakazam:AutoReject');
nFit = numel(fitIdx);
if nFit < 4
    throw(MException('Alakazam:AutoReject', ['I''m afraid AutoReject needs at least four ' ...
        'scalp channels with a position to interpolate from, and this dataset has %d.'], nFit));
end
[~, nSamples, nTrials] = size(EEG.data);
examined = reshape(~any(isnan(EEG.data(fitIdx, :, :)), [1 2]), 1, []);
epochIdx = find(examined);

folds = autorejectFolds(numel(epochIdx), round(TransTools.FieldOr(options, 'Folds', 10)));
kappaGrid = linspace(0, 1, 11);
rhoGrid = interpolationCandidates(TransTools.FieldOr(options, 'Interpolate', ''), nFit);

% The scalp channels of the epochs examined, as a dataset of their own, so
% that interpolation reconstructs each channel from the other scalp channels
% only (an EOG channel is no neighbour of Fp1).
scalp = subDataset(EEG, fitIdx, epochIdx);
X = double(scalp.data);
ptp = reshape(max(X, [], 2) - min(X, [], 2), nFit, []);

thresholds = autorejectThresholds(X, folds);
bad = ptp > thresholds(:);
interpolate = @(plan) interpolatedData(scalp, plan);
[kappa, rho, loss] = autorejectConsensus(X, bad, ptp, folds, kappaGrid, rhoGrid, interpolate);

% The repair, with the chosen pair: no interpolation in an epoch that is
% rejected anyway, so the record does not claim repairs that were discarded.
rejected = sum(bad, 1) >= kappa * nFit;
plan = autorejectRepairPlan(ptp, bad, rho);
plan(:, rejected) = false;
EEG.data(fitIdx, :, epochIdx) = interpolatedData(scalp, plan);
EEG.data(:, :, epochIdx(rejected)) = NaN;

interpolatedCells = false(size(EEG.data, 1), nTrials);
interpolatedCells(fitIdx, epochIdx) = plan;
EEG = TransTools.RecordInterpolated(EEG, interpolatedCells);

badCells = false(nFit, nTrials);
badCells(:, epochIdx) = bad;
rejectedEpochs = false(1, nTrials);
rejectedEpochs(epochIdx(rejected)) = true;
EEG.etc.alz.autoreject = struct( ...
    'method',          'local autoreject (Jas et al., 2017), exact threshold search', ...
    'channels',        {{EEG.chanlocs(fitIdx).labels}}, ...
    'thresholds',      thresholds, ...
    'consensus',       kappa, ...
    'nInterpolate',    rho, ...
    'consensusGrid',   kappaGrid, ...
    'interpolateGrid', rhoGrid, ...
    'loss',            loss, ...
    'nFolds',          numel(folds), ...
    'examined',        examined, ...
    'badCells',        badCells, ...
    'rejected',        rejectedEpochs, ...
    'nInterpolated',   nnz(plan), ...
    'nSamples',        nSamples, ...
    'options',         options);

fprintf(['AutoReject: thresholds %.0f to %.0f uV (median %.0f) over %d channel(s); an epoch ' ...
    'is rejected with %d or more bad channels, and up to %d are interpolated. Rejected %d of ' ...
    '%d epoch(s), interpolated %d channel-epoch(s)%s.\n'], min(thresholds), max(thresholds), ...
    median(thresholds), nFit, ceil(kappa * nFit), rho, nnz(rejected), numel(epochIdx), ...
    nnz(plan), notExamined(nTrials - numel(epochIdx)));
end

% ======================================================================= %
function rho = interpolationCandidates(setting, nFit)
%INTERPOLATIONCANDIDATES  The candidates for rho: those typed in, or
%   autoreject's own, 1, 4 and min(nChan - 1, 32). Always whole numbers from
%   1 to nChan - 1 (interpolating every channel would leave nothing to
%   interpolate from).
    if isnumeric(setting) && ~isempty(setting)
        rho = double(setting(:)).';
    else
        rho = sscanf(char(string(setting)), '%f').';
    end
    if isempty(rho)
        rho = [1, 4, min(nFit - 1, 32)];
    end
    rho = unique(min(max(round(rho), 1), nFit - 1));
end

function sub = subDataset(EEG, channels, epochs)
%SUBDATASET  A plain dataset holding CHANNELS of EPOCHS, for interpolation.
%   Built by hand rather than by pop_select, which would re-derive events
%   and epochs that interpolation never reads. The ICA fields go: eeg_interp
%   would otherwise try to keep a decomposition of channels no longer there.
    sub = EEG;
    sub.data     = EEG.data(channels, :, epochs);
    sub.chanlocs = EEG.chanlocs(channels);
    sub.nbchan   = numel(channels);
    sub.trials   = numel(epochs);
    sub.event    = [];
    sub.epoch    = [];
    for f = {'icaweights', 'icasphere', 'icawinv', 'icaact', 'icachansind'}
        if isfield(sub, f{1})
            sub.(f{1}) = [];
        end
    end
end

function data = interpolatedData(scalp, plan)
%INTERPOLATEDDATA  SCALP's data with the channel-epochs in PLAN rebuilt from
%   the other channels of their epoch (spherical splines, as ArtefactDetect's
%   and ManualReject's interpolation).
    repaired = TransTools.InterpolateFlaggedCells(scalp, plan);
    data = double(repaired.data);
end

function s = notExamined(n)
    if n == 0
        s = '';
    else
        s = sprintf('; %d epoch(s) already rejected were not examined', n);
    end
end
