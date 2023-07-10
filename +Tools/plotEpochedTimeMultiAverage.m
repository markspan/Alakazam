function plotEpochedTimeMultiAverage(data, fig)
    % Multichannel plot epoched
    % channels:time:trial
    set(fig, 'KeyPressFcn',@Key_Pressed_epoched_multi_average);
    ud = get(gcf, 'UserData');
    
    if isfield(ud, 'channel')
        data.channel = ud.channel;
    else
        data.channel=1;
    end
    
    data.labels = {data.chanlocs.labels};

    set(fig, 'UserData', data);
    plot_etm(); % averaged over trials, one channel
    axtoolbar('default');   
end

function plot_etm()
    ud = get(gcf, 'UserData');
    l=plot(ud.times, squeeze(ud.data(ud.channel,:,:)));
    col=l.Color;
    hold on
    sd = 3 * squeeze(ud.stErr(ud.channel,:));
    plot(ud.times, squeeze(ud.data(ud.channel,:,:)) + sd, 'Color', col, 'LineStyle', ':');
    plot(ud.times, squeeze(ud.data(ud.channel,:,:)) - sd, 'Color', col, 'LineStyle', ':');
    patch([ud.times, fliplr(ud.times)], ...
        [squeeze(ud.data(ud.channel,:,:)) + sd, fliplr(squeeze(ud.data(ud.channel,:,:)) - sd)], ...
        col, 'EdgeColor', 'none', 'FaceAlpha', .3)
    title("Channel: " + ud.labels{ud.channel});
    xline(0,'Color', 'k', 'LineStyle','--')
    yline(0,'Color', 'k', 'LineStyle','--')
    box off
    hold off
    xlim([min(ud.times), max(ud.times)])
    ylim([min(min(ud.data(:,:,:))) max(max(ud.data(:,:,:)))])
end

function Key_Pressed_epoched_multi_average(~,evnt)
    ud = get(gcf, 'UserData');
    if strcmpi(evnt.Key, 'uparrow') % previous channel
        ud.channel = max(1, ud.channel - 1);
    end
    if strcmpi(evnt.Key, 'downarrow') % next channel
        ud.channel = min(size(ud.data,1), ud.channel + 1);
    end
    set(gcf, 'UserData', ud)
    plot_etm();
end
