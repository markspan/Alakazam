function [onsets, info] = detectDiodeOnsets(signal, srate, opts)
%DETECTDIODEONSETS  Stimulus onsets from a photodiode channel.
%   [ONSETS, INFO] = detectDiodeOnsets(SIGNAL, SRATE, OPTS) returns the
%   sample indices where the diode goes high, and INFO describing what was
%   decided: the threshold used, how separable the two states were, and why
%   nothing was returned when nothing was.
%
%   OPTS fields, all optional:
%     SmoothMs      window for the moving average       (default 25)
%     Threshold     level, or NaN to choose one         (default NaN)
%     MinDurationMs how long high must last             (default 20)
%     MinGapMs      minimum spacing between onsets      (default 100)
%     MinSeparation how bimodal the signal must be      (default 3)
%     Edge          'leading' | 'trailing'              (default 'leading')
%
%   THE HARD PART IS NOT FINDING A STEP, IT IS NOT FIRING ON FLICKER.
%   Measured from real recordings on this lab's rig, a photodiode channel
%   with NO patch presented still swings about 2400 units peak to peak at
%   50 Hz, continuously, around a baseline near 5000. A plain threshold at
%   the midpoint of that signal produces fifty onsets a second forever, and
%   it looks like it is working. Two things prevent that:
%
%   SMOOTHING FIRST. A moving average over a window longer than the flicker
%   period removes an oscillation about a stable mean while leaving a
%   sustained level change almost intact. 25 ms comfortably covers 50 Hz
%   (20 ms) and 60 Hz (17 ms) mains.
%
%   THEN A SEPARABILITY TEST, which is what actually makes "no patches
%   here" a possible answer. After smoothing, a real patch signal is
%   strongly bimodal: a tight baseline and a tight high state, far apart. A
%   flickering channel with no patch is unimodal, and splitting it at its
%   own midpoint gives two halves of one distribution whose means differ by
%   little relative to their spread. Requiring the separation to exceed
%   MinSeparation makes the detector able to say "there is nothing here",
%   which a thresholding detector never can.
%
%   Verified against real recordings that contain no patches at all: the
%   correct answer there is zero onsets, and it is the answer this returns.
%
%   See also PHOTODIODE, DIODETRIGGERDELAY.
    if nargin < 3; opts = struct(); end
    o = defaults(opts);

    onsets = [];
    info = struct('threshold', NaN, 'separation', NaN, 'reason', '', ...
        'low', NaN, 'high', NaN, 'nSamples', numel(signal));

    signal = double(signal(:))';
    if numel(signal) < 3 || ~isfinite(srate) || srate <= 0
        info.reason = 'The signal or the sampling rate is unusable.';
        return;
    end

    smoothed = movingMean(signal, max(1, round(o.SmoothMs * srate / 1000)));

    lo = TransTools.Percentile(smoothed, 5);
    hi = TransTools.Percentile(smoothed, 95);
    info.low = lo;
    info.high = hi;

    % A QUARTER OF THE WAY UP, NOT HALF. The level's job is to say where the
    % high state begins, and the high state begins at the foot of the edge,
    % not at its middle: a display ramps, and the midpoint of the range sits
    % part way up that ramp by construction.
    %
    % It can be this low safely because it is applied to the SMOOTHED
    % channel, where the mains flicker that dominates a raw diode trace has
    % already gone. On the raw signal a quarter of the range would sit
    % inside the flicker on this lab's rig; on the smoothed one the baseline
    % is a line rather than a band.
    %
    % A quarter and not a tenth because "low" is the 5th percentile of a
    % channel that still drifts, so the bottom of the range is itself only
    % approximate, and a level too close to it starts tracking that drift.
    if isnan(o.Threshold)
        level = lo + 0.25 * (hi - lo);
    else
        level = o.Threshold;
    end
    info.threshold = level;

    % BIMODALITY IS JUDGED AT THE MIDPOINT, wherever the detection level
    % sits. The midpoint is the valley between the two states, and the
    % separability metric only means what it says when the split is there:
    % splitting a quarter of the way up puts baseline samples into the high
    % group and dilutes the very separation being measured. Measured, on a
    % clean recording of 30 patches, moving the split from the midpoint to a
    % quarter took the separability from 3.43 to 2.88 and the detector then
    % refused its own patches as "not two states".
    %
    % So the two levels do two jobs and are computed separately: this one
    % decides WHETHER there is a patch signal at all, and the lower one
    % above decides WHERE each patch starts.
    below = smoothed < level;
    info.separation = separability(smoothed, smoothed < (lo + hi) / 2);

    % A chosen threshold is the analyst overriding this judgement, so the
    % separability test only gates the automatic case.
    if isnan(o.Threshold) && info.separation < o.MinSeparation
        info.reason = sprintf(['The channel does not look like it has two states ' ...
            '(separability %.1f, needs %.1f). Either no patch was presented, or the ' ...
            'diode saw nothing. Set a threshold by hand to override.'], ...
            info.separation, o.MinSeparation);
        return;
    end

    high = ~below;
    if strcmpi(o.Edge, 'trailing')
        high = below;                       % falling edges are rising edges of the inverse
    end

    onsets = risingEdges(high);
    onsets = holdFor(onsets, high, round(o.MinDurationMs * srate / 1000));
    onsets = separated(onsets, round(o.MinGapMs * srate / 1000));

    % SMOOTHING DECIDES THAT THERE IS AN EDGE; THE RAW SIGNAL DECIDES WHEN.
    % Measured: without this step every onset landed about 7 ms early and
    % consistently so. A moving average turns a step into a ramp, and a
    % threshold set from whole-recording percentiles sits low on that ramp
    % when patches are brief, so it is crossed before the patch begins. A
    % fixed 7 ms bias is fatal for the one thing this transformation is
    % for: an instrument for measuring display delay must not have a delay
    % of its own. So each onset is re-timed against the unsmoothed channel,
    % using levels taken from just before and just after it.
    %
    % AND IT IS TIMED TO THE FOOT OF THE EDGE, not its half-height: the
    % display began to change when the trace left its baseline, and the climb
    % from there to half height is the panel's own pixel response. See
    % refineOnsets, which says what that costs in repeatability.
    onsets = refineOnsets(onsets, signal, ...
        round(o.SmoothMs * srate / 1000), strcmpi(o.Edge, 'trailing'));

    if isempty(onsets) && isempty(info.reason)
        info.reason = ['The two states are separable, but no transition lasted long ' ...
            'enough to count. Try a shorter minimum duration.'];
    end
