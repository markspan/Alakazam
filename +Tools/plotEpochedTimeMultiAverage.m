function fig = plotEpochedTimeMultiAverage(data, fig)
    % Multichannel plot epoched
    % channels:time:trial
    % fig  = figure dropped on, or new figure
    % data = dropped data of data to be plotted

    data.channel = 1;
    set(fig, 'KeyPressFcn', @Key_Pressed_epoched_multi_average);
    ud = get(fig, 'UserData');

    if length(ud) == 1
        if isfield(ud, 'channel')
            % Add to plot: data dropped!
            data.channel = ud.channel;
            data.labels = {data.chanlocs.labels};
            if ~strcmpi(data.id, ud.id)
                data = {ud, data};
            end
        else
            % First plot
            data.channel = 1;
            data.labels = {data.chanlocs.labels};
        end
    end

    set(fig, 'UserData', data);
    plotEpochedTimeMultiAverage_helper(fig);
    axtoolbar('default');
end

function plotEpochedTimeMultiAverage_helper(fig)
    uds = get(fig, 'UserData');
    figure(fig.Number)
    clf;
    for i = 1:length(uds)
        if length(uds) == 1
            ud = uds;
        else
%             if i == length(uds)
%                 % Break
%                 break;
%             end
            ud = uds{i};
        end

        l = plot(ud.times, squeeze(ud.data(ud.channel, :, :)));
        col = l.Color;
        hold on

        sd = 3 * squeeze(ud.stErr(ud.channel, :));
        plot(ud.times, squeeze(ud.data(ud.channel, :, :)) + sd, 'Color', col, 'LineStyle', ':');
        plot(ud.times, squeeze(ud.data(ud.channel, :, :)) - sd, 'Color', col, 'LineStyle', ':');
        patch([ud.times, fliplr(ud.times)], ...
              [squeeze(ud.data(ud.channel, :, :)) + sd, fliplr(squeeze(ud.data(ud.channel, :, :)) - sd)], ...
              col, 'EdgeColor', 'none', 'FaceAlpha', 0.3);

        title("Channel: " + ud.labels{ud.channel});
        xline(0, 'Color', 'k', 'LineStyle', '--');
        yline(0, 'Color', 'k', 'LineStyle', '--');
        box off;

        xlim([min(ud.times), max(ud.times)]);
        ylim([min(min(ud.data(:, :, :))), max(max(ud.data(:, :, :)))]);
    end
end

function Key_Pressed_epoched_multi_average(fig, evnt)
    hold off;
    uds = get(fig, 'UserData');
    for i = 1:length(uds)
        if length(uds) == 1
            ud = uds;
        else
            ud = uds{i};
        end

        if strcmpi(evnt.Key, 'uparrow') % previous channel
            ud.channel = max(1, ud.channel - 1);
        end
        if strcmpi(evnt.Key, 'downarrow') % next channel
            ud.channel = min(size(ud.data, 1), ud.channel + 1);
        end

        if length(uds) > 1
            uds{i} = ud;
        end
    end

    set(fig, 'UserData', uds);
    plotEpochedTimeMultiAverage_helper(fig);
end