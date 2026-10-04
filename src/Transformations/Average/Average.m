function [EEG, opts] = Average(input, varargin)
% Average - Compute the trial average of epoched EEG data.
%
% Syntax: [EEG, opts] = Average(input, opts)
%
% Inputs:
%   input - EEG structure containing the epoched data
%       .data - 3D matrix of EEG data (channels x samples x epochs)
%       .DataFormat - Format of the data, must be 'EPOCHED'
%       .trials - Number of trials (epochs)
%       .bindesc - (optional) per-bin descriptors written by DefineBins; when
%                  present, the average is computed separately per bin.
%   opts - Options for the function, default is 'Init' if not provided
%
% Outputs:
%   EEG - Modified EEG structure with averaged data
%       .data  - averaged EEG data: channels x samples (no bins) or
%                channels x samples x bins (one average per bin)
%       .stErr - Standard error of the mean, matching .data
%       .DataFormat - Set to 'Averaged'
%       .ntrials - Original number of trials
%       .trials - Set to 1 indicating the data is now averaged
%   opts - Options for the function, returned unchanged
%
% Description:
%   Computes the average of epoched EEG data along the third (epoch)
%   dimension. When the dataset carries bin membership (EEG.bindesc / the
%   per-epoch .bini tags produced by DefineBins), each bin is averaged over
%   just the trials that belong to it, giving one channels x samples slice per
%   bin plus a matching standard error and per-bin trial count. Without bins it
%   averages across all trials, as before. A trial in several bins contributes
%   to each of them.
%
%   TOOLBOX OR OWN CODE. The arithmetic is MATLAB's mean and std. ERPLAB's
%   pop_averager does the same job, but ERPLAB is not a toolbox Alakazam
%   installs, and its averager reads ERPLAB's EVENTLIST and drops whole
%   flagged epochs, where this leaves a rejected channel of a trial out (NaN)
%   and keeps the rest, counts the trials per channel, and forms combination
%   bins with their propagated standard errors in the same step. EEGLAB has no
%   binned average with a standard error. Measured against Luck's own
%   1_N400.erp (Docs/luck.md): the same accepted and rejected counts per bin,
%   and waveforms to 0.0004 uV; LibraryReplayTest replays those chapters.
%
opts = TransTools.InitGuard(nargin, 'Alakazam:Average', varargin{:});

% Validate input data
if ~isfield(input, 'data')
    throw(MException('Alakazam:Average', ...
        'Problem in Average: I''m afraid this dataset has no data at all, so there is nothing to average.'));
end

% TransTools.FieldOr, not a bare input.DataFormat: this condition is true when
% the field is ABSENT as well as when it is wrong, and reading it directly then
% throws a raw "Unrecognized field name" from inside the very message meant to
% explain the problem. The format is named rather than assumed to be
% continuous, since an already-averaged dataset lands here too.
dataFormat = char(string(TransTools.FieldOr(input, 'DataFormat', 'not set')));
if (length(size(input.data)) < 3 || ~strcmpi(dataFormat, 'EPOCHED'))
    throw(MException('Alakazam:Average', sprintf([ ...
        'Problem in Average: this needs segmented (epoched) data, and this dataset ' ...
        'is not (DataFormat = "%s"). Please segment it first (e.g. with DefineBins), ' ...
        'then run Average on the segmented result.'], dataFormat)));
end

if ~isfield(input, 'trials')
    throw(MException('Alakazam:Average', ...
        'Problem in Average: I''m afraid this dataset is missing its trial count, so it cannot be treated as segmented data.'));
end

EEG = input;
[nchan, npnts, ntrials] = size(input.data);
EEG.ntrials = ntrials;
EEG.trials  = 1;
EEG.DataFormat = "Averaged";
% The baseline: every sample up to and including time zero, FieldTrip's
% 'prestim' window. Its covariance, pooled over every clean trial, is the
% noise a dSPM estimate is normalised by (see baselineCovariance); a bin's
% average carries that divided by the number of trials averaged.
baseline = reshape(input.times, 1, []) <= 0;
[trialCov, covTrials] = baselineCovariance(input.data(:, baseline, :));

