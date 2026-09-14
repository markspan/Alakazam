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
%   TRIALS is channels x samples x trials for ONE bin, with rejected data
%   already NaN (see ArtefactDetect/ManualReject); fully-NaN trials are
%   dropped first, so n is the surviving trial count. TIMES is the epoch
%   time axis in ms. WIN is one entry of EEG.measurements (Measure.m's own
%   window struct: .label/.start/.stop/.measure/.polarity/.fraction/
%   .areaMode/...). NBOOT defaults to 200.
%
%   Returns SME (nChannels x 1, NaN where a channel could not be scored),
%   METHOD ("analytic"/"bootstrap"), and SCORE (nChannels x 1), the score
%   of the actual average, which erpScoreSMETest pins against Measure.m's
%   own value for the same window so this scorer cannot silently drift from
%   the numbers the rest of the app reports.
%
%   See also DATAQUALITYMETRICS, MEASURE, AVERAGE.
    if nargin < 4 || isempty(nBoot)
        nBoot = 200;
    end
    [nChan, ~, ~] = size(trials);
    sme   = nan(nChan, 1);
    score = nan(nChan, 1);

    measure = lower(strtrim(char(string(TransTools.FieldOr(win, 'measure', 'mean amplitude')))));
    if strcmp(measure, 'mean amplitude')
        method = "analytic";
    else
        method = "bootstrap";
    end

    [lo, hi] = windowRange(times, TransTools.FieldOr(win, 'start', times(1)), TransTools.FieldOr(win, 'stop', times(end)));
    if isempty(lo)
        return;
    end

    for c = 1:nChan
        chanTrials = squeeze(trials(c, :, :));          % samples x trials
        if size(trials, 3) == 1
            chanTrials = trials(c, :, :).';             % squeeze collapses a single trial
        end
        keep = ~all(isnan(chanTrials), 1);
        chanTrials = chanTrials(:, keep);
        n = size(chanTrials, 2);
        if n < 2
            continue;   % no distribution to describe
        end

        score(c) = scoreWaveform(mean(chanTrials, 2, 'omitnan').', times, lo, hi, win, measure);

        if strcmp(method, "analytic")
            perTrial = mean(chanTrials(lo:hi, :), 1, 'omitnan');
            sme(c) = std(perTrial, 0, 'omitnan') / sqrt(n);
        else
            sme(c) = bootstrapSME(chanTrials, times, lo, hi, win, measure, nBoot, n);
        end
    end
end

% ======================================================================= %
function s = bootstrapSME(chanTrials, times, lo, hi, win, measure, nBoot, n)
%BOOTSTRAPSME  SD of the score across NBOOT bootstrap averages.
%   The resampling is done as ONE matrix multiply rather than a loop of
%   mean() calls: a bootstrap average is a weighted sum of the same trials,
%   the weights being how many times each trial was drawn, so counts/n
%   applied to the samples x trials matrix produces every bootstrap average
%   at once. With NBOOT at 200 and a scalp's worth of channels that is the
%   difference between a report that renders and one nobody waits for.
    counts = zeros(n, nBoot);
    for b = 1:nBoot
        idx = randi(n, n, 1);
        counts(:, b) = accumarray(idx, 1, [n 1]);
    end
    filled = chanTrials;
    filled(isnan(filled)) = 0;   % a NaN sample would poison the whole product
    boots = (filled * counts) / n;                       % samples x nBoot
    scores = nan(1, nBoot);
    for b = 1:nBoot
        scores(b) = scoreWaveform(boots(:, b).', times, lo, hi, win, measure);
    end
    s = std(scores, 0, 'omitnan');
end

% ======================================================================= %
function v = scoreWaveform(wave, times, lo, hi, win, measure)
%SCOREWAVEFORM  Score one averaged waveform the way Measure.m scores it.
%   Deliberately a separate, narrow implementation rather than a call into
%   Measure.m: Measure's own scoring is a monolithic pass over a whole EEG
%   struct (it resolves channels, bins, reference channels and derivations
%   at the same time), and it would have to be re-entered once per
%   bootstrap iteration per channel. The risk that comes with a second
%   implementation, that the two silently drift apart, is pinned down by
%   erpScoreSMETest, which checks this scorer against Measure.m's own
%   output for the same window on the same average.
%
%   Not covered: a window whose peak is located via a REFERENCE channel
%   (Measure's Analyzer-style shared-peak mode). That is a cross-channel
%   dependency this per-channel scorer cannot express, and quietly scoring
%   it per-channel instead would report an SME for a measurement nobody
%   made, so dataQualityMetrics skips those windows outright.
    v = NaN;
    seg = wave(lo:hi);
    segTimes = times(lo:hi);
    if all(isnan(seg))
        return;
    end
    polarity = lower(strtrim(char(string(TransTools.FieldOr(win, 'polarity', 'positive')))));
    fraction = TransTools.FieldOr(win, 'fraction', 0.5);

    switch measure
        case 'mean amplitude'
            v = mean(seg, 'omitnan');

        case 'peak'
            s = peakIndex(seg, polarity);
            if ~isnan(s)
                v = seg(s);
            end

        case 'peak latency'
            s = peakIndex(seg, polarity);
            if ~isnan(s)
                v = segTimes(s);
            end

        case {'area', 'integral', 'peak area'}
            v = areaOf(segTimes, seg, lower(strtrim(char(string(TransTools.FieldOr(win, 'areaMode', 'signed'))))));

        case 'fractional peak latency'
            v = fractionalPeakLatency(seg, segTimes, polarity, fraction);

        case 'fractional area latency'
            v = fractionalAreaLatency(seg, segTimes, fraction);

        otherwise
            v = mean(seg, 'omitnan');
    end
end

function s = peakIndex(seg, polarity)
    if startsWith(polarity, 'neg')
        [~, s] = min(seg);
    else
        [~, s] = max(seg);
    end
    if isempty(s); s = NaN; end
end

function a = areaOf(t, v, mode)
%AREAOF  Area under V over T, by integration mode. Mirrors Measure.m's own
%   areaOf: 'signed' integrates as-is, the others rectify or one-side the
%   waveform first.
    switch mode
        case 'rectified'
            v = abs(v);
        case 'positive'
            v(v < 0) = 0;
        case 'negative'
            v(v > 0) = 0;
    end
    good = ~isnan(v);
    if sum(good) < 2
        a = NaN;
    else
        a = trapz(t(good), v(good));
    end
end

function lat = fractionalPeakLatency(seg, segTimes, polarity, fraction)
%FRACTIONALPEAKLATENCY  Time at which the waveform first reaches FRACTION
%   of its own peak, searching BACKWARDS from the peak (the rising edge),
%   which is what makes it less biased by noise than peak latency itself.
    lat = NaN;
    s = peakIndex(seg, polarity);
    if isnan(s) || isnan(fraction)
        return;
    end
    target = seg(s) * fraction;
    if startsWith(polarity, 'neg')
        hit = find(seg(1:s) > target, 1, 'last');
    else
        hit = find(seg(1:s) < target, 1, 'last');
    end
    if isempty(hit)
        lat = segTimes(1);
    elseif hit >= s
        lat = segTimes(s);
    else
        lat = interpCrossing(segTimes, seg, hit, target);
    end
end

function lat = fractionalAreaLatency(seg, segTimes, fraction)
%FRACTIONALAREALATENCY  Time by which FRACTION of the window's total area
%   has accumulated. Uses the rectified area, so a waveform straddling zero
%   cannot produce a running total that goes backwards.
    lat = NaN;
    v = abs(seg);
    good = ~isnan(v);
    if sum(good) < 2 || isnan(fraction)
        return;
    end
    t = segTimes(good);
    v = v(good);
    running = cumtrapz(t, v);
    total = running(end);
    if total <= 0
        return;
    end
    target = total * fraction;
    hit = find(running >= target, 1, 'first');
    if isempty(hit)
        lat = t(end);
    elseif hit == 1
        lat = t(1);
    else
        span = running(hit) - running(hit - 1);
        if span <= 0
            lat = t(hit);
        else
            lat = t(hit - 1) + (t(hit) - t(hit - 1)) * (target - running(hit - 1)) / span;
        end
    end
end

function t = interpCrossing(segTimes, seg, hit, target)
%INTERPCROSSING  Linear interpolation of the crossing time between sample
%   HIT and HIT+1, so the latency is not quantised to the sampling grid.
    denom = seg(hit + 1) - seg(hit);
    if denom == 0
        t = segTimes(hit);
    else
        t = segTimes(hit) + (segTimes(hit + 1) - segTimes(hit)) * (target - seg(hit)) / denom;
    end
end

function [lo, hi] = windowRange(times, startMs, stopMs)
    lo = find(times >= startMs, 1, 'first');
    hi = find(times <= stopMs, 1, 'last');
    if isempty(lo) || isempty(hi) || hi < lo
        lo = []; hi = [];
    end
end

