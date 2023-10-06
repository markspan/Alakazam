function fig = plotEpochedTimeMultiAverage(data, fig)
    % Multichannel plot epoched
    % channels:time:trial
    % fig  = figure dropped on, or new figure
    % data = dropped data of data to be plotted

    data.channel = 1;
    set(fig, 'KeyPressFcn', @Key_Pressed_epoched_multi_average);
    EEG = get(fig, 'UserData');

    if length(EEG) == 1
        if isfield(EEG, 'channel')
            % Add to plot: data dropped!
            data.channel = EEG.channel;
            data.labels = {data.chanlocs.labels};
            if ~strcmpi(data.id, EEG.id)
                data = {EEG, data};
            end
        else
            % First plot
            data.channel = 1;
            data.labels = {data.chanlocs.labels};
            %data = EEG;
        end
    else

        data.labels = {data.chanlocs.labels};
        EEG{end+1} = data;
        data = EEG;
    end
    set(fig, 'UserData', data);
    plotEpochedTimeMultiAverage_helper(fig);
    axtoolbar('default');
end

function plotEpochedTimeMultiAverage_helper(fig)
    EEGS = get(fig, 'UserData');
    figure(fig.Number)
    clf;
    for i = 1:length(EEGS)
        if (length(EEGS) == 1); EEG = EEGS; else; EEG = EEGS{i}; end
        l = plot(EEG.times, squeeze(EEG.data(EEG.channel, :, :)));
        col = l.Color;
        hold on
        sd = 3 * squeeze(EEG.stErr(EEG.channel, :));
        plot(EEG.times, squeeze(EEG.data(EEG.channel, :, :)) + sd, 'Color', col, 'LineStyle', ':');
        plot(EEG.times, squeeze(EEG.data(EEG.channel, :, :)) - sd, 'Color', col, 'LineStyle', ':');
        patch([EEG.times, fliplr(EEG.times)], ...
              [squeeze(EEG.data(EEG.channel, :, :)) + sd, fliplr(squeeze(EEG.data(EEG.channel, :, :)) - sd)], ...
              col, 'EdgeColor', 'none', 'FaceAlpha', 0.3);
        title("Channel: " + EEG.labels{EEG.channel});
        xline(0, 'Color', 'k', 'LineStyle', '--');
        yline(0, 'Color', 'k', 'LineStyle', '--');
        box off;
        xlim([min(EEG.times), max(EEG.times)]);
        ylim([min(min(EEG.data(:, :, :))), max(max(EEG.data(:, :, :)))]);
    end
end

function Key_Pressed_epoched_multi_average(fig, evnt)
    hold off;
    uds = get(fig, 'UserData');
    for i = 1:length(uds)
        if (length(uds) == 1); ud = uds; else; ud = uds{i}; end
        if strcmpi(evnt.Key, 'uparrow') % previous channel
            ud.channel = max(1, ud.channel - 1);
        end
        if strcmpi(evnt.Key, 'downarrow') % next channel
            ud.channel = min(size(ud.data, 1), ud.channel + 1);
        end
        if length(uds) > 1
            uds{i} = ud;
        else
            uds = ud;
        end
    end
    set(fig, 'UserData', uds);
    plotEpochedTimeMultiAverage_helper(fig);
end