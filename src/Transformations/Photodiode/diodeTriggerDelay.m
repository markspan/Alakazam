function report = diodeTriggerDelay(onsets, events, srate, opts)
%DIODETRIGGERDELAY  How late the display was, relative to the triggers.
%   REPORT = diodeTriggerDelay(ONSETS, EVENTS, SRATE, OPTS) pairs each
%   photodiode onset with the trigger it belongs to and summarises the lag
%   between them.
%
%   OPTS fields, all optional:
%     Types        trigger types to pair against   (default: all)
%     MaxLagMs     how far to look for a partner   (default 200)
%     ToleranceMs  how far a trigger may arrive AFTER an onset and still
%                  own it, for markers sent at the flip rather than before
%                  it                              (default 5)
%
%   REPORT fields: n, medianMs, meanMs, sdMs, iqrMs, minMs, maxMs, pairs
%   (a struct array of onset/event/lagMs), byType (one row per trigger code
%   with its own n/median/IQR/min/max), unpaired, and summary, a sentence
%   fit to show an analyst.
%
%   THIS IS THE POINT OF THE WHOLE TRANSFORMATION. Importing diode onsets as
%   events is what EEGLAB's pop_chanevent does, and on its own it is not
%   very useful to somebody who already has 600 perfectly good triggers.
%   What a photodiode is actually FOR, in a lab that already records
%   triggers, is measuring how long after the trigger the screen really
%   changed: the monitor's own lag, plus whatever the presentation software
%   added. That number is what you correct with, and nothing else in the
%   pipeline can tell you it.
%
%   Once measured, the correction is EventEditor's millisecond latency
%   shift. Measure here, correct there: the two halves are deliberately
%   separate transformations, because the measurement is a property of one
%   recording session and the correction is something you then apply to
%   every subject recorded on that rig.
%
%   THE MEDIAN, NOT THE MEAN, is what to correct by. Display lag is roughly
%   constant plus a quantisation to the refresh interval, but a dropped
%   frame or a missed patch produces an outlier of a whole frame or more,
%   and a mean is moved by those in a way a median is not. Both are
%   reported, and a large gap between them is itself worth seeing.
%
%   See also DETECTDIODEONSETS, PHOTODIODE, EVENTEDITOR.
    if nargin < 4; opts = struct(); end
    maxLag = TransTools.FieldOr(opts, 'MaxLagMs', 200);
    types = TransTools.FieldOr(opts, 'Types', {});
    tolerance = TransTools.FieldOr(opts, 'ToleranceMs', 5);

    report = struct('n', 0, 'medianMs', NaN, 'meanMs', NaN, 'sdMs', NaN, ...
        'iqrMs', NaN, 'minMs', NaN, 'maxMs', NaN, ...
        'pairs', struct('onset', {}, 'event', {}, 'lagMs', {}), ...
        'byType', emptyByType(), ...
        'unpaired', 0, 'summary', '');

    if isempty(onsets)
        report.summary = 'No photodiode onsets were found, so there is nothing to compare.';
        return;
    end
    if isempty(events)
        report.summary = 'This dataset has no events, so the diode cannot be compared to anything.';
        return;
    end

    keep = matching(events, types);
    if ~any(keep)
        report.summary = 'No trigger of the requested type was found in this dataset.';
        return;
    end
    eventIdx = find(keep);
    eventLat = double([events(keep).latency]);

    maxLagSamples = maxLag * srate / 1000;
    toleranceSamples = max(0, tolerance) * srate / 1000;
    lags = [];
    for k = 1:numel(onsets)
        % The trigger this onset belongs to is the nearest one BEFORE it: a
        % screen cannot change before it was told to. Pairing to the nearest
        % in either direction would happily report a negative lag, which is
        % not a display delay but a mis-pairing, and would then be averaged
        % in as though it were real.
        prior = find(eventLat <= onsets(k), 1, 'last');
        gap = Inf;
        if ~isempty(prior)
            gap = onsets(k) - eventLat(prior);
        end

        % A SMALL NEGATIVE LAG IS JITTER, NOT A CAUSALITY VIOLATION, and
        % refusing it silently loses trials. Measured on a real recording:
        % one lab's stimulus markers are sent AT the flip rather than before
        % it, giving a median lag of 2.0 ms and a minimum of 0.0. At that
        % distance a single sample of movement in where the edge is called
        % puts the onset in front of its own trigger, the pair is rejected,
        % and the count comes up one short: 30 diode events for 31 triggers,
        % appearing and disappearing as the smoothing or threshold changes.
        %
        % So a trigger arriving within ToleranceMs AFTER an onset may still
        % own it, but only when nothing before it can. The strict rule is
        % tried first and wins whenever it applies, which keeps a genuine
        % display lag pairing exactly as it did.
        if isempty(prior) || gap > maxLagSamples
            after = find(eventLat > onsets(k) & ...
                eventLat <= onsets(k) + toleranceSamples, 1, 'first');
            if isempty(after)
                continue;
            end
            prior = after;
            gap = onsets(k) - eventLat(prior);   % negative, within tolerance
        end
        report.pairs(end + 1) = struct('onset', onsets(k), ...
            'event', eventIdx(prior), 'lagMs', gap / srate * 1000);
        lags(end + 1) = gap / srate * 1000; %#ok<AGROW>
    end

    report.unpaired = numel(onsets) - numel(lags);
    report.n = numel(lags);
    if isempty(lags)
        report.summary = sprintf(['None of the %d photodiode onsets had a trigger within ' ...
            '%g ms before it. Either the triggers are of a different type, or the diode ' ...
            'and the triggers are not describing the same events.'], numel(onsets), maxLag);
        return;
    end

    report.medianMs = median(lags);
    report.meanMs   = mean(lags);
    report.sdMs     = std(lags);
    report.iqrMs    = TransTools.Percentile(lags, 75) - TransTools.Percentile(lags, 25);
    report.minMs    = min(lags);
    report.maxMs    = max(lags);

    report.byType = perType(report.pairs, events);

    report.summary = sprintf(['The display changed %.1f ms after the trigger (median of ' ...
        '%d paired onsets, IQR %.1f ms, range %.1f to %.1f).'], ...
        report.medianMs, report.n, report.iqrMs, report.minMs, report.maxMs);

    % WHAT TO CORRECT BY DEPENDS ON WHETHER THE TRIGGERS AGREE, and until
    % this was looked at on a real recording it assumed they always do. They
    % do not. Measured on one: s50 and s51 sat 21.5 ms after the screen
    % change while s102 to s111 sat at 2.0 ms, because the two families are
    % sent at different points in the flip cycle. One median pooled across
    % them describes neither, and shifting every trigger by it would apply a
    % twenty millisecond monitor correction to markers that never had one,
    % which is a real error introduced into the data rather than a wrong
    % number in a table.
    if disagree(report.byType)
        report.summary = sprintf(['%s\n\nThese triggers do NOT share one lag: %s. A ' ...
            'single shift would be wrong for at least one of them. Correct each type ' ...
            'separately in the Event editor, or set Triggers to the one family you are ' ...
            'measuring and run this again.'], report.summary, spread(report.byType));
    else
        report.summary = sprintf(['%s To correct it, shift these triggers by %+.0f ms ' ...
            'in the Event editor.'], report.summary, round(report.medianMs));
    end

    if report.unpaired > 0
        report.summary = sprintf('%s\n%d onset(s) had no trigger within %g ms and were left out.', ...
            report.summary, report.unpaired, maxLag);
    end
