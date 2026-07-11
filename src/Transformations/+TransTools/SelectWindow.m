function h = SelectWindow(handles)
DWR = findobj('Tag', 'DataWindowRadio');
handles.options.Window = get(get(DWR, 'SelectedObject'),'Tag');
handles.options.Window_Length = str2double(get(handles.WinLen,'String'));

type = handles.options.Window;

if (strcmpi(type, 'OtherWin'))
    contents = get(handles.OtherWindowType,'String');
    type = contents{get(handles.OtherWindowType,'Value')};
    handles.options.Window = type;
end

% Fixed 100-sample preview shape regardless of Window_Length: the preview
% is proportional, not a literal render of the real analysis window (that
% one is sized to the loaded signal in Fourier.m, which this preview has
% no access to) -- Window_Length instead controls how much of the fixed
% 1000-unit preview canvas the flat (untapered) middle occupies below, the
% same fraction-of-total-length semantics as Fourier.m's own
% sizeofwin/nsamp ratio.
prev = TransTools.WindowByName(type, 100);

len = handles.options.Window_Length;
winPreview = [prev(1:length(prev)/2)' zeros(1, (1000-(10*len)))+1 prev(length(prev)/2:end)'];
plot(handles.WindowPreview, (1:length(winPreview))/length(winPreview), winPreview , 'black');

set (handles.WindowPreview,'XLim', [0 1]);
set (handles.WindowPreview,'YLim', [0 1]);

set (handles.WindowPreview,'XTick', [0 1]);
set (handles.WindowPreview,'YTick', [0 1]);
h=handles;