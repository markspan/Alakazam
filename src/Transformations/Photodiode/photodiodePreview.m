function [preview, styleFor] = photodiodePreview(signal, srate, onsets, events, pairs, diodeType)
%PHOTODIODEPREVIEW  The diode channel, its triggers and its measured lags,
%   packaged as an EEG-shaped struct that SignalView can draw.
%
%   [PREVIEW, STYLEFOR] = photodiodePreview(SIGNAL, SRATE, ONSETS, EVENTS,
%   PAIRS, DIODETYPE). ONSETS are sample indices from detectDiodeOnsets,
%   EVENTS the recording's own events, and PAIRS the pairing that
%   diodeTriggerDelay worked out (its report.pairs, with onset, event and
%   lagMs). STYLEFOR maps an event label to how it should be drawn, for
%   SignalView's EventStyleFcn.
%
%   WHY THIS IS A FUNCTION AND NOT PART OF THE DIALOG. What goes on the
%   picture is the whole argument the dialog is making, and it can be
%   checked without opening a window: that every onset is marked, that
%   every pair becomes a band starting at its trigger and ending at its
%   onset, and that the band is labelled with the lag it represents. See
%   PhotodiodePreviewTest.
%
%   THE LAG IS DRAWN AS A BAND, not as a number in a corner. SignalView
%   already renders an event with a duration as a shaded span with a label
%   on it, so a trigger/onset pair drawn that way makes the quantity being
%   measured the thing you actually see: a row of bands of equal width is a
%   steady display lag, and the one band twice as wide as its neighbours is
%   the dropped frame that would otherwise only show up as a widened IQR.
%
%   THREE KINDS OF MARK, and they are deliberately different colours:
%   the recording's own triggers, the onsets the detector found, and the
%   bands between the pairs. An onset with no trigger before it, or a
%   trigger the diode never answered, is then visible as an unpaired mark
%   rather than as an increment to the "unpaired" count in the summary.
%
%   TIME IS IN SECONDS HERE. SignalView reads its overlay positions from
%   the time vector it is given, so the unit is whatever this says it is;
%   seconds suits a whole-recording view of a diode channel, and matches
%   what the dialog showed before.
%
%   See also DETECTDIODEONSETS, DIODETRIGGERDELAY, PHOTODIODEDIALOG,
%   SIGNALVIEW.
    arguments
        signal double
        srate (1, 1) double
        onsets double = []
        events struct = struct('type', {}, 'latency', {})
        pairs struct = struct('onset', {}, 'event', {}, 'lagMs', {})
        diodeType (1, :) char = 'diode'
    end

    signal = double(signal(:))';
    nSamples = numel(signal);

    preview = struct();
    preview.data    = signal;
    preview.srate   = srate;
    preview.nbchan  = 1;
    preview.pnts    = nSamples;
    preview.trials  = 1;
    preview.times   = (0:nSamples - 1) / srate;   % seconds, see above
    preview.xmin    = 0;
    preview.xmax    = max(0, (nSamples - 1) / srate);
    preview.event   = buildEvents(onsets, events, pairs, diodeType, nSamples);
    preview.chanlocs = struct('labels', {'Photodiode'});
    preview.DataType = 'TIMEDOMAIN';

    styleFor = @(label) styleOf(label, diodeType);
end

% ======================================================================= %
function events = buildEvents(onsets, sourceEvents, pairs, diodeType, nSamples)
%BUILDEVENTS  Triggers, onsets and lag bands, in one event array.
%   Each is a separate entry rather than a mutated trigger: SignalView
%   treats an event with a duration as a band and one without as a line
%   (see its parseOverlays), so giving a trigger a duration would turn the
%   trigger's own line into a band and lose the line.
    events = struct('type', {}, 'latency', {}, 'duration', {});

    for k = 1:numel(sourceEvents)
        latency = double(sourceEvents(k).latency);
        if ~isfinite(latency) || latency < 1 || latency > nSamples
            continue;
        end
        events(end + 1) = struct('type', char(string(sourceEvents(k).type)), ...
            'latency', latency, 'duration', 0); %#ok<AGROW>
    end

    for k = 1:numel(onsets)
        events(end + 1) = struct('type', diodeType, ...
            'latency', double(onsets(k)), 'duration', 0); %#ok<AGROW>
    end

    % The band runs from the trigger to the onset it was paired with, so its
    % width IS the lag. Its label is the lag, so a reader does not have to
    % measure the picture to read the number off it.
    for k = 1:numel(pairs)
        idx = pairs(k).event;
        if idx < 1 || idx > numel(sourceEvents)
            continue;
        end
        start = double(sourceEvents(idx).latency);
        width = double(pairs(k).onset) - start;
        if ~isfinite(width) || width <= 0
            continue;
        end
        events(end + 1) = struct('type', sprintf('%.0f ms', pairs(k).lagMs), ...
            'latency', start, 'duration', width); %#ok<AGROW>
    end

    if isempty(events)
        return;
    end
    [~, order] = sort([events.latency]);
    events = events(order);
end

% ======================================================================= %
function style = styleOf(label, diodeType)
%STYLEOF  Red for what the detector found, and its label lifted clear.
%
%   THREE MARKS, THREE HEIGHTS, and none of them is decoration. A diode
%   onset sits a display lag after its trigger, which is tens of
%   milliseconds: close enough that labels sharing a height overlap, and
%   the one drawn second covers the first. The trigger code is precisely
%   what the analyst is reading, so it keeps the bottom. The lag band draws
%   its own label at the top of the axes (see @label), which is where the
%   diode label went first and where it was promptly covered. The middle is
%   the one height left, and it is checked by looking at a render rather
%   than by reasoning about it.
%
%   Returning empty leaves SignalView on its own defaults, which is what
%   the recording's own triggers get.
    style = [];
    if strcmp(char(label), diodeType)
        style = struct('Color', [0.75 0.25 0.24 0.75], ...
            'LabelVerticalAlignment', 'middle');
    end
end
