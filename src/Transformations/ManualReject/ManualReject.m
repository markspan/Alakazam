function [EEG, options] = ManualReject(input, varargin)
%% ManualReject  Manually flag artefact-contaminated trials or channels by inspection.
%
%   The manual counterpart of ArtefactDetect: rather than an automatic
%   threshold, it opens a per-trial channel browser (ManualRejectDialog)
%   showing every channel's waveform for one trial at a time, and lets the
%   analyst click a channel to flag it faulty for that trial while walking
%   through the whole recording. On confirm, flagged data is rejected the
%   same way ArtefactDetect rejects a detected hit -- set to NaN, which
%   Average already omits -- with the same Whole-epoch/This-channel-only
%   Scope choice ArtefactDetect offers. For This-channel-only, a further
%   choice: leave the flagged cell NaN, or reconstruct it from its
%   neighbours (EEGLAB's spherical-spline interpolation -- the same maths
%   Interpolate.m uses for a whole-recording bad channel, applied here one
%   trial at a time so a channel flagged bad in trial 12 is untouched in
%   every other trial).
%
%   Because the flagged (channel, trial) cells are specific to one
%   dataset's own trial count and order, this transform is inspection-
%   driven and is not registered as recalculable -- the same reasoning
%   RemoveComponents.m gives for its own component indices being specific
%   to one ICA decomposition. The stored options record the flags (and the
%   two settings) for provenance; replaying them onto a differently-shaped
%   dataset is rejected with a friendly error rather than silently
%   misapplying them.
%
%   Signature (Alakazam transformation contract):
%     [EEG, options] = ManualReject(input)        % interactive browser
%     [EEG, options] = ManualReject(input, opts)  % replay a stored struct
[options, interactive] = TransTools.InitGuard(nargin, 'Alakazam:ManualReject', varargin{:});

EEG = input;
if ~isfield(EEG, 'data') || isempty(EEG.data)
    throw(MException('Alakazam:ManualReject', ...
        'Problem in ManualReject: I''m afraid this dataset has no data.'));
end
if ismatrix(EEG.data) || (isfield(EEG, 'DataFormat') && ~strcmpi(EEG.DataFormat, 'EPOCHED'))
    throw(MException('Alakazam:ManualReject', ...
        ['Problem in ManualReject: I''m afraid this needs segmented (epoched) data. Please segment it ' ...
         'first (e.g. with DefineBins), then flag trials/channels on the epoched result.']));
end

if interactive
    options = ManualRejectDialog(EEG, TransformSettings.get('ManualReject'));
    if isempty(options)
        EEG = [];   % cancelled -- no node, no compute
        return;
    end
    TransformSettings.set('ManualReject', options);
end

[nChan, ~, nTrials] = size(EEG.data);
if ~isfield(options, 'flags') || ~isequal(size(options.flags), [nChan, nTrials])
    throw(MException('Alakazam:ManualReject', ...
        ['Problem in ManualReject: I''m afraid the stored flags do not match this dataset''s shape ' ...
         '(%d channel(s) x %d trial(s)). This usually means these flags were recorded by walking ' ...
         'through a different dataset -- please run ManualReject interactively on this one instead.'], ...
        nChan, nTrials));
end

if ~any(options.flags(:))
    return;   % nothing flagged: keep the dataset unchanged
end

if strcmpi(options.scope, 'Whole epoch')
    badTrials = any(options.flags, 1);
    EEG.data(:, :, badTrials) = NaN;
    fprintf('ManualReject: rejected %d of %d epoch(s).\n', sum(badTrials), nTrials);
elseif strcmpi(options.channelMode, 'Interpolate')
    EEG = interpolateFlaggedCells(EEG, options.flags);
    fprintf('ManualReject: interpolated %d flagged channel-epoch(s).\n', nnz(options.flags));
else
    for t = 1:nTrials
        EEG.data(options.flags(:, t), :, t) = NaN;
    end
    fprintf('ManualReject: flagged (NaN) %d channel-epoch(s).\n', nnz(options.flags));
end
end

% ======================================================================= %
function EEG = interpolateFlaggedCells(EEG, flags)
%INTERPOLATEFLAGGEDCELLS  Reconstruct every flagged (channel, trial) cell
%   from its neighbours, one trial at a time. eeg_interp (the function
%   pop_interp itself calls, and Interpolate.m calls indirectly through it)
%   is handed a one-trial copy of EEG so its own spherical-spline maths
%   only ever sees THIS trial's spatial pattern -- the same channel is
%   free to be flagged in one trial and left alone in the next, unlike
%   pop_interp's own whole-recording "this channel is bad everywhere" model.
    nTrials = size(EEG.data, 3);
    for t = 1:nTrials
        badIdx = find(flags(:, t));
        if isempty(badIdx)
            continue;
        end
        oneTrial = EEG;
        oneTrial.data   = EEG.data(:, :, t);
        oneTrial.trials = 1;
        oneTrial = eeg_interp(oneTrial, badIdx, 'spherical');
        EEG.data(badIdx, :, t) = oneTrial.data(badIdx, :);
    end
end
