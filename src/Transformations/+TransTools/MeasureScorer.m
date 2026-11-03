classdef MeasureScorer
%MEASURESCORER  How one window of ERP Measure scores one waveform: the one
%   implementation, used by Measure for its values and by erpScoreSME for the
%   standard error of those values.
%
%   SPEC = TransTools.MeasureScorer.prepare(WIN, TIMES) resolves a window
%   definition (Measure's windows, or the windows on a result) against a time
%   axis: which measure, the window's samples, its baseline's samples, and the
%   peak, area and fraction settings. It refuses a window that cannot be
%   measured, so a bad one fails with a clear message rather than a column of
%   NaN discovered later.
%
%   S = TransTools.MeasureScorer.score(WAVE, TIMES, SPEC) scores one waveform,
%   a row over TIMES, and returns S.amplitude, S.latency and S.area, NaN where
%   the measure does not give them. S = score(WAVE, TIMES, SPEC, PEAK) uses
%   sample PEAK as the peak, for a peak found on a reference channel.
%
%   ONE IMPLEMENTATION BECAUSE TWO DRIFTED. The SME of a score has to be the
%   standard error of that score (Luck et al., 2021), on the same window and
%   scoring procedure (Zhang & Luck, 2023). erpScoreSME used to have its own
%   narrow copy of this, which over time took the window by a different rule,
%   ignored a window's baseline, its local peaks, its peak-locked band and its
%   area mode, and read an unreachable fractional peak as the window's start
%   where Measure says NaN: 5.0 against Measure's 266 on a peak-band area.
%
%   See also MEASURE, ERPSCORESME, TRANSTOOLS.WINDOWSAMPLES.
    methods (Static)
        function spec = prepare(win, times)
            requested = lower(strtrim(char(string(win.measure))));
            spec.width = winWidth(win);
            spec.localPoints = winLocalPoints(win);
            spec.fraction = winFraction(win);
            spec.areaMode = winAreaMode(win);
            spec.polarity = win.polarity;
            spec.negative = strcmpi(win.polarity, 'Negative');
            [spec.measure, spec.useBand] = resolveMeasureKind(requested, spec.width);
            validateMeasureParameters(spec.measure, spec.useBand, spec.width, spec.fraction, win);
            if ~any(strcmp(spec.measure, {'mean amplitude', 'area', 'peak', ...
                    'fractional peak latency', 'fractional area latency'}))
                throw(MException('Alakazam:Measure', sprintf( ...
                    'Window "%s" has a measure type ("%s") that I don''t recognise.', ...
                    win.label, char(string(win.measure)))));
            end
            spec.needsPeak = strcmp(spec.measure, 'peak') ...
                || strcmp(spec.measure, 'fractional peak latency') ...
                || (strcmp(spec.measure, 'area') && spec.useBand);

            [spec.lo, spec.hi] = windowSampleRange(times, win.start, win.stop);
            spec.winTimes = reshape(times(spec.lo:spec.hi), 1, []);

            spec.baseLo = [];
            spec.baseHi = [];
            spec.baseline = winBaseline(win);
            if ~isempty(spec.baseline)
                [spec.baseLo, spec.baseHi] = windowSampleRange(times, spec.baseline(1), spec.baseline(2));
            end
        end

        function s = score(wave, times, spec, peak)
            s = struct('amplitude', NaN, 'latency', NaN, 'area', NaN);
            wave = reshape(wave, 1, []);

            % The window's own baseline, subtracted before any measure, so
            % amplitude, area and the fractional latencies are all taken relative
            % to it (a DC offset inflates an integral most of all).
            if ~isempty(spec.baseLo)
                base = mean(wave(spec.baseLo:spec.baseHi), 'omitnan');
                if ~isnan(base)
                    wave = wave - base;
                end
            end

            segment = wave(spec.lo:spec.hi);
            if spec.needsPeak && nargin < 4
                peak = TransTools.MeasureScorer.findPeak(segment, spec);
            end

            switch spec.measure
                case 'mean amplitude'
                    s.amplitude = mean(segment, 'omitnan');

                case 'area'
                    if spec.useBand
                        if isnan(peak); return; end
                        s.amplitude = wave(peak);
                        s.latency   = times(peak);
                        s.area      = bandArea(times, wave, times(peak), spec.width, spec.areaMode);
                    else
                        s.area = areaOf(spec.winTimes, segment, spec.areaMode);
                    end

                case 'peak'
                    if isnan(peak); return; end
                    s.amplitude = wave(peak);
                    s.latency   = times(peak);

                case 'fractional peak latency'
                    if isnan(peak); return; end
                    s.latency = fractionalPeakLatency(segment, spec.winTimes, spec.negative, ...
                        peak - spec.lo + 1, spec.fraction);

                case 'fractional area latency'
                    s.latency = fractionalAreaLatency(segment, spec.winTimes, spec.fraction, spec.areaMode);
            end
        end

        function s = findPeak(windowData, spec)
        %FINDPEAK  The absolute sample index (into the full recording, not the
        %   window-relative slice WINDOWDATA) of the window's peak by polarity.
        %   With localPoints >= 1 it returns the most extreme LOCAL peak, a
        %   sample at least as extreme as its localPoints neighbours on each side,
        %   which avoids picking a window-edge sample or a lone noise spike the
        %   way the plain extreme can (ERPLAB's "local peak" / Analyzer's "local
        %   maximum"); if the window has no such local peak it falls back to the
        %   absolute extreme, matching both tools' own fallback. localPoints == 0
        %   is the absolute extreme outright. NaN if every sample is NaN (e.g. an
        %   unresolved combo bin Average.m left as NaN): max/min on an all-NaN
        %   vector return NaN with idx == 1, which would otherwise look like a
        %   real match at the window's first sample.
            windowData = reshape(windowData, 1, []);
            if spec.localPoints >= 1
                localIdx = findLocalPeak(windowData, spec.negative, spec.localPoints);
                if ~isnan(localIdx)
                    s = spec.lo + localIdx - 1;
                    return;
                end
            end
            if spec.negative
                [ext, idx] = min(windowData);
            else
                [ext, idx] = max(windowData);
            end
            if isnan(ext)
                s = NaN;
            else
                s = spec.lo + idx - 1;
            end
        end
    end
end

% ======================================================================= %
function [measure, useBand] = resolveMeasureKind(requested, width)
%RESOLVEMEASUREKIND  The computation a requested measure name asks for.
%
%   Folds the pre-unification names into the one Area measure:
%     Integral  -> Area over the whole window (signed).
%     Peak Area -> Area over a peak-locked band (signed).
%
%   Kept so that saved templates, tree nodes and .alm files from before the
%   unification still replay. Otherwise Area's scope is set by its Width
%   (0 or blank = the whole window, >0 = a peak-locked band that wide).
%
%   THE ONLY PLACE A MEASURE NAME IS TRANSLATED. Everything downstream sees
%   the resolved name and nothing re-derives it, which is what keeps the
%   translation checkable: one function to read, rather than a rewrite here
%   and assumptions about it scattered over the next hundred lines.
    forceBand = [];
    measure = requested;
    if strcmp(requested, 'integral')
        measure = 'area'; forceBand = false;
    elseif strcmp(requested, 'peak area')
        measure = 'area'; forceBand = true;
    end

    useBand = false;
    if strcmp(measure, 'area')
        if ~isempty(forceBand)
            useBand = forceBand;
        else
            useBand = ~isnan(width) && width > 0;
        end
    end
end

function validateMeasureParameters(measure, useBand, width, fraction, win)
%VALIDATEMEASUREPARAMETERS  Refuse a window definition that cannot be
%   measured, up front, so a bad one fails with a clear message rather than
%   a column of NaN discovered later.
%
%   Reports win.measure, not the resolved name: a user who chose "Peak
%   Area" should not be told about "area".
    if strcmp(measure, 'area') && useBand && (isnan(width) || width <= 0)
        throw(MException('Alakazam:Measure', sprintf( ...
            'Window "%s" is set up as a peak-band Area measure, but has no positive Width (ms) to integrate over. Could you add one?', win.label)));
    end
    if any(strcmp(measure, {'fractional peak latency', 'fractional area latency'})) ...
            && (isnan(fraction) || fraction <= 0 || fraction >= 1)
        throw(MException('Alakazam:Measure', sprintf( ...
            'Window "%s" is a %s measure, but is missing a Fraction strictly between 0 and 1. Would you set one?', ...
            win.label, char(string(win.measure)))));
    end
end

function w = winWidth(win)
%WINWIDTH  A window's Peak Area band width (ms) as a numeric scalar, or
%   NaN if absent/empty/non-numeric. Tolerant of a stored window that
%   predates the Width field, or one whose width is only meaningful for a
%   Peak Area measure and was left blank for the others.
    if isfield(win, 'width') && ~isempty(win.width) && isnumeric(win.width)
        w = double(win.width);
    else
        w = NaN;
    end
end

function n = winLocalPoints(win)
%WINLOCALPOINTS  A window's local-peak neighbourhood as a non-negative
%   integer (0 = absolute extreme; the default and the behaviour of every
%   window saved before this field existed).
    if isfield(win, 'localPoints') && ~isempty(win.localPoints) && isnumeric(win.localPoints)
        n = max(0, round(double(win.localPoints)));
    else
        n = 0;
    end
end

function f = winFraction(win)
%WINFRACTION  A window's fractional-latency fraction (0..1) as a numeric
%   scalar, or NaN if absent/empty/non-numeric.
    if isfield(win, 'fraction') && ~isempty(win.fraction) && isnumeric(win.fraction)
        f = double(win.fraction);
    else
        f = NaN;
    end
end

function mode = winAreaMode(win)
%WINAREAMODE  An Area window's integration mode: 'signed' (numerical
%   integration, negatives subtract), 'rectified' (|v|), 'positive' (only
%   the part above 0) or 'negative' (only the part below 0). Defaults to
%   'signed', which is also what the old Integral / Peak Area measures
%   (folded into Area) always did.
    mode = 'signed';
    if isfield(win, 'areaMode') && ~isempty(win.areaMode) && (ischar(win.areaMode) || isstring(win.areaMode))
        cand = lower(strtrim(char(string(win.areaMode))));
        if ismember(cand, {'signed', 'rectified', 'positive', 'negative'})
            mode = cand;
        end
    end
end

function base = winBaseline(win)
%WINBASELINE  A window's baseline interval as [start stop] ms (start <=
%   stop), or [] when there is none. Accepts a 2-element numeric array or
%   the raw "start stop" / "start, stop" text the dialog stores; anything
%   else (blank, a single number, junk) means "no baseline".
    base = [];
    if ~isfield(win, 'baseline') || isempty(win.baseline)
        return;
    end
    b = win.baseline;
    if isnumeric(b) && numel(b) == 2
        base = double(reshape(b, 1, 2));
    else
        txt = strtrim(char(string(b)));
        if isempty(txt)
            return;
        end
        nums = str2double(strtrim(strsplit(txt, {',', ' '})));
        nums = nums(~isnan(nums));
        if numel(nums) == 2
            base = nums(:)';
        end
    end
    if ~isempty(base) && base(1) > base(2)
        base = base([2 1]);
    end
