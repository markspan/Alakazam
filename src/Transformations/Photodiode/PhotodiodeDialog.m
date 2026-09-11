function options = PhotodiodeDialog(EEG)
%PHOTODIODEDIALOG  Pick the diode channel and confirm the detection by eye.
%   OPTIONS = PhotodiodeDialog(EEG) returns the settings Photodiode should
%   record, or [] if the analyst cancelled.
%
%   THE PLOT IS NOT DECORATION. A photodiode channel can look like almost
%   anything: on this lab's own recordings it appears as mains flicker at a
%   baseline of 5000, as a dead channel sitting at zero, and as a live one
%   stepping fifteen-fold. No default threshold survives that variety, so
%   the dialog shows the channel with the detected onsets drawn on it and
%   asks the analyst to agree. A number typed into a box with no picture is
%   how a detector ends up looking like it works.
%
%   It also shows the measured delay as it changes, because that is the
%   answer being sought, and seeing it move as the threshold moves is the
%   quickest way to tell a real detection from a spurious one.
%
%   See also PHOTODIODE, DETECTDIODEONSETS, DIODETRIGGERDELAY.
    options = [];

    labels = channelLabels(EEG);
    guess = guessDiode(labels);

    fig = uifigure('Name', 'Photodiode', 'Position', centredOn([], 1080, 680));
    outer = uigridlayout(fig, [3 1], 'RowHeight', {'fit', '1x', 46}, ...
        'Padding', [10 10 10 10], 'RowSpacing', 8);

    % ---- settings ---------------------------------------------------------
    top = uigridlayout(outer, [4 8], ...
        'ColumnWidth', {58, '1x', 62, 70, 74, 70, 78, 70}, ...
        'RowHeight', {'fit', 'fit'}, 'Padding', [0 0 0 0], ...
        'ColumnSpacing', 6, 'RowSpacing', 6);
    top.Layout.Row = 1;

    uilabel(top, 'Text', 'Channel');
    chanDrop = uidropdown(top, 'Items', labels, 'Value', labels{guess}, ...
        'ValueChangedFcn', @(~,~) refresh());
    uilabel(top, 'Text', 'Smooth');
    smoothField = uieditfield(top, 'numeric', 'Value', 25, ...
        'ValueChangedFcn', @(~,~) refresh());
    uilabel(top, 'Text', 'ms  Min gap');
    gapField = uieditfield(top, 'numeric', 'Value', 100, ...
        'ValueChangedFcn', @(~,~) refresh());
    uilabel(top, 'Text', 'ms');
    modeDrop = uidropdown(top, 'Items', {'Measure delay', 'Add as events'}, ...
        'ItemsData', {'measure', 'events'}, 'ValueChangedFcn', @(~,~) refresh());

    uilabel(top, 'Text', 'Threshold');
    threshField = uieditfield(top, 'text', 'Value', 'auto', ...
        'ValueChangedFcn', @(~,~) refresh());
    uilabel(top, 'Text', 'Min high');
    durField = uieditfield(top, 'numeric', 'Value', 20, ...
        'ValueChangedFcn', @(~,~) refresh());
    uilabel(top, 'Text', 'ms  Max lag');
    lagField = uieditfield(top, 'numeric', 'Value', 200, ...
        'ValueChangedFcn', @(~,~) refresh());
    uilabel(top, 'Text', 'ms  Suffix');
    typeField = uieditfield(top, 'text', 'Value', 'PD', ...
        'Tooltip', ['Appended to the trigger''s own name when adding onsets as ' ...
            'events, so an onset answering "s70" is added as "s70PD"'], ...
        'ValueChangedFcn', @(~,~) refresh());

    % WHICH TRIGGERS MAY OWN AN ONSET, and this is not a nicety. An onset is
    % paired with the nearest event BEFORE it, and with this left empty that
    % means the nearest event of any type at all. Any marker that happens to
    % land between a stimulus trigger and the screen change, a response code
    % or a port reset twenty milliseconds later, will take the onset from
    % the trigger that actually caused it: the stimulus type then comes up
    % one short and the interloper acquires a diode event it cannot have
    % earned. Naming the stimulus types here is what prevents it.
    uilabel(top, 'Text', 'Triggers');
    triggersField = uieditfield(top, 'text', 'Value', '', ...
        'Tooltip', ['Only these event types may be paired with an onset, separated ' ...
            'by spaces or commas (e.g. "s106 s107"). Empty means any event, which ' ...
            'lets a marker falling between a trigger and the screen change steal ' ...
            'the pairing.'], ...
        'ValueChangedFcn', @(~,~) refresh());
    triggersField.Layout.Row = 3;
    triggersField.Layout.Column = [2 8];

    % WHICH TRANSITION COUNTS AS AN ONSET. detectDiodeOnsets calls this
    % 'leading'/'trailing' (the edge of the HIGH state); shown here as
    % Rising/Falling, the terms an analyst actually thinks in when looking at
    % the trace. There was no control for this at all before -- Edge silently
    % defaulted to 'leading' (rising) in detectDiodeOnsets, which is right
    % for a patch that goes bright and wrong for a rig wired so the patch
    % going dark is the one that marks the flip. Given its own row (rather
    % than folded into the already-full rows above) and explicit Layout, so
    % it cannot be disturbed by the auto-flow placement those rows rely on.
    edgeLabel = uilabel(top, 'Text', 'Edge');
    edgeLabel.Layout.Row = 4;
    edgeLabel.Layout.Column = 1;
    edgeDrop = uidropdown(top, 'Items', {'Rising', 'Falling'}, ...
        'ItemsData', {'leading', 'trailing'}, 'Value', 'leading', ...
        'Tooltip', ['Which transition of the diode signal is the onset: Rising if the ' ...
            'patch going bright marks the flip, Falling if going dark does.'], ...
        'ValueChangedFcn', @(~,~) refresh());
    edgeDrop.Layout.Row = 4;
    edgeDrop.Layout.Column = 2;

    % ---- plot + verdict ----------------------------------------------------
    mid = uigridlayout(outer, [3 2], 'RowHeight', {'1x', 26, 'fit'}, ...
        'ColumnWidth', {'1x', 330}, 'Padding', [0 0 0 0], ...
        'RowSpacing', 6, 'ColumnSpacing', 8);
    mid.Layout.Row = 2;
    % A holder rather than the axes itself: the view inside it is rebuilt
    % when the channel changes, and rebuilding a child of a two-row grid
    % would land it in the wrong row.
    plotHolder = uigridlayout(mid, [1 1], 'Padding', [0 0 0 0]);
    plotHolder.Layout.Row = 1;
    plotHolder.Layout.Column = 1;

    % ONE ROW PER TRIGGER CODE, because they do not all measure the same
    % thing. On a real recording s50 and s51 sat 21.5 ms after the screen
    % change while s102 to s111 sat at 2.0 ms: two families of marker sent
    % at different points in the flip cycle, pooled into one median that
    % described neither. The spread within a type matters as much as its
    % offset, so the IQR and the range are here beside it: a type whose
    % onsets all land within a millisecond is timed reliably whatever its
    % offset, and one spread over a frame is not.
    byTypeTable = uitable(mid, ...
        'ColumnName', {'Trigger', 'n', 'median', 'IQR', 'min', 'max'}, ...
        'ColumnWidth', {70, 40, 55, 50, 50, 50}, ...
        'ColumnFormat', {'char', 'numeric', 'bank', 'bank', 'bank', 'bank'}, ...
        'RowName', {}, 'Data', cell(0, 6));
    byTypeTable.Layout.Row = [1 3];
    byTypeTable.Layout.Column = 2;
    view = [];
    viewChannel = -1;
    thresholdLine = [];
    ranking = [];        % pair indices, most deviant first
    rankIndex = 0;
    lastReport = [];
    lastEvents = struct('type', {}, 'latency', {});

    % WORST FIRST, THEN STEP DOWN. A display lag is only interesting when
    % it is not what the others are: the median is the number you correct
    % by, and the trials worth looking at are the ones furthest from it.
    % Ranking by distance from the median and starting at the top puts the
    % dropped frame, or the trigger that fired at the wrong moment, on
    % screen first rather than leaving it to be found by scrolling through
    % twelve hundred of them.
    navRow = uigridlayout(mid, [1 4], 'ColumnWidth', {96, 32, 32, '1x'}, ...
        'Padding', [0 0 0 0], 'ColumnSpacing', 4);
    navRow.Layout.Row = 2;
    navRow.Layout.Column = 1;
    worstBtn = uibutton(navRow, 'Text', 'Worst lag', ...
        'Tooltip', 'Go to the trigger whose display lag is furthest from the median', ...
        'ButtonPushedFcn', @(~,~) gotoRank(1));
    prevBtn = uibutton(navRow, 'Text', '-', ...
        'Tooltip', 'Back towards the worst', ...
        'ButtonPushedFcn', @(~,~) stepRank(-1));
    nextBtn = uibutton(navRow, 'Text', '+', ...
        'Tooltip', 'On to the next most deviant', ...
        'ButtonPushedFcn', @(~,~) stepRank(+1));
    navLabel = uilabel(navRow, 'Text', '', 'FontSize', 12);

    verdict = uilabel(mid, 'Text', '', 'WordWrap', 'on', 'FontSize', 13);
    verdict.Layout.Row = 3;
    verdict.Layout.Column = 1;

    % ---- buttons ------------------------------------------------------------
    buttons = uigridlayout(outer, [1 3], 'ColumnWidth', {'1x', 90, 90}, ...
        'Padding', [0 4 0 0]);
    buttons.Layout.Row = 3;
    cancelBtn = uibutton(buttons, 'Text', 'Cancel', 'ButtonPushedFcn', @(~,~) onCancel());
    cancelBtn.Layout.Column = 2;
    okBtn = uibutton(buttons, 'Text', 'OK', 'ButtonPushedFcn', @(~,~) onOK());
    okBtn.Layout.Column = 3;
    fig.CloseRequestFcn = @(~,~) onCancel();

    refresh();
    uiwait(fig);

    % ===================================================================== %
    function refresh()
        o = currentOptions();
        chan = find(strcmp(labels, chanDrop.Value), 1);
        signal = double(EEG.data(chan, :));
        [onsets, info] = detectDiodeOnsets(signal, EEG.srate, o);

        % The pairing is worked out whichever mode is selected, because the
        % bands it produces are the clearest evidence that the detection is
        % right: one band per trial, all much the same width. In events mode
        % it is drawn but not reported.
        sourceEvents = TransTools.FieldOr(EEG, 'event', []);
        if ~isstruct(sourceEvents) || isempty(fieldnames(sourceEvents))
            sourceEvents = struct('type', {}, 'latency', {});
        end
        report = diodeTriggerDelay(onsets, sourceEvents, EEG.srate, o);

        [preview, styleFor] = photodiodePreview(signal, EEG.srate, onsets, ...
            sourceEvents, report.pairs, typeField.Value);
        showPreview(preview, styleFor, chan, info);

        lastReport = report;
        lastEvents = sourceEvents;
        rankPairs(report);
        fillByType(report);

        if isempty(onsets)
            verdict.Text = info.reason;
            verdict.FontColor = [0.69 0.24 0.22];
            byTypeTable.Data = cell(0, 6);
            return;
        end
        verdict.FontColor = [0.18 0.42 0.28];
        if strcmp(modeDrop.Value, 'events')
            names = diodeEventLabels(onsets, sourceEvents, report.pairs, typeField.Value);
            verdict.Text = sprintf(['%d onsets found (separability %.1f). They will be ' ...
                'added as events named after their own trigger, e.g. "%s".%s'], ...
                numel(onsets), info.separation, names{1}, ...
                pairedTypesNote(report, sourceEvents));
        else
            verdict.Text = sprintf('%d onsets found (separability %.1f).  %s%s', ...
                numel(onsets), info.separation, report.summary, ...
                pairedTypesNote(report, sourceEvents));
        end
    end

    function showPreview(preview, styleFor, chan, info)
    %SHOWPREVIEW  Draw, or redraw, the channel and its marks.
    %   The view is rebuilt only when the channel changes. Every other
    %   control here changes the marks and not the signal, and rebuilding
    %   would rebuild the decimation pyramid over the whole recording and
    %   throw away the analyst's scroll position mid-comparison.
        if isempty(view) || ~isvalid(view) || chan ~= viewChannel
            delete(plotHolder.Children);
            view = SignalView(plotHolder, preview.times, preview, ...
                'LineSpec', 'k-', ...
                'ShowAxisTicks', true, ...
                'YLimMode', 'fixed', ...
                'FitWholeRecording', true, ...
                'MaxEvents', 400, ...
                'MaxAreas', 400, ...
                'EventStyleFcn', styleFor);
            viewChannel = chan;
            thresholdLine = [];
        else
            view.setOverlays(preview);
        end

        % The threshold is the one number the detector acts on, so it is
        % drawn where it can be compared against the trace it is cutting.
        if ~isempty(thresholdLine) && isvalid(thresholdLine)
            delete(thresholdLine);
        end
        thresholdLine = [];
        if isfinite(info.threshold)
            thresholdLine = yline(view.Axes, info.threshold, '--', ...
                'Color', [0.29 0.44 0.71], 'LineWidth', 1);
        end
    end

    function fillByType(report)
    %FILLBYTYPE  The per-trigger breakdown, worst jitter first.
    %   Sorted by IQR rather than by count, because the row worth reading is
    %   the one whose onsets do not agree with each other: an offset can be
    %   corrected, scatter cannot.
        if isempty(report.byType)
            byTypeTable.Data = cell(0, 6);
            return;
        end
        rows = report.byType;
        [~, order] = sort([rows.iqrMs], 'descend', 'MissingPlacement', 'last');
        rows = rows(order);

        data = cell(numel(rows), 6);
        for i = 1:numel(rows)
            data(i, :) = {rows(i).type, rows(i).n, rows(i).medianMs, ...
                rows(i).iqrMs, rows(i).minMs, rows(i).maxMs};
        end
        byTypeTable.Data = data;
    end

    function rankPairs(report)
    %RANKPAIRS  Order the pairs by how far each lag is from the median.
    %   Recomputed on every refresh, because changing a setting changes
    %   which onsets exist and therefore which of them is the odd one.
        ranking = [];
        rankIndex = 0;
        navLabel.Text = '';
        enable = 'off';
        if ~isempty(report.pairs) && isfinite(report.medianMs)
            deviation = abs([report.pairs.lagMs] - report.medianMs);
            [~, ranking] = sort(deviation, 'descend');
            enable = 'on';
        end
        worstBtn.Enable = enable;
        prevBtn.Enable = enable;
        nextBtn.Enable = enable;
    end

    function stepRank(delta)
        if isempty(ranking)
            return;
        end
        if rankIndex == 0
            gotoRank(1);
            return;
        end
        gotoRank(rankIndex + delta);
    end

    function gotoRank(k)
    %GOTORANK  Show the K-th most deviant pair, and say which it is.
        if isempty(ranking)
            return;
        end
        k = min(numel(ranking), max(1, k));
        rankIndex = k;
        pair = lastReport.pairs(ranking(k));

        triggerName = 'unknown';
        if pair.event >= 1 && pair.event <= numel(lastEvents)
            triggerName = char(string(lastEvents(pair.event).type));
        end
        seconds = (pair.onset - 1) / EEG.srate;

        % Two seconds is a CEILING, not a zoom setting: wide enough to see
        % the trigger, the edge and the baseline before it, and applied only
        % when the window is currently wider than that. Anyone stepping
        % through markers has usually just set the magnification they want
        % to compare them at, and resetting it on every step would change
        % the size of the thing they are comparing.
        if ~isempty(view) && isvalid(view)
            view.centreOnTime(seconds, 2);
        end

        navLabel.Text = sprintf('%d of %d: %s at %.1f s, lag %.1f ms (median %.1f, off by %+.1f)', ...
            k, numel(ranking), triggerName, seconds, pair.lagMs, ...
            lastReport.medianMs, pair.lagMs - lastReport.medianMs);
    end

    function note = pairedTypesNote(report, sourceEvents)
    %PAIREDTYPESNOTE  Which trigger types took an onset, and how many each.
    %   Shown because it is where a stolen pairing becomes visible: a
    %   stimulus type one short, and beside it some other code with a single
    %   onset it should not have. Counting them is the difference between
    %   noticing that on screen and discovering it in the event table weeks
    %   later.
        note = '';
        if isempty(report.pairs)
            return;
        end
        owners = arrayfun(@(pr) string(sourceEvents(pr.event).type), report.pairs);
        [kinds, ~, which] = unique(owners);
        counts = accumarray(which(:), 1);
        [counts, order] = sort(counts, 'descend');

        parts = strings(1, numel(order));
        for i = 1:numel(order)
            parts(i) = sprintf('%s (%d)', kinds(order(i)), counts(i));
        end
        note = sprintf('\nPaired against: %s.', strjoin(parts, ', '));

        if numel(kinds) > 1
            note = sprintf(['%s A type with only one or two is usually a marker that ' ...
                'fell between a trigger and the screen change; name the stimulus ' ...
                'types under Triggers to stop it taking them.'], note);
        end
    end

    function types = parseTypes(text)
    %PARSETYPES  "s106, s107" or "s106 s107" into a cellstr; a token shaped
    %   like MATLAB range notation ("40:43", or "40:2:48" with a step)
    %   expands to the individual codes it names. Empty means any.
        text = strtrim(char(text));
        if isempty(text)
            types = {};
            return;
        end
        parts = strsplit(text, {',', ' ', ';'});
        parts = parts(~cellfun(@isempty, strtrim(parts)));
        parts = cellfun(@strtrim, parts, 'UniformOutput', false);
        types = expandTriggerRanges(parts);
    end

    function o = currentOptions()
        o = struct();
        o.Channel = chanDrop.Value;        % by LABEL: see Photodiode/resolveChannel
        o.SmoothMs = smoothField.Value;
        o.MinGapMs = gapField.Value;
        o.MinDurationMs = durField.Value;
        o.MaxLagMs = lagField.Value;
        o.Mode = modeDrop.Value;
        o.Edge = edgeDrop.Value;
        o.EventSuffix = typeField.Value;
        o.Types = parseTypes(triggersField.Value);
        t = str2double(threshField.Value);
        if isnan(t)
            o.Threshold = NaN;             % 'auto', or anything unreadable
        else
            o.Threshold = t;
        end
    end

    function onOK()
        options = currentOptions();
        uiresume(fig);
        delete(fig);
    end

    function onCancel()
        options = [];
        uiresume(fig);
        delete(fig);
    end
end

function labels = channelLabels(EEG)
    n = size(EEG.data, 1);
    labels = arrayfun(@(k) sprintf('Channel %d', k), 1:n, 'UniformOutput', false);
    if isfield(EEG, 'chanlocs') && numel(EEG.chanlocs) == n
        for k = 1:n
            if ~isempty(EEG.chanlocs(k).labels)
                labels{k} = char(EEG.chanlocs(k).labels);
            end
        end
    end
end

function idx = guessDiode(labels)
%GUESSDIODE  The diode is conventionally labelled and conventionally last,
%   in that order of reliability: a label says what a channel IS, a position
%   only says where it happened to be written.
    idx = find(~cellfun(@isempty, regexpi(labels, 'photo|diode', 'once')), 1);
    if isempty(idx)
        idx = numel(labels);
    end
end


