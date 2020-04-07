function ShowSliders()
%ShowSliders Activates the sliders in the EEG plot of ALAKAZAM
%   Simple helper function with no parameters.
%   Will activate the sliders only if they exist. 

s=findobj('Tag', 'Scroll');
if ~isempty(s)
    set(s, 'Visible', 'on');
end
s=findobj('Tag', 'Zoom');
if ~isempty(s)
    set(s, 'Visible', 'on');
end
s=findobj('Tag', 'Scale');
if ~isempty(s)
    set(s, 'Visible', 'on');
end

