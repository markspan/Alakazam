function [EEG, options] = ASR(input, varargin)
%% ASR  Artifact Subspace Reconstruction: bad channels found and
%   interpolated, then high-amplitude bursts repaired (or rejected).
%
%   Runs the stages of EEGLAB's clean_rawdata plugin (Kothe; Mullen et al.,
%   2015, IEEE Trans Biomed Eng 62:2553) that clean, in the order
%   clean_artifacts runs them:
%     1. clean_flatlines  -- a channel flat for longer than FlatlineSeconds;
%     2. clean_channels   -- a channel whose signal its neighbours predict
%                            poorly (correlation below ChannelCorrelation
%                            for more than half the recording) or which
%                            carries far more line noise than the rest
%                            (LineNoiseSD, in robust SDs);
%     3. clean_asr        -- ASR proper: a clean stretch of the recording
%                            calibrates what the scalp's covariance should
%                            look like; wherever a sliding window's
%                            variance exceeds that by BurstCriterion
%                            standard deviations along some direction, the
%                            offending components are reconstructed from
%                            the clean ones;
%     4. clean_windows    -- optionally, windows that are still bad after
%                            the repair (more than WindowCriterion of the
%                            channels outside the power tolerance).
%   The channels removed in 1 and 2 are then interpolated back from their
%   neighbours (spherical splines), so the montage, and every template and
%   grand average that relies on it, is unchanged.
%
%   BURST CRITERION. clean_rawdata's own default is 5, which is aggressive;
%   its dialog proposes 20, and a systematic evaluation on real EEG found
%   the useful range to be 20 to 30 (Chang et al., 2020, IEEE Trans Biomed
%   Eng 67:1114). 20 is the default here.
%
%   REPAIR OR REJECT. By default the bursts are repaired, which is what ASR
%   is for. "Reject" marks every sample ASR had to change as rejected
%   instead, and so do the windows step 4 finds. Rejected samples are NaN on
%   every channel, not cut out, so the recording keeps its length and its
%   events their latencies (AutoGEDAI does the same). An epoch cut across a
%   rejected stretch keeps NaN there; Average leaves NaN out sample by
%   sample.
%
%   NOT HERE: THE HIGH-PASS FILTER. clean_artifacts high-passes the data
%   first (0.25 to 0.75 Hz), and ASR assumes data without slow drifts. That
%   filter is left to Filter, so that what the data went through is one
%   step per operation in the tree; a recording that still carries large
%   offsets is warned about.
%
%   WHICH CHANNELS. Scalp EEG with a 10-5 position (TransTools.ScalpChannels)
%   calibrate ASR and are cleaned. EOG, ECG, a photodiode and the like are
%   left exactly as they were, apart from sharing a rejected stretch.
%
%   WHAT IT RECORDS, in EEG.etc.alz.asr: the plugin version, the channels
%   interpolated, the samples repaired and rejected, and the options.
%
%   clean_rawdata ships with EEGLAB; Alakazam installs it through EEGLAB's
%   plugin manager at startup when it is missing.
%
%   Signature (Alakazam transformation contract):
%     [EEG, options] = ASR(input)        % interactive dialog
%     [EEG, options] = ASR(input, opts)  % replay a stored options struct
%
%   See also PREP, AUTOREJECT, ASRREJECTEDSAMPLES, TRANSTOOLS.SCALPCHANNELS.
[opts, interactive] = TransTools.InitGuard(nargin, 'Alakazam:ASR', varargin{:});

requireContinuous(input);
ensureCleanRawdata();

if interactive
    stored = TransformSettings.get('ASR');
    if isempty(stored) || ~isstruct(stored)
        stored = struct();
    end
    d = @(f, v) TransTools.FieldOr(stored, f, v);
    options = TransformOptionsDialog( ...
        'title', 'ASR options', ...
        'Description', ['Artifact Subspace Reconstruction (clean_rawdata). Bad scalp channels ' ...
            'are found and interpolated, then high-amplitude bursts are repaired. High-pass ' ...
            'the recording first (Filter); a criterion of 0 switches that check off.'], ...
        'separator', 'Bad channels (interpolated afterwards):', ...
        {'Flat for longer than (s)'; 'FlatlineSeconds'}, d('FlatlineSeconds', 5), ...
        {'Correlation below'; 'ChannelCorrelation'}, d('ChannelCorrelation', 0.8), ...
        {'Line noise above (SD)'; 'LineNoiseSD'}, d('LineNoiseSD', 4), ...
        'separator', 'Bursts:', ...
        {'Burst criterion (SD)'; 'BurstCriterion'}, d('BurstCriterion', 20), ...
        {'Bursts are'; 'BurstHandling'}, TransTools.PutFirst({'Repaired', 'Rejected'}, d('BurstHandling', 'Repaired')), ...
        'separator', 'What the repair could not fix:', ...
        {'Reject bad windows'; 'RejectWindows'}, d('RejectWindows', false), ...
        {'Bad above (fraction of channels)'; 'WindowCriterion'}, d('WindowCriterion', 0.25));
    if isempty(options)
        EEG = [];   % cancelled: no node, no compute
        return;
    end
    TransformSettings.set('ASR', options);
