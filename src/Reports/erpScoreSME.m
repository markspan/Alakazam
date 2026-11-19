function [sme, method, score] = erpScoreSME(trials, times, win, nBoot)
%ERPSCORESME  Standardized measurement error (Luck et al., 2021) of ONE
%   Measure window's own score, per channel, from single trials.
%
%   SME is the standard error of the score you actually report: re-run the
%   same subject in the same condition, and this is how far the number
%   would be expected to move. That makes it comparable across subjects and
%   across labs in a way a rejection percentage never is, and it is the
%   reason it is worth computing per WINDOW rather than once per recording:
%   a subject can be clean in one time range and hopeless in another, and a
%   whole-epoch summary averages that distinction away.
%
%   Two estimators, picked automatically per score type, exactly as Luck et
%   al. set out:
%
%     * MEAN AMPLITUDE has a closed form. The mean amplitude of the average
%       IS the average of the per-trial mean amplitudes, so its standard
%       error is just SD(per-trial scores)/sqrt(n). METHOD is "analytic".
%     * EVERY OTHER SCORE (peak amplitude, peak latency, the fractional
%       latencies, area) is a NON-LINEAR function of the waveform: the peak
%       of the average is not the average of the peaks, so there is no such
%       identity to exploit and no closed form to use. These are
%       bootstrapped instead: resample NBOOT sets of n trials with
%       replacement, average each set, score each average, and take the SD
%       of that distribution. METHOD is "bootstrap".
%
%   Scoring a per-trial waveform directly (rather than bootstrapping) would
%   be wrong for the non-linear scores and is not offered: single-trial
%   peak latency is dominated by noise, and its SD estimates the spread of
%   single-trial peaks, which is a different quantity from the standard
%   error of the peak of the average.
%
%   THE SCORE IS MEASURE'S OWN. Scoring is TransTools.MeasureScorer, which
%   Measure.m uses for its values, so the window, its baseline, the local peak,
%   the peak-locked band and the area mode all mean what they mean there, and
%   this is the standard error of that number (Zhang & Luck, 2023, score the
%   SME on the site and window of the score itself).
%
%   TRIALS is channels x samples x trials for ONE bin, with rejected data
%   already NaN (see ArtefactDetect/ManualReject); fully-NaN trials are
%   dropped first, so n is the surviving trial count. A row of TRIALS may be a
%   pool, the mean of its members per trial. TIMES is the epoch time axis in
%   ms. WIN is one entry of EEG.measurements (Measure.m's own window struct).
%   NBOOT defaults to 1000, the number Zhang & Luck (2023) use.
%
%   Returns SME (nChannels x 1, NaN where a channel could not be scored),
%   METHOD ("analytic"/"bootstrap"), and SCORE (nChannels x 1), the score of
%   the actual average.
%
%   Not covered: a window whose peak is located via a REFERENCE channel
%   (Measure's Analyzer-style shared-peak mode). That is a cross-channel
%   dependency this per-channel scorer cannot express, and quietly scoring
%   it per-channel instead would report an SME for a measurement nobody
%   made, so dataQualityMetrics skips those windows outright.
%
%   See also DATAQUALITYMETRICS, MEASURE, AVERAGE.
    if nargin < 4 || isempty(nBoot)
        nBoot = 1000;
    end
    [nChan, ~, ~] = size(trials);
    sme   = nan(nChan, 1);
    score = nan(nChan, 1);

    % A Peak window gives an amplitude and a latency, and they have separate
    % SMEs: 'Peak Latency' asks for the second (dataQualityMetrics' scoreVariants).
    measure = lower(strtrim(char(string(TransTools.FieldOr(win, 'measure', 'mean amplitude')))));
    field = 'amplitude';
    switch measure
        case 'peak latency'
            win.measure = 'Peak';
            field = 'latency';
        case {'fractional peak latency', 'fractional area latency'}
            field = 'latency';
        case {'area', 'integral', 'peak area'}
            field = 'area';
    end
    if strcmp(measure, 'mean amplitude')
        method = "analytic";
    else
        method = "bootstrap";
    end

    % The window as Measure takes it, so that this is the same score.
    win.start = TransTools.FieldOr(win, 'start', times(1));
    win.stop  = TransTools.FieldOr(win, 'stop', times(end));
    win.label = TransTools.FieldOr(win, 'label', 'window');
    win.polarity = TransTools.FieldOr(win, 'polarity', 'Positive');
    if min(win.start, win.stop) > times(end) || max(win.start, win.stop) < times(1)
        return;
    end
    spec = TransTools.MeasureScorer.prepare(win, times);

    for c = 1:nChan
        chanTrials = reshape(trials(c, :, :), size(trials, 2), []);    % samples x trials
        keep = ~all(isnan(chanTrials), 1);
        chanTrials = chanTrials(:, keep);
        n = size(chanTrials, 2);
        if n < 2
            continue;   % no distribution to describe
        end

        s = TransTools.MeasureScorer.score(mean(chanTrials, 2, 'omitnan').', times, spec);
        score(c) = s.(field);

        if strcmp(method, "analytic")
            perTrial = mean(chanTrials(spec.lo:spec.hi, :), 1, 'omitnan');
            if ~isempty(spec.baseLo)
                perTrial = perTrial - mean(chanTrials(spec.baseLo:spec.baseHi, :), 1, 'omitnan');
            end
            sme(c) = std(perTrial, 0, 'omitnan') / sqrt(n);
        else
            sme(c) = bootstrapSME(chanTrials, times, spec, field, nBoot, n);
        end
    end
end

% ======================================================================= %
function s = bootstrapSME(chanTrials, times, spec, field, nBoot, n)
%BOOTSTRAPSME  SD of the score across NBOOT bootstrap averages, seeded, so a
%   report states the same SME every time it is made.
%   The resampling is done as ONE matrix multiply rather than a loop of
%   mean() calls: a bootstrap average is a weighted sum of the same trials,
%   the weights being how many times each trial was drawn, so counts/n
%   applied to the samples x trials matrix produces every bootstrap average
%   at once. A NaN sample is left out of its own average, as mean's 'omitnan'
%   leaves it out of the actual average, rather than being counted as zero.
    previous = rng;
    restore = onCleanup(@() rng(previous));
    rng(20260101, 'twister');

    counts = zeros(n, nBoot);
    for b = 1:nBoot
        idx = randi(n, n, 1);
        counts(:, b) = accumarray(idx, 1, [n 1]);
    end
    present = ~isnan(chanTrials);
    filled = chanTrials;
    filled(~present) = 0;
    boots = (filled * counts) ./ (double(present) * counts);   % samples x nBoot
    scores = nan(1, nBoot);
    for b = 1:nBoot
        one = TransTools.MeasureScorer.score(boots(:, b).', times, spec);
        scores(b) = one.(field);
    end
    s = std(scores, 0, 'omitnan');
end
