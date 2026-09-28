function pairs = timeLockedEvents(plan, srate, windowMs)
%TIMELOCKEDEVENTS  Modelled events in no bin that keep a near-constant lag
%   to another event type, which the fit can hardly tell apart.
%   PAIRS = Unfold.timeLockedEvents(PLAN, SRATE, WINDOWMS) checks every event
%   type PLAN models for an event code in no bin (PLAN.nuisanceTypes, see
%   Unfold.binModel) against every other type it models, bins and codes
%   alike, in a recording sampled at SRATE Hz with a response window of
%   WINDOWMS ([start stop], in ms). It returns one element per time-locked
%   pair, with fields
%       .code    the event code in no bin, as the dialog lists it
%       .other   the bin label or code it is locked to
%       .lagMs   the median lag, code minus other: positive when the code
%                follows, negative when it precedes
%       .sdMs    the standard deviation of that lag
%       .note    one sentence saying so, for the model's notes
%   in the order the types are modelled. It fits nothing and needs no
%   toolbox.
%
%   WHY IT MATTERS. Deconvolution separates two responses by seeing them at
%   different offsets from one another. Two event types that almost always
%   come the same distance apart (a fixation 12 ms after its saccade, a
%   trial marker a second before each stimulus) give the model next to no
%   such leverage, so the design is nearly collinear: the solver can run out
%   of iterations before it converges, and whatever it returns for the two
%   is shared between them arbitrarily. Unfold.binModel already names bins
%   at an exactly fixed lag; this is the near-constant case, for the events
%   the user chose to model outside the bins (manual issue M10), where
%   leaving one of the pair out is usually the answer: its response then
%   stays in the other's waveform, as it would in an average.
%
%   WHAT COUNTS AS TIME-LOCKED, a heuristic with its thresholds named below.
%   The typical lag is the median, over the code's events, of the lag to the
%   nearest event of the other type; it has to be shorter than the window,
%   or the two responses never overlap. A code event is locked when the
%   other type has an event within TOLERANCE_MS of that lag, and the other
%   type's event is locked when the code has one there. The pair is
%   time-locked when at least MOST_LOCKED of the events of EACH type are
%   locked, and the locked lags vary by less than LOCKED_SD_MS. Each type,
%   because the events without a partner are exactly what lets the fit tell
%   the two apart: a code that follows only a few of a bin's events is
%   harmless. The median and the tolerance, rather than the nearest lag
%   itself, because the nearest event is now and then another trial's (two
%   stimuli closer together than the lag), and one such outlier would
%   otherwise hide a lock that holds for every other event. A jitter of s ms
%   leaves responses slower than about 1/(2*pi*s) Hz unseparated, 8 Hz at
%   20 ms, which is most of an ERP.
%
%   See also UNFOLD.BINMODEL, UNFOLD.FITBINS, DECONVOLVEDIALOG.
    LOCKED_SD_MS = 20;      % below this spread, a lag counts as near-constant
    TOLERANCE_MS = 40;      % how far from the typical lag a partner may be
    MOST_LOCKED = 0.8;      % the share of each type's events that must be locked

    pairs = struct('code', {}, 'other', {}, 'lagMs', {}, 'sdMs', {}, 'note', {});
    if isempty(plan.nuisanceTypes) || isempty(plan.events)
        return;
    end

    types = {plan.events.type};
    latencies = [plan.events.latency];
    toMs = 1000 / double(srate);
    spanMs = diff(double(windowMs));
    isNuisance = ismember(plan.eventTypes, plan.nuisanceTypes);

    for a = find(isNuisance)
        latA = latencies(strcmp(types, plan.eventTypes{a}));
        for b = 1:numel(plan.eventTypes)
            % A pair of codes is checked once; a code and a bin always.
            if b == a || (isNuisance(b) && b < a)
                continue;
            end
            latB = latencies(strcmp(types, plan.eventTypes{b}));
            if numel(latA) < 2 || numel(latB) < 2
                continue;
            end
            typical = median(lagsNearest(latA, latB, 0)) * toMs;
            if abs(typical) >= spanMs
                continue;       % the two responses never overlap
            end
            lagA = lagsNearest(latA, latB, typical / toMs) * toMs;
            lagB = lagsNearest(latB, latA, -typical / toMs) * toMs;
            lockedA = abs(lagA - typical) <= TOLERANCE_MS;
            lockedB = abs(lagB + typical) <= TOLERANCE_MS;
            if mean(lockedA) < MOST_LOCKED || mean(lockedB) < MOST_LOCKED || nnz(lockedA) < 2
                continue;
            end
            spread = std(lagA(lockedA));
            if spread >= LOCKED_SD_MS
                continue;
            end
            pair = struct('code', plan.typeLabels{a}, 'other', plan.typeLabels{b}, ...
                'lagMs', median(lagA(lockedA)), 'sdMs', spread, 'note', '');
            pair.note = noteFor(pair, isNuisance(b));
            pairs(end + 1) = pair; %#ok<AGROW>
        end
    end
end

% ======================================================================= %
function lags = lagsNearest(from, to, target)
%LAGSNEAREST  For each latency in FROM, the signed lag (FROM minus TO, in
%   samples) to the event in TO whose lag is closest to TARGET. With TARGET
%   0 that is simply the nearest event. Signed, so a code that always
%   follows by the same amount reads as one constant lag rather than two
%   alternating ones.
    lags = zeros(1, numel(from));
    for k = 1:numel(from)
        differences = from(k) - to;
        [~, at] = min(abs(differences - target));
        lags(k) = differences(at);
    end
end

function text = noteFor(pair, otherIsCode)
%NOTEFOR  The pair in one sentence, with what to do about it.
    if pair.lagMs >= 0
        relation = sprintf('follows "%s" by %.0f ms', pair.other, pair.lagMs);
    else
        relation = sprintf('precedes "%s" by %.0f ms', pair.other, -pair.lagMs);
    end
    if otherIsCode
        advice = 'Consider modelling only one of the two.';
    else
        advice = sprintf(['Consider not modelling "%s": its response then stays in the ' ...
            'waveform of "%s", as it would in an average.'], pair.code, pair.other);
    end
    text = sprintf(['"%s", in no bin, %s almost every time (SD %.1f ms), so the model can ' ...
        'hardly tell their responses apart: the solver may not converge, and what it ' ...
        'returns for the two is shared between them arbitrarily. %s'], ...
        pair.code, relation, pair.sdMs, advice);
end
