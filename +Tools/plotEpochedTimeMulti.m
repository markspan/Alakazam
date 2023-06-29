function plotEpochedTimeMulti(data, fig)
    % Multichannel plot epoched
    % channels:time:trial
    set(fig, 'KeyPressFcn',@Key_Pressed_epoched_multi);
    data.channel=1;
    data.trial = 1;
    data.labels = {data.chanlocs.labels};
    data.legend = true;
    set(fig, 'UserData', data);
    plot_etm(1); % all trials, one channel
    axtoolbar('default'); 
end

function plot_etm(mode)
    ud = get(gcf, 'UserData');
    if mode == 1 % all trials, one channel
        plot(ud.times, squeeze(ud.data(ud.channel,:,:)));
        title("Channel: " + ud.labels{ud.channel});
        N=1:size(ud.data,3);
        legendCell = cellstr(num2str(N', 'Trial=%-d'));
        legend(legendCell, ...
            'NumColumns', ceil(size(ud.data,3)/35), ...
            'Location', 'northeast');
    end
    if mode == 2 % all channels, one trial
        plot(ud.times, squeeze(ud.data(:,:,ud.trial)));
        title("Trial: " + ud.trial)
        legend(ud.labels, 'NumColumns', ...
            ceil(length(ud.labels)/35), ...            
            'Location', 'northeast')
    end

    hLeg=findobj(gcf,'type','legend');
    if (ud.legend)
        set(hLeg,'visible','on')
    else
        set(hLeg,'visible','off')
    end

    ud.mode = mode;
    set(gcf, 'UserData', ud);
end

function Key_Pressed_epoched_multi(~,evnt)
    
    ud = get(gcf, 'UserData');
    if strcmpi(evnt.Key, 'uparrow') % previous channel
        ud.channel = max(1, ud.channel - 1);
        ud.mode = 1;
        set(gcf, 'UserData', ud)
    end
    if strcmpi(evnt.Key, 'downarrow') % next channel
        ud.channel = min(size(ud.data,1), ud.channel + 1);
        ud.mode = 1;
        set(gcf, 'UserData', ud)
    end
    if strcmpi(evnt.Key, 'leftarrow') % previous trial
        ud.trial = max(1,ud.trial-1);
        ud.mode = 2;
        set(gcf, 'UserData', ud)
    end
    if strcmpi(evnt.Key, 'rightarrow') % next trial
        ud.trial = min(size(ud.data,3), ud.trial + 1);
        ud.mode = 2;
        set(gcf, 'UserData', ud)
    end
    if strcmpi(evnt.Key, 'l') % legend toggle
        ud.legend = ~ud.legend
        set(gcf, 'UserData', ud);
    end
    plot_etm(ud.mode);
end
