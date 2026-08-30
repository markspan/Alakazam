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

    fig = uifigure('Name', 'Photodiode', 'Position', centred(1080, 680));
    outer = uigridlayout(fig, [3 1], 'RowHeight', {'fit', '1x', 46}, ...
        'Padding', [10 10 10 10], 'RowSpacing', 8);

    % ---- settings ---------------------------------------------------------
    top = uigridlayout(outer, [2 8], ...
        'ColumnWidth', {58, '1x', 62, 70, 74, 70, 58, 70}, ...
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
    uilabel(top, 'Text', 'ms');
    typeField = uieditfield(top, 'text', 'Value', 'diode', ...
        'Tooltip', 'Event type to use when adding onsets as events');

    % ---- plot + verdict ----------------------------------------------------
    mid = uigridlayout(outer, [2 1], 'RowHeight', {'1x', 'fit'}, ...
        'Padding', [0 0 0 0], 'RowSpacing', 6);
    mid.Layout.Row = 2;
    ax = uiaxes(mid);
    ax.Layout.Row = 1;
    xlabel(ax, 'Time (s)');
    ylabel(ax, 'Photodiode');

    verdict = uilabel(mid, 'Text', '', 'WordWrap', 'on', 'FontSize', 13);
    verdict.Layout.Row = 2;

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

        draw(ax, signal, onsets, info, EEG.srate);

        if isempty(onsets)
            verdict.Text = info.reason;
            verdict.FontColor = [0.69 0.24 0.22];
            return;
        end
        verdict.FontColor = [0.18 0.42 0.28];
        if strcmp(modeDrop.Value, 'events')
            verdict.Text = sprintf(['%d onsets found (separability %.1f). They will be ' ...
                'added as events of type "%s".'], numel(onsets), info.separation, ...
                typeField.Value);
        else
            rep = diodeTriggerDelay(onsets, eventsOf(EEG), EEG.srate, o);
            verdict.Text = sprintf('%d onsets found (separability %.1f).  %s', ...
                numel(onsets), info.separation, rep.summary);
        end
    end

    function o = currentOptions()
        o = struct();
        o.Channel = chanDrop.Value;        % by LABEL: see Photodiode/resolveChannel
        o.SmoothMs = smoothField.Value;
        o.MinGapMs = gapField.Value;
        o.MinDurationMs = durField.Value;
        o.MaxLagMs = lagField.Value;
        o.Mode = modeDrop.Value;
        o.EventType = typeField.Value;
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

% ======================================================================= %
function draw(ax, signal, onsets, info, srate)
%DRAW  The channel with the detected onsets on it.
%   Decimated for display. A recording is often ten minutes at 1 kHz, and
%   plotting 600,000 points to a 900-pixel axis costs seconds and shows
%   nothing a decimated trace does not; the onsets are drawn from the FULL
%   resolution result, so nothing is lost where it matters.
    cla(ax);
    n = numel(signal);
    step = max(1, floor(n / 6000));
    idx = 1:step:n;
    t = (idx - 1) / srate;

    plot(ax, t, signal(idx), 'Color', [0.42 0.47 0.53]);
    hold(ax, 'on');
    if isfinite(info.threshold)
        yline(ax, info.threshold, '--', 'Color', [0.29 0.44 0.71], 'LineWidth', 1);
    end
    if ~isempty(onsets)
        y = double(max(signal));
        plot(ax, (onsets - 1) / srate, repmat(y, 1, numel(onsets)), 'v', ...
            'MarkerFaceColor', [0.75 0.25 0.24], 'MarkerEdgeColor', 'none', ...
            'MarkerSize', 5);
    end
    hold(ax, 'off');
    xlim(ax, [0, max(t)]);
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

function events = eventsOf(EEG)
    if isfield(EEG, 'event')
        events = EEG.event;
    else
        events = [];
    end
end

function pos = centred(width, height)
    screen = get(groot, 'ScreenSize');
    pos = [(screen(3) - width) / 2, (screen(4) - height) / 2, width, height];
end
