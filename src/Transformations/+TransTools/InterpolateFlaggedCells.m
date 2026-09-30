function [EEG, nInterpolated] = InterpolateFlaggedCells(EEG, flags)
%INTERPOLATEFLAGGEDCELLS  Reconstruct every flagged (channel, trial) cell
%   from its neighbours, one trial at a time, and record that it happened.
%
%   NINTERPOLATED is how many cells were ACTUALLY reconstructed, which is
%   not always how many were flagged: a channel with no scalp position
%   cannot be placed and is left flagged instead (see the guard below). A
%   caller that reports nnz(flags) rather than this number tells the
%   user it repaired data it did not touch.
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
%   has been through interpolation twice keeps both rounds (see
%   TransTools.RecordInterpolated, which a caller that reconstructs data in
%   some other way uses too). That mask is the
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
%   user having looked.
%
%   See also INTERPOLATE, MANUALREJECT, ARTEFACTDETECT, AUTOREJECT,
%   TRANSTOOLS.RECORDINTERPOLATED, DATAQUALITYMETRICS.
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

    % A TRIAL WITH NO POSITIONED GOOD CHANNEL LEFT has nothing for a
    % spherical-spline scalp pattern to be built from, and eeg_interp does
    % not fail cleanly when handed one: computeg's electrode-coordinate
    % array comes out empty, and MATLAB's own legendre() then throws
    % "Operands to the short-circuit AND/OR... must be convertible to
    % logical scalars" -- max() of an empty array is [], not a scalar, so
    % the >1 comparison inside legendre.m produces [] rather than
    % true/false. Reproduced directly, two ways: every channel of a trial
    % flagged, and every UNFLAGGED channel of a trial being unpositioned (an
    % EOG channel left as the only "good" neighbour is just as useless to
    % the spline as no neighbour at all) -- both raise exactly this, with
    % exactly this stack (legendre <- computeg <- spheric_spline <-
    % eeg_interp). Checked against POSITIONED, so a trial is only skipped
    % when it truly has nothing to reconstruct from -- and left flagged
    % here, the same as a channel with no scalp position, rather than
    % letting either case reach eeg_interp at all.
    nTrials = size(EEG.data, 3);
    noGoodNeighbour = false(size(flags));

    % TRIALS THAT SHARE A SET OF BAD CHANNELS ARE INTERPOLATED IN ONE CALL.
    % The spline weights depend only on which channels are bad and where the
    % good ones sit, and eeg_interp applies them sample by sample, so running
    % it once on all trials with the same bad set gives exactly what running
    % it on each of them alone would. On real data most flagged trials share
    % one or two sets (one loose electrode), so this is a call per set rather
    % than a call per trial; AutoReject's cross-validation, which interpolates
    % every epoch once per candidate, depends on it.
    [badSets, ~, setOfTrial] = unique(flags.', 'rows');
    for s = 1:size(badSets, 1)
        badIdx = find(badSets(s, :));
        if isempty(badIdx)
            continue;
        end
        trials = find(setOfTrial == s).';
        if ~any(positioned(:) & ~badSets(s, :).')
            noGoodNeighbour(:, trials) = flags(:, trials);   % only the cells actually flagged
            continue;
        end
        group = EEG;
        group.data   = EEG.data(:, :, trials);
        group.trials = numel(trials);
        group = eeg_interp(group, badIdx, 'spherical');
        EEG.data(badIdx, :, trials) = reshape(group.data(badIdx, :, :), numel(badIdx), [], numel(trials));
    end

    if any(noGoodNeighbour(:))
        for k = 1:nTrials
            EEG.data(noGoodNeighbour(:, k), :, k) = NaN;
        end
        fprintf(['InterpolateFlaggedCells: every channel was flagged in %d trial(s), leaving no ' ...
            'clean neighbour to reconstruct any of them from; %d channel-epoch(s) were left ' ...
            'flagged instead of interpolated.\n'], nnz(any(noGoodNeighbour, 1)), nnz(noGoodNeighbour));
        flags = flags & ~noGoodNeighbour;
    end

    nInterpolated = nnz(flags);
    EEG = TransTools.RecordInterpolated(EEG, flags);
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