end

% ======================================================================= %
function o = defaults(opts)
    o = struct('SmoothMs', 25, 'Threshold', NaN, 'MinDurationMs', 20, ...
        'MinGapMs', 100, 'MinSeparation', 3, 'Edge', 'leading');
    for f = fieldnames(o)'
        if isfield(opts, f{1}) && ~isempty(opts.(f{1}))
            o.(f{1}) = opts.(f{1});
        end
    end
end

function y = movingMean(x, w)
%MOVINGMEAN  Centred moving average, edges included rather than trimmed:
%   a patch at the very start of a recording is still a patch.
    if w <= 1
        y = x;
        return;
    end
    y = movmean(x, w, 'Endpoints', 'shrink');
end

function s = separability(smoothed, below)
%SEPARABILITY  How far apart the two putative states are, in units of their
%   own spread. A ratio rather than a difference, so it does not depend on
%   the diode's gain: one rig reads 5000 to 75000 and another 0 to 5, and
%   both are equally bimodal.
    a = smoothed(below);
    b = smoothed(~below);
    if isempty(a) || isempty(b)
        s = 0;
        return;
    end
    spread = std(a) + std(b);
    if spread < eps
        s = Inf;                            % two perfectly flat states
        return;
    end
    s = abs(mean(b) - mean(a)) / spread;
end

function idx = risingEdges(high)
    idx = find(high(2:end) & ~high(1:end-1)) + 1;
    if ~isempty(high) && high(1)
        idx = [1, idx];                     % already high at the first sample
    end
end

function idx = holdFor(idx, high, n)
%HOLDFOR  Keep only onsets whose high state lasts at least N samples. This
%   is what rejects a single-sample artefact: a real recording here carried
%   one isolated 15x excursion matching no trigger, and a patch that lasts
%   one millisecond is not a patch.
    if n <= 1 || isempty(idx)
        return;
    end
    keep = false(1, numel(idx));
    for k = 1:numel(idx)
        stop = min(numel(high), idx(k) + n - 1);
        keep(k) = all(high(idx(k):stop));
    end
    idx = idx(keep);