if isfield(input, 'bindesc') && ~isempty(input.bindesc)
    % Bin-aware: one average per bin, over the trials that belong to it.
    nbin  = numel(input.bindesc);
    data  = nan(nchan, npnts, nbin);
    stErr = nan(nchan, npnts, nbin);
    aSME  = nan(nchan, nbin);   % analytic standardized measurement error, per channel/bin
    noiseCov  = nan(nchan, nchan, nbin);
    for b = 1:nbin
        idx = TransTools.BinTrials(input, b);
        EEG.bindesc(b).n = keptTrials(input.data(:, :, idx));
        if isempty(idx)
            continue;
        end
        data(:, :, b)  = mean(input.data(:, :, idx), 3, 'omitnan');
        stErr(:, :, b) = standardError(input.data(:, :, idx));
        aSME(:, b)     = windowedSME(input.data(:, :, idx));
        noiseCov(:, :, b) = trialCov / max(EEG.bindesc(b).n, 1);
    end

    % Second pass: combination (difference) bins defined in DefineBins with
    % "bin N = bin A - bin B". They have no trials of their own; their average
    % is the signed sum of the referenced bins' averages, and the standard
    % error propagates as the root of the summed squared errors. A
    % combination bin may itself reference another combination bin (a
    % difference-of-differences, e.g. an interaction effect), so these are
    % computed in the dependency order TransTools.ComboOrder works out, the
    % one resolver ComputeErsp and Unfold.fitBins share with this.
    [steps, unresolved] = TransTools.ComboOrder(input.bindesc);
    for s = steps
        acc     = zeros(nchan, npnts);
        varAcc  = zeros(nchan, npnts);
        smeAcc  = zeros(nchan, 1);
        covAcc  = zeros(nchan, nchan);
        nParts = strings(1, numel(s.parts));
        for t = 1:numel(s.parts)
            r      = s.parts(t);
            coeff  = s.coeffs(t);
            acc    = acc    + coeff * data(:, :, r);
            varAcc = varAcc + (coeff * stErr(:, :, r)).^2;
            smeAcc = smeAcc + (coeff * aSME(:, r)).^2;
            covAcc = covAcc + coeff^2 * noiseCov(:, :, r);   % independent trials
            if coeff < 0;         sign = "-";
            elseif t == 1;        sign = "";
            else;                 sign = "+";
            end
            nParts(t) = sign + string(EEG.bindesc(r).n);
        end
        data(:, :, s.target)  = acc;
        stErr(:, :, s.target) = sqrt(varAcc);
        aSME(:, s.target)     = sqrt(smeAcc);
        noiseCov(:, :, s.target) = covAcc;
        % A combination bin has no trials of its own; report the
        % constituent bins' (signed) trial counts, e.g. "68-74", or, for
        % a nested combination, another such string, rather than the
        % misleading "0" its own (empty) trial list would otherwise give.
        EEG.bindesc(s.target).n = char(strjoin(nParts, ""));
    end
    % Any bin left unresolved here references one that does not exist, or is
    % part of a cycle; DefineBins already rejects both at parse time, so this
    % only bites a hand-built/edited .bins struct (e.g. a stored session).
    for b = unresolved
        warning('Alakazam:Average', ...
            '"%s": could not resolve its combination (unknown or circular bin reference); left as NaN.', ...
            input.bindesc(b).label);
    end

    EEG.data  = data;
    EEG.stErr = stErr;
    EEG.aSME  = aSME;
else
    % No bins: average across every trial.
    EEG.data  = mean(input.data, 3, 'omitnan');
    EEG.stErr = standardError(input.data);
    EEG.aSME  = windowedSME(input.data);
    noiseCov = trialCov / max(keptTrials(input.data), 1);
end
if covTrials >= 2
    EEG.noiseCov = noiseCov;
    times = reshape(input.times, 1, []);
    EEG.noiseCovInfo = struct('windowMs', [times(find(baseline, 1)), times(find(baseline, 1, 'last'))], ...
        'nTrials', covTrials, ...
        'definition', ['FieldTrip''s ft_timelockanalysis covariance of the baseline, ' ...
            'pooled over every clean trial, divided by the number of trials each ' ...
            'average holds: the noise of that average']);
else
    % No baseline before the event: nothing to estimate the noise from. A
    % source estimate then falls back to the identity, and says so.
    EEG.noiseCov = [];
    EEG.noiseCovInfo = [];
end
end

