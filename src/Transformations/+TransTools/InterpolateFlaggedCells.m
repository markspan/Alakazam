function EEG = InterpolateFlaggedCells(EEG, flags)
%INTERPOLATEFLAGGEDCELLS  Reconstruct every flagged (channel, trial) cell
%   from its neighbours, one trial at a time, and record that it happened.
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
    if isempty(flags) || ~any(flags(:))
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

    EEG = recordInterpolated(EEG, flags);
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
