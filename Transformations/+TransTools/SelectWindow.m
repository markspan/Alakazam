function h = SelectWindow(handles)
DWR = findobj('Tag', 'DataWindowRadio');
handles.options.Window = get(get(DWR, 'SelectedObject'),'Tag');
handles.options.Window_Length = str2double(get(handles.WinLen,'String'));

type = handles.options.Window;

prev = zeros(100,1)+1;
if (strcmpi(type, 'No'))
    prev = zeros(100,1)+1;
end
if (strcmpi(type, 'Hanning'))
    prev = hanning(100);
end
if (strcmpi(type, 'Hamming'))
    prev = hamming(100);
end
if (strcmpi(type, 'OtherWin'))
    contents = get(handles.OtherWindowType,'String');
    win = contents{get(handles.OtherWindowType,'Value')};
    if (strcmpi(win, 'bartlett' ))
        handles.options.Window = 'bartlett';
        prev = bartlett(100);
    end
    if (strcmpi(win, 'blackmanharris' ))
        handles.options.Window = 'blackmanharris';
        prev = blackmanharris(100);
    end
    if (strcmpi(win, 'bohmanwin' ))
        handles.options.Window = 'bohmanwin';
        prev = bohmanwin(100);
    end
    if (strcmpi(win, 'nuttallwin' ))
        handles.options.Window = 'nuttallwin';
        prev = nuttallwin(100);
    end
    if (strcmpi(win, 'parzenwin' ))
        handles.options.Window = 'parzenwin';
        prev = parzenwin(100);
    end
    if (strcmpi(win, 'rectwin' ))
        handles.options.Window = 'rectwin';
        prev = rectwin(100);
    end
    if (strcmpi(win, 'triang' ))
        handles.options.Window = 'triang';
        prev = triang(100);
    end
end

len = handles.options.Window_Length;
winPreview = [prev(1:length(prev)/2)' zeros(1, (1000-(10*len)))+1 prev(length(prev)/2:end)'];
plot(handles.WindowPreview, (1:length(winPreview))/length(winPreview), winPreview , 'black');

set (handles.WindowPreview,'XLim', [0 1]);
set (handles.WindowPreview,'YLim', [0 1]);

set (handles.WindowPreview,'XTick', [0 1]);
set (handles.WindowPreview,'YTick', [0 1]);
h=handles;