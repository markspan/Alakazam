function [EEG, options] = Measure(input, opts)
%% Measure  Quantify ERP components (mean amplitude, peak amplitude, peak
%   latency) in named time windows, for group-level statistics.
%
%   Works on an averaged dataset (a subject Average or a Grand Average),
%   the same DataFormat=='Averaged' contract ScalpDistribution.m checks:
%   EEG.data is channels x samples[ x bins]. Reads a set of named
%   measurement windows (see MeasureDialog) and, for each window x bin x
%   selected channel, computes one of:
%     * Mean Amplitude -- the NaN-tolerant mean of the window's samples.
%     * Peak -- both the extreme (by polarity) amplitude in the window and
%       its latency (ms). With a reference channel set, the latency is
%       found on that one channel only, then that same sample is read on
%       every other selected channel (Analyzer's "search peak in a
%       reference channel" mode); without one, every channel is searched
%       independently.
%     * Area -- the area (uV.ms) over either the whole window (.width 0 or
%       blank) or a peak-locked band .width ms wide centred on the located
%       peak (.width > 0). .areaMode picks how: 'signed' (numerical
%       integration, negatives subtract), 'rectified' (|v|), 'positive'
%       (only above 0) or 'negative' (only below 0). A peak-band Area also
%       reports the peak's amplitude and latency, and honours a reference
%       channel the same way Peak does. (The old Integral = signed whole-
%       window Area; the old Peak Area = signed peak-band Area; both still
%       replay, folded into Area.)
%     * Fractional Peak Latency -- the latency at which the waveform rises
%       through .fraction x its peak amplitude on the onset side (ERPLAB's
%       fractional peak latency), interpolated between samples.
%     * Fractional Area Latency -- the latency dividing the window's
%       cumulative signed area at .fraction (e.g. 0.5 = 50% area latency,
%       the robust onset measure), interpolated between samples.
%
%   The peak-locating measures (Peak, peak-band Area, Fractional Peak
%   Latency) honour .localPoints: 0 = the absolute extreme; >=1 = the most
%   extreme LOCAL peak (more extreme than that many neighbours each side),
%   falling back to the absolute extreme if the window has none.
%
%   Every measure honours an optional .baseline interval: each channel's
%   own mean over it is subtracted before the measure is taken (matters
%   most for the area measures, which a DC offset inflates).
%
%   Optionally derives new channels first from a block of "let" statements
%   (options.derivations, e.g. "let LRP = C3 - C4"): each is appended to
%   EEG.data/EEG.chanlocs (marked .type = 'derived') so it can be measured
%   here AND shows up downstream on the ERP plot and in grand averages, and
%   can be named in any window's Channels/Reference cell. A difference
%   channel has no scalp position, so ScalpDistribution drops it from the
%   head map automatically. See measureDerivations.m. Apart from those
%   opt-in derived channels, EEG.data/EEG.times/etc. pass through unchanged.
%
%   Adds EEG.measurements: a 1xN cell array (N = number of windows, never a
%   struct array -- see the note on WINDOWS below) of scalar structs:
%       .label, .start, .stop, .measure, .polarity, .width, .localPoints,
%       .fraction, .areaMode, .baseline, .refChannel, .channels
%           -- the window definition, carried through so the CSV export
%              can label its rows (see exportMeasurementsCSV.m). .width is
%              the Area band width / scope switch, .fraction the fractional
%              latency (0..1), .localPoints the local-peak neighbourhood
%              (0 = absolute), .baseline a "[start stop] ms" pre-window (or
%              blank). The OUTPUT struct additionally carries .areaMode and
%              .scope ('band'/'window', or '' for non-area) so the exporter
%              knows how to label an Area row; .channels on output is the
%              resolved list of output-channel labels (a pool shows as
%              "{Pz+POz+CPz}") -- see measureChannelSpecs.
%       .amplitude, .latency, .area
%           -- numel(.channels) x nBins numeric matrices, each filled only
%              for the measures it applies to and NaN elsewhere: .amplitude
%              for Mean Amplitude, Peak and peak-band Area; .latency for
%              Peak, peak-band Area and the two fractional-latency measures;
%              .area for Area. The CSV exporter picks the right field(s) per
%              window from .measure/.areaMode/.scope.
%
%   Signature (Alakazam transformation contract):
%     [EEG, options] = Measure(input)        % interactive: open MeasureDialog
%     [EEG, options] = Measure(input, opts)  % replay: opts.windows is a
%                                             %   stored window-definition
%                                             %   cell array
%
%   WINDOWS (both MeasureDialog's return value and options.windows) is
%   deliberately a 1xN CELL array of scalar structs, never a struct array:
%   jsonencode collapses a 1-element struct array embedded in another
%   struct's field to a bare JSON object instead of a single-element
%   array (the same gotcha documented in WorkSpaceTree.buildData and
%   worked around in Alakazam.onSaveTemplate), which would silently break
%   Save Template/Apply Template for a one-window Measure step. A cell
%   array sidesteps it regardless of count, so Measure never needs a
%   templateParams-style special case. Each window's .channels is, for
%   the same reason, always a cellstr (never a bare char for a single
%   channel) -- see MeasureDialog and resolveChannelList below.
%
%   See also: MEASUREDIALOG, AVERAGE, SCALPDISTRIBUTION, EXPORTMEASUREMENTSCSV.

%% Guard input
if nargin < 1
    throw(MException('Alakazam:Measure', ...
        'Problem in Measure: needs a dataset to run on, and none was given.'));
end
if nargin < 2
    opts = 'Init';
end

EEG = input;

if ~isfield(input, 'DataFormat') || ~strcmpi(input.DataFormat, 'Averaged')
    throw(MException('Alakazam:Measure', sprintf([ ...
        'Problem in Measure: only works on an averaged ERP (a subject Average or a Grand ' ...
        'Average), not this dataset (DataFormat = "%s"). Run Average -- or Grand Average, ' ...
        'for a group result -- on it first.'], input.DataFormat)));
end

%% Mode: interactive (Init) or replay (stored options struct)
interactive = (ischar(opts) || isstring(opts)) && strcmpi(string(opts), "Init");

if interactive
    stored = TransformSettings.get('Measure');
    if isempty(stored) || ~isfield(stored, 'windows')
        priorWindows = {};
    else
        priorWindows = stored.windows;
    end
    priorDerivations = '';
    if isstruct(stored) && isfield(stored, 'derivations')
        priorDerivations = stored.derivations;
    end
    [windows, derivations] = MeasureDialog(input.chanlocs, priorWindows, priorDerivations);
    if isempty(windows)
        % Cancelled: nothing to persist and nothing to run -- see
        % TransformOptionsDialog's own header comment for why every
        % transformation using a dialog must return [] on Cancel.
        EEG = [];
        return;
    end
    options = struct('windows', {windows}, 'derivations', derivations);
    TransformSettings.set('Measure', options);
else
    if ~isstruct(opts) || ~isfield(opts, 'windows')
        throw(MException('Alakazam:Measure', ...
            ['Measure was asked to replay a previous run, but the stored settings it was ' ...
             'given do not look like ones Measure itself produced (no .windows field).']));
    end
    windows = opts.windows;
    options = opts;
    derivations = '';
    if isfield(opts, 'derivations')
        derivations = opts.derivations;
    end
end

if isempty(windows)
    throw(MException('Alakazam:Measure', ...
        ['No measurement windows are defined, so there is nothing for Measure to do. Add ' ...
         'at least one window (a name, a start/stop time, and a measure type).']));
end

%% Derived channels: evaluate any "let" statements and append them to EEG
% (channels x samples[ x bins]) before measuring, so a derivation like
% "let LRP = C3 - C4" is both measurable here and visible downstream (the
% ERP line plot, grand averages). measureDerivations is a no-op when the
% block is empty, and idempotent, so replay/Recalculate replaces rather
% than accumulates the derived channels. See measureDerivations.m.
EEG = measureDerivations(EEG, derivations);

%% Compute
allLabels = string({EEG.chanlocs.labels});
nBins = size(EEG.data, 3); % 1 for an unbinned average (2-D EEG.data)

measurements = cell(1, numel(windows));
for w = 1:numel(windows)
    measurements{w} = computeWindow(EEG, windows{w}, allLabels, nBins);
end
EEG.measurements = measurements;
end

% ======================================================================= %
%  Per-window computation
% ======================================================================= %
function m = computeWindow(EEG, win, allLabels, nBins)
%COMPUTEWINDOW  Compute one window's amplitude/latency/area matrices, per
%   channel x bin. Each of the three matrices is filled only for the
%   measures it applies to (see this file's own header) and left NaN
%   otherwise; the CSV exporter picks the right one(s) from .measure:
%     Mean Amplitude          -> amplitude
%     Peak                    -> amplitude, latency
%     Peak Area               -> amplitude, latency, area
%     Integral                -> area   (signed trapz over the window)
%     Fractional Peak Latency -> latency
%     Fractional Area Latency -> latency
    % Resolve the Channels field into one output "channel" per spec (a
    % single electrode, or a "{A+B+C}" pool), and build each spec's virtual
    % waveform V(c,:,b): the electrode itself, or the NaN-tolerant mean of
    % a pool's members. Every measure below then runs on V exactly as it
    % used to run on a single electrode -- pooling is just "measure the
    % averaged waveform", invisible to the rest of the maths.
    specs = measureChannelSpecs(win.channels, allLabels, win.label);
    nCh = numel(specs);
    nSamp = size(EEG.data, 2);
    V = nan(nCh, nSamp, nBins);
    for c = 1:nCh
        mem = specs(c).members;
        if isscalar(mem)
            V(c, :, :) = EEG.data(mem, :, :);
        else
            V(c, :, :) = mean(EEG.data(mem, :, :), 1, 'omitnan');
        end
    end

    [loIdx, hiIdx] = windowSampleRange(EEG.times, win.start, win.stop);
    winTimes = reshape(EEG.times(loIdx:hiIdx), 1, []);

    amplitude = nan(nCh, nBins);
    latency   = nan(nCh, nBins);
    area      = nan(nCh, nBins);

    width       = winWidth(win);
    localPoints = winLocalPoints(win);
    fraction    = winFraction(win);
    areaMode    = winAreaMode(win);
    measure     = lower(strtrim(char(string(win.measure))));

    % Fold the pre-unification names into the one Area measure:
    %   Integral  -> Area over the whole window (signed).
    %   Peak Area -> Area over a peak-locked band (signed).
    % Kept so saved templates / tree nodes and .alm files from before the
    % unification still replay. forceBand overrides the width-based scope
    % choice for these; otherwise Area's scope is set by its Width (0/blank
    % = whole window, >0 = a peak-locked band that wide).
    forceBand = [];
    if strcmp(measure, 'integral')
        measure = 'area'; forceBand = false;
    elseif strcmp(measure, 'peak area')
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

    % Measure-specific parameter validation, up front so a bad definition
    % fails with a clear message rather than a NaN column later.
    if strcmp(measure, 'area') && useBand && (isnan(width) || width <= 0)
        throw(MException('Alakazam:Measure', sprintf( ...
            'Window "%s" is a peak-band Area measure but has no positive Width (ms) to integrate over.', win.label)));
    end
    if any(strcmp(measure, {'fractional peak latency', 'fractional area latency'})) ...
            && (isnan(fraction) || fraction <= 0 || fraction >= 1)
        throw(MException('Alakazam:Measure', sprintf( ...
            'Window "%s" is a %s measure but has no Fraction strictly between 0 and 1.', ...
            win.label, char(string(win.measure)))));
    end

    % Optional per-window baseline: subtract each virtual channel's own mean
    % over the baseline interval before ANY measure, so amplitude, area and
    % the fractional latencies are all taken relative to it (matters most
    % for the area measures -- a DC offset inflates an integral). No-op when
    % the window has no baseline set.
    baseline = winBaseline(win);
    if ~isempty(baseline)
        [blo, bhi] = windowSampleRange(EEG.times, baseline(1), baseline(2));
        for c = 1:nCh
            for b = 1:nBins
                base = mean(V(c, blo:bhi, b), 'omitnan');
                if ~isnan(base)
                    V(c, :, b) = V(c, :, b) - base;
                end
            end
        end
    end

    % Locate the peak first for the measures that need one: Peak, a
    % peak-band Area, and Fractional Peak Latency. Peak and peak-band Area
    % may share the peak across channels via a reference channel (Analyzer's
    % "search peak in a reference channel" mode); Fractional Peak Latency is
    % always per-channel (each channel's rise to a fraction of its own
    % peak). localPoints picks absolute (0) vs local (>=1) extremum.
    needsPeak = strcmp(measure, 'peak') || strcmp(measure, 'fractional peak latency') ...
        || (strcmp(measure, 'area') && useBand);
    usesRef = ~isempty(win.refChannel) && (strcmp(measure, 'peak') || (strcmp(measure, 'area') && useBand));
    peakSample = nan(nCh, nBins);
    if needsPeak
        if usesRef
            refIdx = find(allLabels == string(win.refChannel), 1);
            if isempty(refIdx)
                throw(MException('Alakazam:Measure', sprintf( ...
                    'Window "%s" names a reference channel ("%s") that is not in this dataset.', ...
                    win.label, win.refChannel)));
            end
            for b = 1:nBins
                peakSample(:, b) = findPeakSample(EEG.data(refIdx, loIdx:hiIdx, b), win.polarity, loIdx, localPoints);
            end
        else
            for c = 1:nCh
                for b = 1:nBins
                    peakSample(c, b) = findPeakSample(V(c, loIdx:hiIdx, b), win.polarity, loIdx, localPoints);
                end
            end
        end
    end

    switch measure
        case 'mean amplitude'
            for c = 1:nCh
                for b = 1:nBins
                    amplitude(c, b) = mean(V(c, loIdx:hiIdx, b), 'omitnan');
                end
            end

        case 'area'
            if useBand
                for c = 1:nCh
                    for b = 1:nBins
                        s = peakSample(c, b);
                        if isnan(s); continue; end
                        amplitude(c, b) = V(c, s, b);
                        latency(c, b)   = EEG.times(s);
                        area(c, b)      = bandArea(EEG.times, V(c, :, b), EEG.times(s), width, areaMode);
                    end
                end
            else
                for c = 1:nCh
                    for b = 1:nBins
                        area(c, b) = areaOf(winTimes, V(c, loIdx:hiIdx, b), areaMode);
                    end
                end
            end

        case 'peak'
            for c = 1:nCh
                for b = 1:nBins
                    s = peakSample(c, b);
                    if isnan(s); continue; end
                    amplitude(c, b) = V(c, s, b);
                    latency(c, b)   = EEG.times(s);
                end
            end

        case 'fractional peak latency'
            for c = 1:nCh
                for b = 1:nBins
                    s = peakSample(c, b);
                    if isnan(s); continue; end
                    latency(c, b) = fractionalPeakLatency( ...
                        V(c, loIdx:hiIdx, b), winTimes, win.polarity, s - loIdx + 1, fraction);
                end
            end

        case 'fractional area latency'
            for c = 1:nCh
                for b = 1:nBins
                    latency(c, b) = fractionalAreaLatency(V(c, loIdx:hiIdx, b), winTimes, fraction);
                end
            end

        otherwise
            throw(MException('Alakazam:Measure', sprintf( ...
                'Window "%s" has an unknown measure type "%s".', win.label, char(string(win.measure)))));
    end

    if strcmp(measure, 'area')
        outMode = areaMode;
        if useBand; outScope = 'band'; else; outScope = 'window'; end
    else
        outMode = '';
        outScope = '';
    end

    m = struct('label', win.label, 'start', win.start, 'stop', win.stop, ...
        'measure', win.measure, 'polarity', win.polarity, 'width', width, ...
        'localPoints', localPoints, 'fraction', fraction, 'areaMode', outMode, ...
        'scope', outScope, 'refChannel', win.refChannel, 'channels', {{specs.label}}, ...
        'amplitude', amplitude, 'latency', latency, 'area', area);
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
%WINAREAMODE  An Area window's integration mode -- 'signed' (numerical
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
            % 'signed' -- leave y as-is.
    end
    a = trapz(t, y);
end

function s = findPeakSample(windowData, polarity, loIdx, localPoints)
%FINDPEAKSAMPLE  The absolute sample index (into the full recording, not
%   the window-relative slice WINDOWDATA) of the window's peak by POLARITY.
%   With LOCALPOINTS >= 1 it returns the most extreme LOCAL peak -- a
%   sample at least as extreme as its LOCALPOINTS neighbours on each side
%   -- which avoids picking a window-edge sample or a lone noise spike the
%   way the plain extreme can (ERPLAB's "local peak" / Analyzer's "local
%   maximum"); if the window has no such local peak it falls back to the
%   absolute extreme, matching both tools' own fallback. LOCALPOINTS == 0
%   is the absolute extreme outright. NaN if every sample is NaN (e.g. an
%   unresolved combo bin Average.m left as NaN): max/min on an all-NaN
%   vector return NaN with idx == 1, which would otherwise look like a
%   real match at the window's first sample.
    windowData = reshape(windowData, 1, []);
    neg = strcmpi(polarity, 'Negative');

    if localPoints >= 1
        localIdx = findLocalPeak(windowData, neg, localPoints);
        if ~isnan(localIdx)
            s = loIdx + localIdx - 1;
            return;
        end
    end

    if neg
        [ext, idx] = min(windowData);
    else
        [ext, idx] = max(windowData);
    end
    if isnan(ext)
        s = NaN;
    else
        s = loIdx + idx - 1;
    end
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

function latMs = fractionalPeakLatency(windowData, winTimes, polarity, peakLocalIdx, fraction)
%FRACTIONALPEAKLATENCY  The (interpolated) latency at which the waveform
%   rises through FRACTION x its peak amplitude on the onset side --
%   searching back from the peak (PEAKLOCALIDX, window-relative) to the
%   last crossing of the threshold. More robust than raw peak latency
%   (ERPLAB's "fractional peak latency"). NaN if the peak is NaN or the
%   waveform never drops below threshold within the window before the peak
%   (window opened too late -- widen its Start).
    w = reshape(windowData, 1, []);
    if peakLocalIdx < 1 || peakLocalIdx > numel(w) || isnan(w(peakLocalIdx))
        latMs = NaN;
        return;
    end
    thr = fraction * w(peakLocalIdx);
    neg = strcmpi(polarity, 'Negative');
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

function latMs = fractionalAreaLatency(windowData, winTimes, fraction)
%FRACTIONALAREALATENCY  The (interpolated) latency that divides the
%   window's cumulative signed area at FRACTION (e.g. 0.5 = 50% area
%   latency, the robust onset/timing measure). NaN if fewer than two real
%   samples or the total area is zero (a single-signed component window is
%   the intended case; a window whose positive and negative areas cancel
%   makes the fraction ill-defined). NaN samples are dropped first.
    y = reshape(windowData, 1, []);
    t = reshape(winTimes, 1, []);
    valid = ~isnan(y);
    if nnz(valid) < 2
        latMs = NaN;
        return;
    end
    y = y(valid);
    t = t(valid);

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
%   STOPMS] in TIMES -- nearest-sample snapping (the same t -> sample
%   lookup ScalpDistributionView.redraw uses), not a range search, so a
%   window edge a few ms outside the true data range still clamps to the
%   nearest real edge sample instead of returning an empty range.
    [~, loIdx] = min(abs(times - startMs));
    [~, hiIdx] = min(abs(times - stopMs));
    if loIdx > hiIdx
        [loIdx, hiIdx] = deal(hiIdx, loIdx);
    end
end
