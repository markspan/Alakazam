function [EEG, nInterpolated] = InterpolateFlaggedCells(EEG, flags)
%INTERPOLATEFLAGGEDCELLS  Reconstruct every flagged (channel, trial) cell
%   from its neighbours, one trial at a time, and record that it happened.
%
%   NINTERPOLATED is how many cells were ACTUALLY reconstructed, which is
%   not always how many were flagged: a channel with no scalp position
%   cannot be placed and is left flagged instead (see the guard below). A
%   caller that reports nnz(flags) rather than this number tells the
%   analyst it repaired data it did not touch.
%
%   EEG = TransTools.InterpolateFlaggedCells(EEG, FLAGS) takes a logical
%   nChan x nTrials FLAGS matrix and replaces each flagged cell's samples
%   with EEGLAB's spherical-spline interpolation of the remaining channels
%   -- the same maths Interpolate.m uses for a whole-recording bad channel,
%   applied here one trial at a time, so a channel flagged bad in trial 12
%   is untouched in every other trial.
%
%   eeg_interp (the function pop_interp itself calls, and Interpolate.m
%   calls indirectly through it) is handed a one-trial copy of EEG so its
%   own spherical-spline maths only ever sees THIS trial's spatial pattern,
%   unlike pop_interp's own whole-recording "this channel is bad
%   everywhere" model.
%
%   WHY THIS RECORDS A MASK. Rejection in Alakazam is written as NaN, and
%   everything downstream reads that convention rather than a flag field:
%   dataQualityMetrics tells a whole-epoch rejection from a channel-scoped
%   one purely by how many channels of a trial are entirely NaN. Interpolation
%   fills the flagged cells back in with real numbers, so a cell that was
%   interpolated is indistinguishable from one that was never flagged at all
%   -- the data-quality report would show a pristine recording no matter how
%   much of it had been reconstructed. This function therefore writes
%
%       EEG.etc.alz.interpolated   logical nChan x nTrials
%
%   OR-ed with whatever an earlier step already recorded, so a dataset that
%   has been through interpolation twice keeps both rounds. That mask is the
%   ONLY trace interpolation leaves in the data, and dataQualityMetrics
%   reads it to report % channel-epochs interpolated alongside % flagged.
%   Any future caller that reconstructs data must write it too, or the
%   reconstruction becomes invisible to the report meant to audit it.
%
%   A CAVEAT WORTH KNOWING. Spherical-spline interpolation reconstructs a
%   channel from its neighbours, and many artefacts are spatially
%   correlated: a blink hits the whole frontal cluster at once, so
%   interpolating Fp1 from Fp2 during a blink faithfully reproduces the
%   blink. Callers that flag cells automatically (ArtefactDetect) warn when
%   a trial has so many flagged channels that the survivors are unlikely to
%   be clean; callers driven by inspection (ManualReject) rely on the
%   analyst having looked.
%
%   See also INTERPOLATE, MANUALREJECT, ARTEFACTDETECT, DATAQUALITYMETRICS.
    nInterpolated = 0;
    if isempty(flags) || ~any(flags(:))
        return;
    end

    % ONLY CHANNELS WITH A SCALP POSITION CAN BE RECONSTRUCTED, and this is
    % a guard rather than a nicety. eeg_interp places a bad channel by its
    % coordinates; handed one without any (an EOG or ECG channel, which no
    % 10-5 lookup positions) it removes that channel from the set instead,
    % and the caller then indexes a channel that is no longer there:
    % "Index in position 1 exceeds array bounds". Reproduced before this
    % guard existed, with a VEOG flagged by ArtefactDetect.
    %
    % A cell that cannot be reconstructed stays FLAGGED rather than quietly
    % kept: it was judged bad, and NaN is what the rest of the app already
    % reads as bad (see dataQualityMetrics' own NaN convention).
    positioned = positionedChannels(EEG, size(flags, 1));
    unreconstructable = flags & ~positioned(:);
    flags = flags & positioned(:);
    if any(unreconstructable(:))
        for k = 1:size(EEG.data, 3)
            EEG.data(unreconstructable(:, k), :, k) = NaN;
        end
        fprintf(['InterpolateFlaggedCells: %d channel-epoch(s) on channel(s) with no ' ...
            'scalp position were left flagged rather than interpolated.\n'], ...
            nnz(unreconstructable));
    end
    if ~any(flags(:))
        return;
    end

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

    nInterpolated = nnz(flags);
    EEG = recordInterpolated(EEG, flags);
end

% ======================================================================= %
function mask = positionedChannels(EEG, nChan)
%POSITIONEDCHANNELS  Which channels eeg_interp could actually place.
%   A channel needs a finite X to be interpolated onto the scalp. Missing
%   chanlocs entirely means nothing can be placed, which is the honest
%   answer rather than an optimistic one.
    mask = false(1, nChan);
    if ~isfield(EEG, 'chanlocs') || numel(EEG.chanlocs) ~= nChan || ...
            ~isfield(EEG.chanlocs, 'X')
        return;
    end
    for c = 1:nChan
        x = EEG.chanlocs(c).X;
        mask(c) = ~isempty(x) && all(isfinite(x));
    end
end

% ======================================================================= %
function EEG = recordInterpolated(EEG, flags)
%RECORDINTERPOLATED  Merge FLAGS into EEG.etc.alz.interpolated.
%   Written defensively because EEG.etc is EEGLAB's own free-form field: it
%   may be absent, empty, or (on data that has been through some toolboxes)
%   not a struct at all, and none of those may be allowed to error here.
    [nChan, ~, nTrials] = size(EEG.data);

    if ~isfield(EEG, 'etc') || ~isstruct(EEG.etc) || isempty(EEG.etc)
        EEG.etc = struct();
    end
    if ~isfield(EEG.etc, 'alz') || ~isstruct(EEG.etc.alz) || isempty(EEG.etc.alz)
        EEG.etc.alz = struct();
    end

    previous = false(nChan, nTrials);
    if isfield(EEG.etc.alz, 'interpolated')
        stored = EEG.etc.alz.interpolated;
        if islogical(stored) && isequal(size(stored), [nChan, nTrials])
            previous = stored;
        end
        % A stored mask of the wrong shape belongs to a differently shaped
        % dataset (a resample or a channel edit since it was written), so it
        % cannot be merged: it is dropped rather than misaligned.
    end

    EEG.etc.alz.interpolated = previous | logical(flags);
end
