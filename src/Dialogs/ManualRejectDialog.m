function options = ManualRejectDialog(EEG, prior)
%MANUALREJECTDIALOG  Alakazam-styled manual trial/channel rejection browser.
%
%   Shows one trial's full channel montage at a time (every channel stacked,
%   sharing one amplitude scale across the whole dataset so paging between
%   trials is an eye-to-eye comparison), with Prev/Next (or the left/right
%   arrow keys) to walk through trials. Click a channel's trace or its label
%   to toggle it flagged for the trial currently shown; a flagged channel
%   turns red and stays flagged when you page away and back. This is the
%   manual counterpart of ArtefactDetect's own automatic thresholds -- the
%   analyst's eye instead of a fixed number.
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

    [nChan, nSamp, nTrials] = size(EEG.data); %#ok<ASGLU>
    times  = EEG.times;
    labels = {EEG.chanlocs.labels};
    trial  = 1;

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

    % One shared, symmetric amplitude scale across the whole dataset (every
    % channel, every trial), not autoscaled per trial: the same "eye-to-eye
    % paging comparison" principle EpochView's own header comment explains
    % for its per-channel colour scale -- here a channel that looks
    % dramatically bigger in trial 12 than trial 3 should look that way
    % because it IS bigger, not because the axes silently rescaled.
    scaleLim = max(abs(EEG.data(:)), [], 'omitnan');
    if ~isfinite(scaleLim) || scaleLim == 0
        scaleLim = 1;
    end
    spacing = 2.6 * scaleLim;
    offsets = (nChan - (1:nChan)') * spacing; % channel 1 drawn at the top

    fig = uifigure('Name', 'Manually reject trials/channels', 'Position', [100 100 980 620], 'Color', bgColor);
    root = uigridlayout(fig, [2 1], 'RowHeight', {40, '1x'}, 'Padding', [0 0 0 0], 'RowSpacing', 0);
    uilabel(root, 'Text', '  Manually reject trials/channels', 'FontSize', 14, 'FontWeight', 'bold', ...
        'FontColor', [1 1 1], 'BackgroundColor', accentColor, 'VerticalAlignment', 'center');
    outer = uigridlayout(root, [4 1], 'RowHeight', {'fit', 40, '1x', 76}, 'Padding', [10 10 10 10], 'RowSpacing', 8);

    uilabel(outer, 'Text', ['Click a channel''s trace or its label to flag it faulty for the trial shown. ' ...
        'Walk through every trial with Prev/Next (or the left/right arrow keys) before clicking OK.'], ...
        'WordWrap', 'on');

    navRow = uigridlayout(outer, [1 4], 'ColumnWidth', {90, 'fit', '1x', 90}, 'Padding', [0 0 0 0], 'ColumnSpacing', 8);
    navRow.Layout.Row = 2;
    prevBtn = uibutton(navRow, 'Text', '< Prev', 'ButtonPushedFcn', @(~, ~) stepTrial(-1));
    trialLabel = uilabel(navRow, 'Text', '', 'FontWeight', 'bold', 'HorizontalAlignment', 'center');
    countLabel = uilabel(navRow, 'Text', '', 'HorizontalAlignment', 'right', 'FontColor', [0.4 0.4 0.4]);
    nextBtn = uibutton(navRow, 'Text', 'Next >', 'ButtonPushedFcn', @(~, ~) stepTrial(1));

    ax = uiaxes(outer);
    ax.Layout.Row = 3;
    ax.Color = bgColor;
    ax.YTick = [];
    ax.Toolbar.Visible = 'off';
    disableDefaultInteractivity(ax);
    xlabel(ax, 'Time (ms)');

    bottomArea = uigridlayout(outer, [2 1], 'RowHeight', {28, 36}, 'Padding', [0 0 0 0], 'RowSpacing', 8);
    bottomArea.Layout.Row = 4;

    settingsRow = uigridlayout(bottomArea, [1 4], 'ColumnWidth', {'fit', 160, 'fit', 160}, ...
        'Padding', [0 0 0 0], 'ColumnSpacing', 8);
    uilabel(settingsRow, 'Text', 'Reject:');
    scopeDrop = uidropdown(settingsRow, 'Items', {'Whole epoch', 'This channel only'}, ...
        'Value', priorScope, 'ValueChangedFcn', @(~, ~) applyScopeState());
    channelModeLabelText = uilabel(settingsRow, 'Text', 'Single-channel treatment:');
    channelModeDrop = uidropdown(settingsRow, 'Items', {'NaN', 'Interpolate'}, 'Value', priorChannelMode);

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

    function stepTrial(delta)
        trial = min(nTrials, max(1, trial + delta));
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
        cla(ax);
        data = squeeze(EEG.data(:, :, trial));
        if nChan == 1
            data = data(:)'; % squeeze collapses a 1-channel trial to a plain column; force it back to a row
        end
        hold(ax, 'on');
        marginX = 0.09 * (times(end) - times(1));
        for c = 1:nChan
            [col, weight] = channelStyle(c);
            y = data(c, :) + offsets(c);
            plot(ax, times, y, 'Color', col, 'LineWidth', 1, ...
                'ButtonDownFcn', @(~, ~) toggleChannel(c));
            text(ax, times(1) - 0.015 * (times(end) - times(1)), offsets(c), labels{c}, ...
                'HorizontalAlignment', 'right', 'VerticalAlignment', 'middle', ...
                'Color', col, 'FontWeight', weight, 'FontSize', 9, ...
                'ButtonDownFcn', @(~, ~) toggleChannel(c));
        end
        hold(ax, 'off');
        xlim(ax, [times(1) - marginX, times(end)]);
        ylim(ax, [offsets(end) - spacing, offsets(1) + spacing]);
        title(ax, sprintf('Trial %d of %d', trial, nTrials));

        trialLabel.Text = sprintf('Trial %d of %d', trial, nTrials);
        countLabel.Text = sprintf('%d channel-trial(s) flagged', nnz(flags));
        prevBtn.Enable = trial > 1;
        nextBtn.Enable = trial < nTrials;
    end

    function [col, weight] = channelStyle(c)
        if flags(c, trial)
            col = [0.80 0.15 0.15]; weight = 'bold';
        else
            col = [0.25 0.25 0.25]; weight = 'normal';
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