end

function a = bandArea(times, wave, centreMs, width, mode)
%BANDAREA  Area (uV.ms, per MODE) of the full-length WAVE (one bin's
%   virtual channel, over TIMES) across a band WIDTH ms wide centred on
%   CENTREMS. Takes the whole waveform (not a channel/bin index) because
%   the band can extend past the search window and WAVE may be a pooled
%   ROI mean. The band bounds snap to real samples the nearest-sample way
%   the search window does, so a band running off the epoch edge clamps
%   rather than erroring. Integration/NaN handling is areaOf's.
    half = width / 2;
    [lo, hi] = windowSampleRange(times, centreMs - half, centreMs + half);
    a = areaOf(times(lo:hi), wave(lo:hi), mode);
end

function a = areaOf(t, y, mode)
%AREAOF  Trapezoidal area of Y over T, by MODE: 'signed' (as-is, negatives
%   subtract), 'rectified' (|y|), 'positive' (max(y,0)) or 'negative'
%   (min(y,0)). NaN samples are dropped and the rest integrated at their
%   own times; fewer than two real samples has no area (NaN).
    t = reshape(t, 1, []);
    y = reshape(y, 1, []);
    valid = ~isnan(y);
    if nnz(valid) < 2
        a = NaN;
        return;
    end
    t = t(valid);
    y = y(valid);
    switch mode
        case 'rectified'
            y = abs(y);
        case 'positive'
            y = max(y, 0);
        case 'negative'
            y = min(y, 0);
        otherwise
            % 'signed': leave y as-is.
    end
    a = trapz(t, y);
