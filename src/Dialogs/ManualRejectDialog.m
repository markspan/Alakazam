function options = ManualRejectDialog(EEG, prior)
%MANUALREJECTDIALOG  Alakazam-styled manual trial/channel rejection browser.
%
%   Shows one trial's full channel montage at a time -- split into as many
%   side-by-side columns as it takes to keep each one to at most 16
%   channels (a 64-channel montage draws as 4 columns of 16, not one
%   column of 64), so each trace still gets a readable amount of vertical
%   room -- with Prev/Next (or the left/right arrow keys) to walk through
%   trials. Each channel keeps one consistent colour (SignalView's own
%   default axes colour order, cycled by channel number) across every
%   trial and column, matching the continuous-data view. Click a
%   channel's trace or its label to toggle it flagged for the trial
%   currently shown; a flagged channel turns plain red/bold regardless of
%   its own colour, and stays flagged when you page away and back. This
%   is the manual counterpart of ArtefactDetect's own automatic
%   thresholds -- the analyst's eye instead of a fixed number.
%
%   A Scale slider controls the AMPLITUDE GAIN applied to every trace, on
%   top of one auto-computed starting scale shared by every channel/trial
%   (so paging between trials, or between columns, stays an
%   eye-to-eye comparison -- the row spacing itself never changes, only
%   how tall a trace of a given amplitude draws within its own row). The
%   auto starting scale is a robust (99th-percentile) amplitude, not the
%   dataset's raw maximum: a single outlier sample -- a spike, or a
%   channel/trial an earlier ArtefactDetect pass already NaN'd out -- would
%   otherwise flatten every ordinary trace to an invisible flat line, which
%   is exactly the "nothing renders" failure this dialog first shipped
%   with. A trial that is entirely NaN (already rejected upstream) still
%   cannot show a trace -- there is nothing to draw -- so that case prints
%   a plain on-axes note instead of leaving a silent blank plot.
%
%   EEG is the epoched dataset (channels x time x trials) to browse. PRIOR
%   is the struct ManualReject.m last stored via TransformSettings (or [],
%   on first use) -- .scope/.channelMode prefill the two settings controls;
%   .flags only prefills the flagged-cells matrix when its size still
%   matches this exact dataset (nChan x nTrials), since flags recorded on a
%   different recording's trial count/order would not mean anything here.
%
%   Returns a struct with fields:
%     .flags       nChan x nTrials logical, true where the analyst flagged
%                  that channel as faulty for that trial (possibly all
%                  false, if the analyst confirmed without flagging anything)
%     .scope       'Whole epoch' or 'This channel only' -- same two choices,
%                  and the same wording, as ArtefactDetect's own Scope
%     .channelMode 'NaN' or 'Interpolate' -- only meaningful when scope is
%                  'This channel only'
%   or [] if the analyst cancelled.
    [accentColor, bgColor] = dialogChromeColors();
    options = [];

    [nChan, ~, nTrials] = size(EEG.data);
    times  = EEG.times;
    labels = {EEG.chanlocs.labels};
    trial  = 1;
    gain   = 1; % user-controlled multiplier on top of the auto scale below

    flags = false(nChan, nTrials);
    if isstruct(prior) && isfield(prior, 'flags') && isequal(size(prior.flags), [nChan, nTrials])
        flags = logical(prior.flags);
    end
    priorScope = 'Whole epoch';
    if isstruct(prior) && isfield(prior, 'scope') && ~isempty(prior.scope)
        priorScope = char(prior.scope);
    end
    priorChannelMode = 'NaN';
    if isstruct(prior) && isfield(prior, 'channelMode') && ~isempty(prior.channelMode)
        priorChannelMode = char(prior.channelMode);
    end

    % Layout (row spacing) and data scale (how tall a trace of a given
    % amplitude draws within its own row) are deliberately separate: the
    % Scale slider below only ever changes the latter, so paging trials or
    % dragging the slider never reflows the row positions themselves.
    rowHeight = 10;
    % The MEDIAN of each (channel, trial) cell's own peak amplitude, not a
    % percentile over every raw sample pooled together: an entire bad
    % channel or a fully-saturated trial can easily be 5% or more of the
    % dataset's raw SAMPLES, which would still dominate even a 99th-
    % percentile-over-samples estimate (confirmed directly -- this was the
    % actual first version here, and it still rendered nothing on a
    % dataset with one constant-5000uV channel). A per-cell peak is only
    % ONE number no matter how many samples that cell's own fault spans,
    % so the median tolerates a genuinely bad minority of channels/trials
    % the way a same-order percentile over raw samples cannot.
    perCellPeak = squeeze(max(abs(EEG.data), [], 2, 'omitnan'));
    robustAmp = median(perCellPeak(:), 'omitnan');
    if isempty(robustAmp) || ~isfinite(robustAmp) || robustAmp == 0
        robustAmp = 1; % all-NaN or all-zero dataset -- nothing to scale meaningfully, avoid a divide-by-zero
    end
    autoScale = 0.8 * rowHeight / robustAmp; % a typical trace fills ~80% of one row at gain=1
    channelColorOrder = get(groot, 'defaultAxesColorOrder'); % see channelStyle

    % As many side-by-side columns as it takes to keep every column to at
    % most 16 channels, so each trace keeps a readable amount of vertical
    % room regardless of montage size (a 64-channel dataset gets 4 columns
    % of 16, not one column of 64). Split as evenly as possible (columns
    % differ by at most one channel), not "fill each column to 16 before
    % starting the next", so no column ends up conspicuously shorter than
    % its neighbours.
    maxPerColumn = 16;
    numColumns = max(1, ceil(nChan / maxPerColumn));
    columnBounds = round(linspace(0, nChan, numColumns + 1));
    columnChans = cell(1, numColumns);
    for k = 1:numColumns
        columnChans{k} = (columnBounds(k) + 1):columnBounds(k + 1);
    end

    figWidth = min(1800, max(1180, 320 * numColumns));
    fig = uifigure('Name', 'Manually reject trials/channels', 'Position', [100 100 figWidth 660], 'Color', bgColor);
    root = uigridlayout(fig, [2 1], 'RowHeight', {40, '1x'}, 'Padding', [0 0 0 0], 'RowSpacing', 0);
    uilabel(root, 'Text', '  Manually reject trials/channels', 'FontSize', 14, 'FontWeight', 'bold', ...
        'FontColor', [1 1 1], 'BackgroundColor', accentColor, 'VerticalAlignment', 'center');
    outer = uigridlayout(root, [4 1], 'RowHeight', {'fit', 40, '1x', 76}, 'Padding', [10 10 10 10], 'RowSpacing', 8);

    uilabel(outer, 'Text', ['Click a channel''s trace or its label to flag it faulty for the trial shown. ' ...
        'Walk through every trial with Prev/Next (or the left/right arrow keys), and use Scale if the ' ...
        'traces look too flat or too large, before clicking OK.'], 'WordWrap', 'on');

    navRow = uigridlayout(outer, [1 6], 'ColumnWidth', {90, 'fit', '1x', 50, 160, 90}, ...
        'Padding', [0 0 0 0], 'ColumnSpacing', 8);
    navRow.Layout.Row = 2;
    prevBtn = uibutton(navRow, 'Text', '< Prev', 'ButtonPushedFcn', @(~, ~) stepTrial(-1));
    trialLabel = uilabel(navRow, 'Text', '', 'FontWeight', 'bold', 'HorizontalAlignment', 'center');
    uilabel(navRow, 'Text', ''); % spacer, keeps Scale/Next pinned to the right regardless of trialLabel's width
    scaleLabel = uilabel(navRow, 'Text', 'Scale 1.0x', 'HorizontalAlignment', 'right');
    scaleSlider = uislider(navRow, 'Limits', [0.1 8], 'Value', 1, ...
        'MajorTicks', [0.1 1 2 4 8], 'MajorTickLabels', {'0.1x', '1x', '2x', '4x', '8x'}, ...
        'ValueChangingFcn', @(~, ev) setGain(ev.Value));
    nextBtn = uibutton(navRow, 'Text', 'Next >', 'ButtonPushedFcn', @(~, ~) stepTrial(1));

    if numColumns > 1
        plotArea = uigridlayout(outer, [1 numColumns], 'Padding', [0 0 0 0], 'ColumnSpacing', 6);
        plotArea.Layout.Row = 3;
    else
        plotArea = outer; % a single column draws straight into outer's own row 3, no extra wrapping grid needed
    end
    axList = gobjects(1, numColumns);
    for k = 1:numColumns
        axList(k) = makeAxes(plotArea);
    end
    if numColumns == 1
        axList(1).Layout.Row = 3;
    end

    bottomArea = uigridlayout(outer, [2 1], 'RowHeight', {28, 36}, 'Padding', [0 0 0 0], 'RowSpacing', 8);
    bottomArea.Layout.Row = 4;

    settingsRow = uigridlayout(bottomArea, [1 5], 'ColumnWidth', {'fit', 160, 'fit', 160, '1x'}, ...
        'Padding', [0 0 0 0], 'ColumnSpacing', 8);
    uilabel(settingsRow, 'Text', 'Reject:');
    scopeDrop = uidropdown(settingsRow, 'Items', {'Whole epoch', 'This channel only'}, ...
        'Value', priorScope, 'ValueChangedFcn', @(~, ~) applyScopeState());
    channelModeLabelText = uilabel(settingsRow, 'Text', 'Single-channel treatment:');
    channelModeDrop = uidropdown(settingsRow, 'Items', {'NaN', 'Interpolate'}, 'Value', priorChannelMode);
    countLabel = uilabel(settingsRow, 'Text', '', 'HorizontalAlignment', 'right', 'FontColor', [0.4 0.4 0.4]);

    bottomRow = uigridlayout(bottomArea, [1 2], 'ColumnWidth', {'1x', 'fit'}, 'Padding', [0 0 0 0], 'ColumnSpacing', 8);
    uibutton(bottomRow, 'Text', 'Cancel', 'ButtonPushedFcn', @(~, ~) onCancel());
    okBtn = uibutton(bottomRow, 'Text', 'OK', 'BackgroundColor', accentColor, 'FontColor', [1 1 1], ...
        'ButtonPushedFcn', @(~, ~) onOK());
    okBtn.Layout.Column = 2;

    fig.CloseRequestFcn = @(~, ~) onCancel();
    fig.KeyPressFcn = @(~, ev) onKey(ev);

    applyScopeState();
    stepTrial(0);

    uiwait(fig);

    function ax = makeAxes(parent)
        ax = uiaxes(parent);
        ax.Color = bgColor;
        ax.YTick = [];
        ax.Toolbar.Visible = 'off';
        disableDefaultInteractivity(ax);
        xlabel(ax, 'Time (ms)');
    end

    function stepTrial(delta)
        trial = min(nTrials, max(1, trial + delta));
        drawTrial();
    end

    function setGain(newGain)
        gain = newGain;
        scaleLabel.Text = sprintf('Scale %.1fx', gain);
        drawTrial();
    end

    function onKey(ev)
        switch lower(ev.Key)
            case 'leftarrow'
                stepTrial(-1);
            case 'rightarrow'
                stepTrial(1);
        end
    end

    function applyScopeState()
        singleChannel = strcmp(scopeDrop.Value, 'This channel only');
        channelModeDrop.Enable = singleChannel;
        channelModeLabelText.Enable = singleChannel;
    end

    function drawTrial()
        data = squeeze(EEG.data(:, :, trial));
        if nChan == 1
            data = data(:)'; % squeeze collapses a 1-channel trial to a plain column; force it back to a row
        end
        for k = 1:numColumns
            drawColumn(axList(k), columnChans{k}, data);
        end

        trialLabel.Text = sprintf('Trial %d of %d', trial, nTrials);
        countLabel.Text = sprintf('%d channel-trial(s) flagged', nnz(flags));
        prevBtn.Enable = trial > 1;
        nextBtn.Enable = trial < nTrials;
    end

    function drawColumn(ax, chanIdx, data)
    %DRAWCOLUMN  Every channel in CHANIDX, stacked top-to-bottom in AX,
    %   channel 1 of this column at the top -- its own offsets, so every
    %   column gets the same per-row headroom regardless of how many
    %   columns there are or how many channels landed in this one.
        cla(ax);
        n = numel(chanIdx);
        if n == 0
            return;
        end
        offsets = (n - (1:n)') * rowHeight;
        marginX = 0.09 * (times(end) - times(1));

        columnData = data(chanIdx, :);
        if all(isnan(columnData(:)))
            text(ax, mean(times), rowHeight * (n - 1) / 2, ...
                'This trial has no usable data here (already rejected upstream).', ...
                'HorizontalAlignment', 'center', 'Color', [0.5 0.5 0.5], 'FontAngle', 'italic');
            xlim(ax, [times(1) - marginX, times(end)]);
            ylim(ax, [-rowHeight, rowHeight * n]);
            title(ax, sprintf('Trial %d of %d', trial, nTrials));
            return;
        end

        hold(ax, 'on');
        for i = 1:n
            c = chanIdx(i);
            [col, weight] = channelStyle(c);
            y = data(c, :) * autoScale * gain + offsets(i);
            plot(ax, times, y, 'Color', col, 'LineWidth', 1, ...
                'ButtonDownFcn', @(~, ~) toggleChannel(c));
            text(ax, times(1) - 0.015 * (times(end) - times(1)), offsets(i), labels{c}, ...
                'HorizontalAlignment', 'right', 'VerticalAlignment', 'middle', ...
                'Color', col, 'FontWeight', weight, 'FontSize', 9, ...
                'ButtonDownFcn', @(~, ~) toggleChannel(c));
        end
        hold(ax, 'off');
        xlim(ax, [times(1) - marginX, times(end)]);
        ylim(ax, [offsets(end) - rowHeight, offsets(1) + rowHeight]);
        title(ax, sprintf('Trial %d of %d', trial, nTrials));
    end

    function [col, weight] = channelStyle(c)
    %CHANNELSTYLE  A flagged channel is always plain red/bold, so a flag
    %   reads unambiguously regardless of the channel's own colour.
    %   Unflagged, each channel keeps one consistent colour across every
    %   trial and column -- MATLAB's own default axes colour order,
    %   cycled by channel number -- matching the continuous-data view
    %   (SignalView), which colours its own per-channel traces the same
    %   way (each plot() call left to auto-advance through that same
    %   default order).
        if flags(c, trial)
            col = [0.80 0.15 0.15]; weight = 'bold';
        else
            col = channelColorOrder(mod(c - 1, size(channelColorOrder, 1)) + 1, :);
            weight = 'normal';
        end
    end

    function toggleChannel(c)
        flags(c, trial) = ~flags(c, trial);
        drawTrial();
    end

    function onOK()
        options = struct('flags', flags, 'scope', scopeDrop.Value, 'channelMode', channelModeDrop.Value);
        uiresume(fig); delete(fig);
    end

    function onCancel()
        options = [];
        uiresume(fig); delete(fig);
    end
end