end

% ======================================================================= %
function rows = emptyByType()
    rows = struct('type', {}, 'n', {}, 'medianMs', {}, 'iqrMs', {}, ...
        'minMs', {}, 'maxMs', {});
end

% ======================================================================= %
function rows = perType(pairs, events)
%PERTYPE  One row per trigger code: how many onsets it owns, how late they
%   were, and how much they varied.
%
%   The variation is the point as much as the lag. A type whose onsets are
%   all within a millisecond of each other is being timed reliably, whatever
%   its offset; one spread over a frame or more is not, and no single
%   correction will fix it.
    rows = emptyByType();
    if isempty(pairs)
        return;
    end

    owners = arrayfun(@(pr) string(events(pr.event).type), pairs);
    lags = [pairs.lagMs];
    kinds = unique(owners);

    for k = 1:numel(kinds)
        these = lags(owners == kinds(k));
        rows(end + 1) = struct('type', char(kinds(k)), 'n', numel(these), ...
            'medianMs', median(these), ...
            'iqrMs', TransTools.Percentile(these, 75) - TransTools.Percentile(these, 25), ...
            'minMs', min(these), 'maxMs', max(these)); %#ok<AGROW>
    end

    [~, order] = sort([rows.n], 'descend');
    rows = rows(order);
end

% ======================================================================= %
function tf = disagree(rows)
%DISAGREE  Are these trigger types measuring different things?
%   True when the spread of their medians is larger than the scatter within
%   them, which is the ordinary test for two populations rather than one.
%   The floor stops a fraction of a millisecond of rounding from being
%   called a disagreement on a clean recording.
    tf = false;
    if numel(rows) < 2
        return;
    end
    medians = [rows.medianMs];
    within = median([rows.iqrMs], 'omitnan');
    if ~isfinite(within)
        within = 0;
    end
    tf = (max(medians) - min(medians)) > max(2, within);
end

% ======================================================================= %
function text = spread(rows)
%SPREAD  The two ends of the disagreement, named, so the sentence says
%   which types differ rather than only that some do.
    medians = [rows.medianMs];
    [~, lo] = min(medians);
    [~, hi] = max(medians);
    text = sprintf('%s at %.1f ms, %s at %.1f ms', ...
        rows(hi).type, rows(hi).medianMs, rows(lo).type, rows(lo).medianMs);
end

% ======================================================================= %
function keep = matching(events, types)
%MATCHING  Which events are of the requested types, comparing as text so a
%   numeric 112 and the string "112" are one code. Empty types means all.
    if isempty(types)
        keep = true(1, numel(events));
        return;
    end
    wanted = lower(strtrim(string(types(:)')));
    keep = false(1, numel(events));
    for i = 1:numel(events)
        keep(i) = any(wanted == lower(strtrim(string(events(i).type))));
    end
end