end

function idx = findLocalPeak(w, neg, n)
%FINDLOCALPEAK  Window-relative index of the most extreme local peak in W:
%   a sample at least as extreme (by NEG) as the N samples on each side of
%   it. NaN if there is none (window too short, or no interior extremum) --
%   the caller then falls back to the absolute extreme. NaN neighbours do
%   not disqualify a candidate (a few blanked samples should not hide a
%   real local peak).
    idx = NaN;
    bestVal = [];
    L = numel(w);
    for i = (1 + n):(L - n)
        v = w(i);
        if isnan(v)
            continue;
        end
        seg = w(i - n : i + n);
        if neg
            isPeak = all(v <= seg | isnan(seg));
            better = isempty(bestVal) || v < bestVal;
        else
            isPeak = all(v >= seg | isnan(seg));
            better = isempty(bestVal) || v > bestVal;
        end
        if isPeak && better
            bestVal = v;
            idx = i;
        end
    end
end

function latMs = fractionalPeakLatency(windowData, winTimes, neg, peakLocalIdx, fraction)
%FRACTIONALPEAKLATENCY  The (interpolated) latency at which the waveform
%   rises through FRACTION x its peak amplitude on the onset side --
%   searching back from the peak (PEAKLOCALIDX, window-relative) to the
%   last crossing of the threshold. More robust than raw peak latency
%   (ERPLAB's "fractional peak latency"). NaN if the peak is NaN or the
%   waveform never drops below threshold within the window before the peak
%   (window opened too late: widen its Start).
    w = reshape(windowData, 1, []);
    if peakLocalIdx < 1 || peakLocalIdx > numel(w) || isnan(w(peakLocalIdx))
        latMs = NaN;
        return;
    end
    thr = fraction * w(peakLocalIdx);
    latMs = NaN;
    for i = peakLocalIdx : -1 : 2
        if neg
            crossed = w(i) <= thr && w(i - 1) > thr;
        else
            crossed = w(i) >= thr && w(i - 1) < thr;
        end
        if crossed
            latMs = interpCrossing(winTimes(i - 1), w(i - 1), winTimes(i), w(i), thr);
            return;
        end
    end
end

function latMs = fractionalAreaLatency(windowData, winTimes, fraction, mode)
%FRACTIONALAREALATENCY  The (interpolated) latency that divides the
%   window's cumulative area at FRACTION (e.g. 0.5 = 50% area latency, the
%   robust onset/timing measure). NaN if fewer than two real samples or the
%   total area is zero. NaN samples are dropped first.
%
%   MODE is the window's own .areaMode, applied to the waveform before
%   integrating exactly as areaOf does it: 'signed' (as-is, negatives
%   subtract), 'rectified' (|y|), 'positive' (max(y,0)) or 'negative'
%   (min(y,0)). These are ERPLAB's four fractional-area measures,
%   fninteglat, fareatlat, fareaplat and fareanlat respectively, and
%   Alakazam used to ignore MODE here and always integrate the signed area,
%   which silently gave the 'signed' answer to a window asking for any of
%   the other three.
%
%   WHICH MODE TO ASK FOR IS NOT COSMETIC. Only the signed cumulative area
%   can be non-monotonic, and when it is, the fraction is genuinely
%   ambiguous: a window whose positive and negative areas are comparable
%   crosses its own 50% point more than once. This returns the FIRST
%   crossing, which is the earliest latency at which the fraction is
%   reached and the only one that answers "when did this component get
%   halfway". (ERPLAB's fninteglat searches forward instead and reports the
%   window edge in that situation, which is how the disagreement in
%   Docs/luck.md was found.) The other three modes integrate a
%   single-signed quantity, so their cumulative area is monotonic and the
%   crossing is unique, which is the reason to prefer one of them when a
%   window genuinely spans components of both polarities.
    if nargin < 4 || isempty(mode)
        mode = 'signed';
    end
    y = reshape(windowData, 1, []);
    t = reshape(winTimes, 1, []);
    valid = ~isnan(y);
    if nnz(valid) < 2
        latMs = NaN;
        return;
    end
    y = y(valid);
    t = t(valid);
    switch mode
        case 'rectified'
            y = abs(y);
        case 'positive'
            y = max(y, 0);
        case 'negative'
            y = min(y, 0);
        otherwise
            % 'signed': leave y as-is.
    end

    segArea = (y(1:end - 1) + y(2:end)) / 2 .* diff(t);   % per-interval trapezoid
    cum = [0, cumsum(segArea)];                            % cumulative area at each sample
    total = cum(end);
    if total == 0
        latMs = NaN;
        return;
    end
    target = fraction * total;

    % First interval whose cumulative area brackets the target.
    k = find((cum(1:end - 1) - target) .* (cum(2:end) - target) <= 0, 1);
    if isempty(k)
        latMs = NaN;
        return;
    end
    latMs = interpCrossing(t(k), cum(k), t(k + 1), cum(k + 1), target);
end

function tCross = interpCrossing(t1, v1, t2, v2, thr)
%INTERPCROSSING  Linear-interpolated time between (T1,V1) and (T2,V2) at
%   which the value equals THR. Falls back to T1 if the two values are
%   equal (a flat segment exactly at the threshold).
    if v2 == v1
        tCross = t1;
    else
        tCross = t1 + (thr - v1) / (v2 - v1) * (t2 - t1);
    end
end

function [loIdx, hiIdx] = windowSampleRange(times, startMs, stopMs)
%WINDOWSAMPLERANGE  The [loIdx, hiIdx] sample range nearest [STARTMS,
%   STOPMS] in TIMES: FieldTrip's rule for a latency range, which is also
%   ERPLAB's (TransTools.WindowSamples). A window edge a few ms outside the
%   data clamps to the edge sample; a window wholly outside is refused,
%   where it used to be measured on the single edge sample.
    [loIdx, hiIdx] = TransTools.WindowSamples(times, min(startMs, stopMs), ...
        max(startMs, stopMs), 'Alakazam:Measure', 'measurement window');
end