end

function idx = separated(idx, n)
%SEPARATED  Enforce a minimum gap, keeping the first of any cluster. An
%   imperfect edge can cross the threshold several times on its way up.
    if n <= 1 || numel(idx) < 2
        return;
    end
    keep = idx(1);
    for k = 2:numel(idx)
        if idx(k) - keep(end) >= n
            keep(end + 1) = idx(k); %#ok<AGROW>
        end
    end
    idx = keep;
end


function idx = refineOnsets(idx, raw, w, trailing)
%REFINEONSETS  Re-time each onset to the FOOT of the edge, against the
%   unsmoothed channel.
%
%   The coarse onset is within about half a smoothing window of the truth,
%   so the edge is looked for in a window of that size around it. Two steps:
%   find the edge by its half-height, then walk back to where it began.
%
%   HALF-HEIGHT FINDS THE EDGE. The level is the midpoint between the signal
%   just BEFORE it and just AFTER it, both taken locally: a diode's baseline
%   drifts over a recording, and a level from the whole channel would be
%   wrong at both ends of a long session. Medians, not means: the "before"
%   window still contains mains flicker and the tail of a bright patch can
%   overshoot, and a median ignores both.
%
%   THEN THE FOOT IS WHAT IS REPORTED, which is a deliberate choice of
%   measurement convention and worth being explicit about. Half-height is
%   the commoner convention in the literature and is the more repeatable
%   number, because it sits on the steepest part of the edge where a little
%   noise moves it least. But the quantity a photodiode is here to measure
%   is WHEN THE DISPLAY BEGAN TO CHANGE, and the display began to change at
%   the foot: everything between the foot and the half-height is the pixel
%   response of the panel, which is a property of the monitor and not of the
%   presentation software. Reporting the half-height therefore charges the
%   timing chain for the panel's rise time.
%
%   THE FOOT IS FOUND BY WALKING BACK to the last sample still at baseline,
%   not by taking a fixed fraction of the step. Baseline is not a point but
%   a band: this channel carries mains flicker, and on this lab's rig that
%   is thousands of units peak to peak. So "departed" means further from the
%   local median than the local scatter allows, using a robust spread, and
%   the noisier the channel the later the foot honestly is. A fixed 5% or
%   10% of the step would sit inside the flicker on a bad channel and pick a
%   flicker peak instead of the edge.
%
%   The floor keeps that from failing the other way. On a clean synthetic
%   signal the scatter is zero, every sample counts as departed, and the
%   walk would run to the start of the window; requiring the departure to be
%   at least a small fraction of the step stops it.
    if isempty(idx) || w <= 1
        return;
    end
    n = numel(raw);
    for k = 1:numel(idx)
        c = idx(k);
        lo = max(1, c - w);
        hi = min(n, c + w);

        before = raw(lo:max(lo, c - 1));
        after = raw(min(n, c + 1):hi);
        if isempty(before) || isempty(after)
            continue;
        end
        base = median(before);
        level = (base + median(after)) / 2;

        % The first sample in the window on the correct side of that level,
        % searching forward from the start of the window.
        seg = raw(lo:hi);
        if trailing
            crossed = find(seg < level, 1, 'first');
        else
            crossed = find(seg > level, 1, 'first');
        end
        if isempty(crossed)
            continue;
        end

        idx(k) = lo + footOf(seg, crossed, base, median(after)) - 1;
    end
    idx = unique(idx);
end

% ======================================================================= %
function j = footOf(seg, crossed, base, top)
%FOOTOF  The first sample of the run of departure that reaches CROSSED.
%   Walks back from the half-height crossing while the sample before is
%   still away from baseline, and stops at the first one that is not.
    scatter = 1.4826 * median(abs(seg(1:max(1, crossed - 1)) - base));
    step = abs(top - base);
    departure = max(3 * scatter, 0.05 * step);

    j = crossed;
    while j > 1 && abs(seg(j - 1) - base) > departure
        j = j - 1;
    end
end
