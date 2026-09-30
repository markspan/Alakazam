function [EEG, options] = PREP(input, varargin)
%% PREP  The PREP pipeline: line noise removed, bad channels found and
%   interpolated, and the recording put on a robust average reference.
%
%   Runs prepPipeline (Bigdely-Shamlo, Mullen, Kothe, Su & Robbins, 2015,
%   Front Neuroinform 9:16), the standardised early-stage pipeline that
%   large EEG studies cite as one step. In order, PREP
%     1. removes line noise at the mains frequency and its harmonics
%        (multi-taper regression, cleanline), leaving the rest of the
%        spectrum untouched;
%     2. estimates a ROBUST average reference: the average of the channels
%        that are not bad, where bad is decided on a high-passed copy by
%        four criteria (extreme amplitude, a robust z of the channel's
%        deviation; poor correlation with the others; excess high-frequency
%        noise; poor prediction from its neighbours, by RANSAC), iterated
%        because which channels look bad depends on the reference;
%     3. interpolates the channels that are bad against that reference, and
%        returns every channel referenced to it.
%   The high-passed copy is only used to decide; the data returned keep
%   their low frequencies, so filter separately (Filter) as the analysis
%   needs.
%
%   WHICH CHANNELS. The reference is estimated from, and bad channels are
%   looked for among, the scalp EEG channels with a 10-5 position
%   (TransTools.ScalpChannels). The EOG channels are cleaned of line noise
%   and put on the same reference, so an eye channel stays comparable with
%   the scalp, but they neither shape the reference nor are interpolated.
%   Anything else (ECG, a photodiode, a trigger channel) is left exactly as
%   it was.
%
%   WHAT IT RECORDS. PREP's own full account stays on the dataset as
%   EEG.etc.noiseDetection. What a methods section and the data-quality
%   report need is copied to EEG.etc.alz.prep: the PREP version, the
%   channels interpolated, those still noisy after referencing, the line
%   frequencies, and the channel sets used.
%
%   CONTINUOUS DATA ONLY, as PREP requires. A recording with boundary events
%   (discontinuities from an edit or a concatenation) is refused by PREP
%   unless "Ignore boundary events" is ticked, which PREP's authors advise
%   doing with care: its filters then run across the discontinuities.
%
%   PREP is not bundled. It is downloaded on first use, after consent,
%   pinned to version 0.56.0 (see prepToolbox).
%
%   Signature (Alakazam transformation contract):
%     [EEG, options] = PREP(input)        % interactive dialog
%     [EEG, options] = PREP(input, opts)  % replay a stored options struct
%
%   See also ASR, AUTOREJECT, PREPTOOLBOX, TRANSTOOLS.SCALPCHANNELS.
[opts, interactive] = TransTools.InitGuard(nargin, 'Alakazam:PREP', varargin{:});

requireContinuous(input);
TransTools.EnsureToolbox(prepToolbox());

if interactive
    stored = TransformSettings.get('PREP');
    if isempty(stored) || ~isstruct(stored)
        stored = struct();
    end
    d = @(f, v) TransTools.FieldOr(stored, f, v);
    options = TransformOptionsDialog( ...
        'title', 'PREP options', ...
        'Description', ['The PREP pipeline: line noise removed, bad scalp channels found and ' ...
            'interpolated, and every channel put on a robust average reference. The defaults ' ...
            'are PREP''s own, except the line frequency.'], ...
        'separator', 'Line noise:', ...
        {'Line frequency (Hz)'; 'LineFrequency'}, TransTools.PutFirst({'50', '60', 'none'}, d('LineFrequency', '50')), ...
        'separator', 'Bad channels:', ...
        {'Robust deviation (z)'; 'DeviationThreshold'}, DialogFields.Number(d('DeviationThreshold', 5), 'Limits', [0 Inf]), ...
        {'High-frequency noise (z)'; 'HighFrequencyThreshold'}, DialogFields.Number(d('HighFrequencyThreshold', 5), 'Limits', [0 Inf]), ...
        {'Minimum correlation'; 'CorrelationThreshold'}, DialogFields.Number(d('CorrelationThreshold', 0.4), 'Limits', [0 1]), ...
        {'Predict from neighbours (RANSAC)'; 'Ransac'}, d('Ransac', true), ...
        'separator', 'Discontinuities:', ...
        {'Ignore boundary events'; 'IgnoreBoundaries'}, d('IgnoreBoundaries', false));
    if isempty(options)
        EEG = [];   % cancelled: no node, no compute
        return;
    end
    TransformSettings.set('PREP', options);
else
    options = opts;
end
opt = normaliseOptions(options);

[EEG, scalpIdx] = TransTools.ScalpChannels(input, 'Alakazam:PREP');
eogIdx = find(strcmpi({EEG.chanlocs.type}, 'EOG'));
cleanedIdx = sort([scalpIdx, eogIdx]);

params = struct( ...
    'name',                        datasetName(EEG), ...
    'referenceChannels',           scalpIdx, ...
    'evaluationChannels',          scalpIdx, ...
    'rereferencedChannels',        cleanedIdx, ...
    'lineNoiseChannels',           cleanedIdx, ...
    'detrendChannels',             cleanedIdx, ...
    'robustDeviationThreshold',    opt.DeviationThreshold, ...
    'highFrequencyNoiseThreshold', opt.HighFrequencyThreshold, ...
    'correlationThreshold',        opt.CorrelationThreshold, ...
    'ransacOff',                   ~opt.Ransac, ...
    'ignoreBoundaryEvents',        opt.IgnoreBoundaries, ...
    'errorMsgs',                   'verbose');