else
    options = opts;
end
opt = normaliseOptions(options);

[EEG, scalpIdx] = TransTools.ScalpChannels(input, 'Alakazam:ASR');
if any(isnan(EEG.data(scalpIdx, :)), 'all')
    % ASR's covariance and its sliding windows have no notion of a missing
    % sample: one NaN spreads through a window's reconstruction to every
    % channel. Rejection belongs after ASR, not before it.
    throw(MException('Alakazam:ASR', ['I''m afraid this recording already has rejected ' ...
        '(NaN) stretches, which ASR cannot calibrate or repair around. Would you run ASR ' ...
        'on the recording before the step that rejected them?']));
end
warnIfUnfiltered(EEG, scalpIdx);
scalp = pop_select(EEG, 'channel', scalpIdx);
scalpLabels = {scalp.chanlocs.labels};

% clean_artifacts rounds the rate for these stages and restores it after;
% the channel and ASR windows are counted in samples of a whole-number rate.
srate = scalp.srate;
scalp.srate = round(srate);

% 1-2. Bad channels.
kept = scalp;
if opt.FlatlineSeconds > 0
    kept = clean_flatlines(kept, opt.FlatlineSeconds);
end
if opt.ChannelCorrelation > 0 || opt.LineNoiseSD > 0
    % The same stand-ins clean_artifacts uses for a criterion that is 'off':
    % a correlation of 0 never flags, and 100 SD of line noise never does.
    corrCrit = max(opt.ChannelCorrelation, 0);
    lineCrit = opt.LineNoiseSD;
    if lineCrit <= 0
        lineCrit = 100;
    end
    % clean_channels calls rng('default') itself, which would reset the
    % caller's random stream; it is restored afterwards.
    kept = TransTools.WithRestoredRng(@() clean_channels(kept, corrCrit, lineCrit, [], 0.5, 50));
end
keptLabels = {kept.chanlocs.labels};
interpolated = scalpLabels(~ismember(scalpLabels, keptLabels));

% 3. ASR, with clean_artifacts' own calibration settings.
try
    repaired = clean_asr(kept, opt.BurstCriterion, [], [], [], 0.075, [-inf 5.5], [], [], false, 64);
catch err
    throw(MException('Alakazam:ASR', ['I''m afraid ASR could not be calibrated on this ' ...
        'recording: %s. ASR needs a stretch of reasonably clean data, about a minute, to learn ' ...
        'what the scalp should look like.'], err.message));
end
changed = sum(abs(double(kept.data) - double(repaired.data)), 1) >= 1e-8;

% 4. What the repair could not fix.
rejected = false(1, size(kept.data, 2));
if strcmpi(opt.BurstHandling, 'Rejected')
    rejected = asrRejectedSamples(changed);
end
if opt.RejectWindows
    probe = repaired;
    if isfield(probe, 'etc') && isstruct(probe.etc) && isfield(probe.etc, 'clean_sample_mask')
        probe.etc = rmfield(probe.etc, 'clean_sample_mask');   % clean_windows merges into it
    end
    [~, keep] = clean_windows(probe, opt.WindowCriterion, [-inf 7]);
    rejected = rejected | ~reshape(keep, 1, []);
end
repaired.srate = srate;

% Put the removed channels back, interpolated, in their own places.
if ~isempty(interpolated)
    repaired = eeg_interp(repaired, scalp.chanlocs, 'spherical');
end
[found, order] = ismember(lower(scalpLabels), lower({repaired.chanlocs.labels}));
if ~all(found)
    throw(MException('Alakazam:ASR', ['I''m afraid the channels could not be put back after ' ...
        'cleaning: %s went missing. This usually means a clean_rawdata version that renames ' ...
        'channels.'], strjoin(scalpLabels(~found), ', ')));
end
EEG.data(scalpIdx, :) = repaired.data(order, :);
EEG.data(:, rejected) = NaN;

EEG.etc.alz.asr = struct( ...
    'version',          cleanRawdataVersion(), ...
    'channels',         {scalpLabels}, ...
    'interpolated',     {interpolated}, ...
    'samplesRepaired',  nnz(changed & ~rejected), ...
    'samplesRejected',  nnz(rejected), ...
    'nSamples',         numel(rejected), ...
    'burstCriterion',   opt.BurstCriterion, ...
    'options',          options);

