function report = diodeTriggerDelay(onsets, events, srate, opts)
%DIODETRIGGERDELAY  How late the display was, relative to the triggers.
%   REPORT = diodeTriggerDelay(ONSETS, EVENTS, SRATE, OPTS) pairs each
%   photodiode onset with the trigger it belongs to and summarises the lag
%   between them.
%
%   OPTS fields, all optional:
%     Types      trigger types to pair against (default: all)
%     MaxLagMs   how far to look for a partner   (default 200)
%
%   REPORT fields: n, medianMs, meanMs, sdMs, iqrMs, minMs, maxMs, pairs
%   (a struct array of onset/event/lagMs), unpaired, and summary, a sentence
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
    maxLag = getOr(opts, 'MaxLagMs', 200);
    types = getOr(opts, 'Types', {});

    report = struct('n', 0, 'medianMs', NaN, 'meanMs', NaN, 'sdMs', NaN, ...
        'iqrMs', NaN, 'minMs', NaN, 'maxMs', NaN, ...
        'pairs', struct('onset', {}, 'event', {}, 'lagMs', {}), ...
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
    lags = [];
    for k = 1:numel(onsets)
        % The trigger this onset belongs to is the nearest one BEFORE it: a
        % screen cannot change before it was told to. Pairing to the nearest
        % in either direction would happily report a negative lag, which is
        % not a display delay but a mis-pairing, and would then be averaged
        % in as though it were real.
        prior = find(eventLat <= onsets(k), 1, 'last');
        if isempty(prior)
            continue;
        end
        gap = onsets(k) - eventLat(prior);
        if gap > maxLagSamples
            continue;                    % too far apart to be the same trial
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

    sorted = sort(lags);
    report.medianMs = median(lags);
    report.meanMs = mean(lags);
    report.sdMs = std(lags);
    report.iqrMs = quantileOf(sorted, 0.75) - quantileOf(sorted, 0.25);
    report.minMs = sorted(1);
    report.maxMs = sorted(end);

    report.summary = sprintf(['The display changed %.1f ms after the trigger (median of ' ...
        '%d paired onsets, IQR %.1f ms, range %.1f to %.1f). To correct it, shift these ' ...
        'triggers by %+.0f ms in the Event editor.'], ...
        report.medianMs, report.n, report.iqrMs, report.minMs, report.maxMs, ...
        round(report.medianMs));

    if report.unpaired > 0
        report.summary = sprintf('%s\n%d onset(s) had no trigger within %g ms and were left out.', ...
            report.summary, report.unpaired, maxLag);
    end
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

function v = quantileOf(sorted, q)
    if isempty(sorted)
        v = NaN;
        return;
    end
    v = sorted(max(1, min(numel(sorted), round(q * (numel(sorted) - 1)) + 1)));
end

function v = getOr(s, name, default)
    if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
        v = s.(name);
    else
        v = default;
    end
end