lineFrequencies = prepLineFrequencies(opt.LineFrequency, EEG.srate);
if isempty(lineFrequencies)
    params.lineNoiseMethod = 'none';
else
    params.lineFrequencies = lineFrequencies;
end

prepared = prepPipeline(EEG, params);
detection = prepared.etc.noiseDetection;
refuseUnlessProcessed(detection, opt);

% Only the data and the reference change. Everything else, Alakazam's own
% fields included, is the dataset as it came in (with the positions filled).
EEG.data = prepared.data;
EEG.ref  = 'average';
EEG.etc.noiseDetection = detection;
labels = {EEG.chanlocs.labels};
EEG.etc.alz.prep = struct( ...
    'version',              prepVersion(), ...
    'interpolated',         {labels(channelNumbers(detection, 'interpolatedChannelNumbers'))}, ...
    'stillNoisy',           {labels(channelNumbers(detection, 'stillNoisyChannelNumbers'))}, ...
    'lineFrequencies',      lineFrequencies, ...
    'referenceChannels',    {labels(scalpIdx)}, ...
    'rereferencedChannels', {labels(cleanedIdx)}, ...
    'options',              options);

report = EEG.etc.alz.prep;
fprintf('PREP: %d of %d scalp channel(s) interpolated%s.\n', numel(report.interpolated), ...
    numel(scalpIdx), listed(report.interpolated));
if ~isempty(report.stillNoisy)
    fprintf('PREP: still noisy after referencing: %s.\n', strjoin(report.stillNoisy, ', '));
end
end

% ======================================================================= %
function requireContinuous(input)
%REQUIRECONTINUOUS  PREP's line-noise and reference steps assume one
%   continuous recording.
    if ndims(input.data) > 2 || ~strcmpi(TransTools.FieldOr(input, 'DataFormat', 'CONTINUOUS'), 'CONTINUOUS')
        throw(MException('Alakazam:PREP', ['I''m afraid PREP works on the continuous ' ...
            'recording, and this dataset is %s. Would you run it before DefineBins?'], ...
            lower(char(string(TransTools.FieldOr(input, 'DataFormat', 'epoched'))))));
    end
end

function opt = normaliseOptions(options)
%NORMALISEOPTIONS  Fill PREP's own defaults for anything a stored options
%   struct lacks, so an older node replays as it was made.
    opt.LineFrequency          = TransTools.FieldOr(options, 'LineFrequency', '50');
    opt.DeviationThreshold     = TransTools.FieldOr(options, 'DeviationThreshold', 5);
    opt.HighFrequencyThreshold = TransTools.FieldOr(options, 'HighFrequencyThreshold', 5);
    opt.CorrelationThreshold   = TransTools.FieldOr(options, 'CorrelationThreshold', 0.4);
    opt.Ransac                 = logical(TransTools.FieldOr(options, 'Ransac', true));
    opt.IgnoreBoundaries       = logical(TransTools.FieldOr(options, 'IgnoreBoundaries', false));
end

function refuseUnlessProcessed(detection, opt)
%REFUSEUNLESSPROCESSED  Turn PREP's quiet failure into an error.
%   prepPipeline does not throw: a stage that fails sets
%   etc.noiseDetection.errors.status to 'unprocessed', stores the message in
%   that stage's field and returns the data as far as it got. Passing that
%   on would put a half-processed recording in the tree under PREP's name.
    errors = TransTools.FieldOr(detection, 'errors', struct());
    if isstruct(errors) && strcmpi(TransTools.FieldOr(errors, 'status', ''), 'good')
        return;
    end
    messages = {};
    if isstruct(errors)
        for stage = {'boundary', 'detrend', 'lineNoise', 'reference', 'postProcess'}
            m = TransTools.FieldOr(errors, stage{1}, 0);
            if ischar(m) || isstring(m)
                messages{end + 1} = char(m); %#ok<AGROW>
            end
        end
    end
    advice = '';
    if any(contains(messages, 'boundary')) && ~opt.IgnoreBoundaries
        advice = [' The recording has boundary events; ticking "Ignore boundary events" lets ' ...
            'PREP run across them, which its authors advise doing with care.'];
    end
    throw(MException('Alakazam:PREP', 'I''m afraid PREP could not process this recording: %s%s', ...
        strjoin(messages, ' '), advice));
end

function idx = channelNumbers(detection, field)
%CHANNELNUMBERS  A channel-number list from PREP's record, as a row of
%   valid indices, whatever shape PREP stored it in.
    idx = TransTools.FieldOr(detection, field, []);
    idx = reshape(double(idx), 1, []);
end

function name = datasetName(EEG)
%DATASETNAME  PREP labels its record with a name; the recording's own.
    name = char(string(TransTools.FieldOr(EEG, 'setname', '')));
    if isempty(name)
        [~, name] = fileparts(char(string(TransTools.FieldOr(EEG, 'File', 'recording'))));
    end
end

function v = prepVersion()
%PREPVERSION  PREP's own version string ('PrepPipeline0.56.0'), for the
%   methods section; 'unknown' from a copy too old to say.
    try
        v = getPrepVersion();
    catch
        v = 'unknown';
    end
end

function s = listed(labels)
    if isempty(labels)
        s = '';
    else
        s = [': ' strjoin(labels, ', ')];
    end
end