fprintf(['ASR: %d of %d scalp channel(s) interpolated%s; %.1f%% of the samples repaired, ' ...
    '%.1f%% rejected.\n'], numel(interpolated), numel(scalpIdx), listed(interpolated), ...
    100 * nnz(changed & ~rejected) / numel(rejected), 100 * nnz(rejected) / numel(rejected));
end

% ======================================================================= %
function requireContinuous(input)
%REQUIRECONTINUOUS  ASR slides its windows along one continuous recording.
    if ndims(input.data) > 2 || ~strcmpi(TransTools.FieldOr(input, 'DataFormat', 'CONTINUOUS'), 'CONTINUOUS')
        throw(MException('Alakazam:ASR', ['I''m afraid ASR works on the continuous ' ...
            'recording, and this dataset is %s. Would you run it before DefineBins?'], ...
            lower(char(string(TransTools.FieldOr(input, 'DataFormat', 'epoched'))))));
    end
end

function ensureCleanRawdata()
%ENSURECLEANRAWDATA  clean_rawdata ships with EEGLAB and is on Alakazam's
%   startup list (EEGLabEnvironment), so this only acts for an EEGLAB that
%   lacks it: it asks EEGLAB's plugin manager, as the startup does.
    if ~isempty(which('clean_asr'))
        return;
    end
    if ~isempty(which('plugin_askinstall'))
        try
            plugin_askinstall('clean_rawdata', 'clean_asr', true);
        catch
            % Reported below, with what to do about it.
        end
    end
    if isempty(which('clean_asr'))
        throw(MException('Alakazam:ASR', ['I''m afraid ASR needs EEGLAB''s clean_rawdata ' ...
            'plugin, which is not installed and could not be installed just now. Would you ' ...
            'install it from EEGLAB''s File > Manage EEGLAB extensions, then try again?']));
    end
end

function opt = normaliseOptions(options)
%NORMALISEOPTIONS  Fill the defaults for anything a stored options struct
%   lacks, so an older node replays as it was made.
    opt.FlatlineSeconds    = TransTools.FieldOr(options, 'FlatlineSeconds', 5);
    opt.ChannelCorrelation = TransTools.FieldOr(options, 'ChannelCorrelation', 0.8);
    opt.LineNoiseSD        = TransTools.FieldOr(options, 'LineNoiseSD', 4);
    opt.BurstCriterion     = TransTools.FieldOr(options, 'BurstCriterion', 20);
    opt.BurstHandling      = char(string(TransTools.FieldOr(options, 'BurstHandling', 'Repaired')));
    opt.RejectWindows      = logical(TransTools.FieldOr(options, 'RejectWindows', false));
    opt.WindowCriterion    = TransTools.FieldOr(options, 'WindowCriterion', 0.25);
    if ~(opt.BurstCriterion > 0)
        throw(MException('Alakazam:ASR', ['I''m afraid a burst criterion of %g cannot be ' ...
            'used: it is a number of standard deviations, and 20 to 30 is the range found ' ...
            'to work on real EEG.'], opt.BurstCriterion));
    end
end

function warnIfUnfiltered(EEG, scalpIdx)
%WARNIFUNFILTERED  Say so when the scalp channels still carry large offsets.
%   ASR calibrates on covariance, which a DC offset or a slow drift
%   dominates, so on unfiltered data it mistakes the drift for the
%   scalp's normal state. A high-passed channel has a mean near zero
%   relative to its spread; a DC-coupled recording's channels sit far from
%   zero. Warned, not refused: the choice of filter is the user's.
    x = double(EEG.data(scalpIdx, :));
    offset = median(abs(mean(x, 2, 'omitnan')) ./ max(std(x, 0, 2, 'omitnan'), eps));
    if offset > 0.5
        fprintf(['ASR: WARNING -- the scalp channels carry large offsets (median |mean| is %.1f ' ...
            'SD), so the recording looks unfiltered. ASR assumes data without slow drifts; ' ...
            'a high-pass Filter (about 0.5 to 1 Hz) before ASR is advised.\n'], offset);
    end
end

function v = cleanRawdataVersion()
%CLEANRAWDATAVERSION  The clean_rawdata install that ran, by its folder
%   name, which is how EEGLAB's plugin manager names a version
%   ('clean_rawdata2.10'); 'unknown' when it cannot be told.
    v = 'unknown';
    where = which('clean_asr');
    if ~isempty(where)
        [~, v] = fileparts(fileparts(where));
    end
end

function s = listed(labels)
    if isempty(labels)
        s = '';
    else
        s = [' (' strjoin(labels, ', ') ')'];
    end
end