function [C, n] = baselineCovariance(trials)
%BASELINECOVARIANCE  The covariance of a single trial's noise, from the
%   baseline of TRIALS (channels x baseline samples x trials), and how many
%   trials it is from.
%
%   FieldTrip's own definition, so that a dSPM estimate here is normalised
%   as FieldTrip's ft_sourceanalysis would normalise it: ft_timelockanalysis
%   with cfg.covariance = 'yes' demeans each trial within the window
%   (removemean, its default), sums x*x' over the trials, and divides by the
%   summed number of samples less one per trial. FieldTripReferenceTest
%   holds this to FieldTrip.
%
%   POOLED OVER EVERY TRIAL, NOT PER BIN, as FieldTrip's minimum-norm
%   tutorial and MNE both estimate it: the noise is a property of the
%   recording, and one estimate from all trials is steadier than one per
%   condition. The average of N trials carries 1/N of it, which is what
%   each bin is given. With FieldTrip's prewhitening and source-covariance
%   scaling that leaves every bin the same spatial filter, so conditions
%   are compared through one operator, and only the dSPM scale differs,
%   by the square root of the trials averaged, as it should.
%
%   A TRIAL WITH ANY REJECTED (NaN) SAMPLE IN THE WINDOW IS LEFT OUT, every
%   channel of it: FieldTrip refuses channel-specific NaNs here, and in
%   FieldTrip rejected trials are removed before the covariance is taken.
%   With fewer than two clean trials there is no estimate (NaN).
    nChan = size(trials, 1);
    nSmp  = size(trials, 2);
    C = nan(nChan, nChan);
    clean = reshape(all(all(isfinite(trials), 1), 2), 1, []);
    n = nnz(clean);
    if nSmp < 2 || n < 2
        n = 0;
        return;
    end
    x = double(trials(:, :, clean));
    x = x - mean(x, 2);                      % each trial demeaned in the window
    x = reshape(x, nChan, []);
    C = (x * x') / (n * (nSmp - 1));         % summed samples less one per trial
    C = (C + C') / 2;
end

function n = keptTrials(trials)
%KEPTTRIALS  How many trials of a bin went into its average: those not
%   rejected as a whole epoch (every sample NaN). This is the count the
%   legend shows, averagedToErpset exports as ERPLAB's accepted trials, and
%   a weighted grand average weights by; it used to count the rejected
%   trials too. A trial rejected on some channels only still counts, since
%   the other channels' averages include it.
    if isempty(trials)
        n = 0;
        return;
    end
    n = nnz(any(~isnan(reshape(trials, [], size(trials, 3))), 1));
end

function se = standardError(trials)
%STANDARDERROR  Standard error of the mean across trials, per channel and
%   sample. The divisor is the number of trials that were KEPT there, not the
%   number in the bin: rejection writes NaN and leaves the trial in place
%   (ArtefactDetect, ManualReject), so dividing by every trial in the bin
%   made the band too narrow by sqrt(kept/total) -- 13% at a quarter of the
%   trials rejected -- while std itself already left the NaNs out. With
%   one channel rejected in one trial, that channel's count drops and no
%   other's does. erpScoreSME counts the same way.
    se = std(trials, 0, 3, 'omitnan') ./ sqrt(sum(~isnan(trials), 3));
end

function sme = windowedSME(trials)
%WINDOWEDSME  Analytic standardized measurement error of the mean amplitude,
%   per channel: the standard deviation across trials of each trial's own
%   mean amplitude (over the whole epoch), divided by sqrt(number of trials).
%   This is the SME ERPLAB reports for a mean-amplitude score, here summarised
%   over the full epoch (the per-time-point counterpart is EEG.stErr, the
%   shaded band in AverageView). TRIALS is channels x time x trials.
    % reshape, not squeeze: with one channel, squeeze turns channels x 1 x
    % trials into a trials x 1 column, and the SME came out one per trial.
    perTrialMean = reshape(mean(trials, 2, 'omitnan'), size(trials, 1), []);   % channels x trials
    % n counts the trials KEPT on each channel (a rejected trial's mean is
    % NaN), for the reason standardError gives.
    n = sum(~isnan(perTrialMean), 2);
    sme = std(perTrialMean, 0, 2, 'omitnan') ./ sqrt(n);
    sme(n < 2) = NaN;
end
