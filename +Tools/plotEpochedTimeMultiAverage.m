function plotEpochedTimeMultiAverage(data, fig)
    % Multichannel plot epoched
    % channels:time:trial
    set(fig, 'KeyPressFcn',@Key_Pressed_epoched_multi_average);
    data.channel=1;
    data.labels = {data.chanlocs.labels};
    set(fig, 'UserData', data);
    plot_etm(); % averaged over trials, one channel
    axtoolbar('default');   
end

    function plot_etm()
    ud = get(gcf, 'UserData');
    plot(ud.times, squeeze(ud.data(ud.channel,:,:)));
    hold on
    sd = squeeze(ud.stDev(ud.channel,:));
    plot(ud.times, squeeze(ud.data(ud.channel,:,:)) + sd, 'b:');
    plot(ud.times, squeeze(ud.data(ud.channel,:,:)) - sd, 'b:');
    
    title("Channel: " + ud.labels{ud.channel});
    hold off
    xlim([min(ud.times), max(ud.times)])
end

function Key_Pressed_epoched_multi_average(~,evnt)
    ud = get(gcf, 'UserData');
    if strcmpi(evnt.Key, 'uparrow') % previous channel
        ud.channel = max(1, ud.channel - 1);
        set(gcf, 'UserData', ud)
        plot_etm();
    end
    if strcmpi(evnt.Key, 'downarrow') % next channel
        ud.channel = min(size(ud.data,1), ud.channel + 1);
        set(gcf, 'UserData', ud)
        plot_etm();
    end
end
