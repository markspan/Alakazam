function varargout=jplot(varargin)
% jplot(x)
% jplot(x,y)
% jplot(x,y,PropertyName,PropertyValue)
% h=jplot(...)
%
% This function is a minimal wrapper for the matlab plot function with automatic downsampling at low zoom factors
% and cropping at high zoom factors for faster zoom and pan.
% It works in subplots and can be combined with normals plots of any kind in the same axes.
%
% The amount of downsampling can be changed by adjusting the value of MAXPOINTS.
% Lines with less than MAXPOINTS are plotted normally.
% jplotting of multiple lines at once is allowed up to MAXHANDLES (otherwise everything is plotted normally). Adjust as necessary.
%
% Note that jplot uses the 'tag' and 'userdata' properties of the plotted lines.
% v1.0 Jake Reimer 6/11/2013
% v1.1 Jake Reimer 6/12/2013 Takes initial xL as [min(x) max(x)] rather than initial xlims so that
%                            downsampling works even if you're zoomed into the axis when you jplot.  

MAXPOINTS=1E1;
MAXHANDLES=100;
%%
if nargin==0
    return
elseif nargin==1
    y=varargin{1};
    x=1:length(y);
    mods={};
elseif nargin==2
    x=varargin{1};
    y=varargin{2};
    mods={};
else
    x=varargin{1};
    y=varargin{2};
    mods = varargin(3:end);
end

h=plot(x,y,mods{:});

if nargout
    varargout{1}=h;
end

hZoom = zoom(gcf);
hPan = pan(gcf);
set(hZoom, 'ActionPostCallback', @zoomCallback);
set(hPan , 'ActionPostCallback', @panCallback);

if length(h) < MAXHANDLES
    for i=1:length(h)
        x=get(h(i),'xdata');
        len = length(x);
        if len > MAXPOINTS
            y=get(h(i),'ydata');
            
            raw.x=x;
            raw.y=y;
            raw.xL=[min(x) max(x)];
            raw.maxPoints=MAXPOINTS;
            
            set(h(i),'userdata',raw,'tag','dec');
            dec = ceil(len/MAXPOINTS);
            
            set(h(i),'xdata',x(1:dec:end),'ydata',y(1:dec:end));
        end
    end
end
end

function zoomCallback(~,ev)

if strcmp(get(gcf,'selectiontype'),'normal')
    xL=get(ev.Axes,'xlim');
else
    xL=[-inf inf];
end

h=findobj(ev.Axes,'tag','dec');

for i=1:length(h)
    raw=get(h(i),'userdata');
    len = length(raw.x);
    ind = [find(raw.x>=xL(1)-diff(xL),1,'first') find(raw.x<=xL(2)+diff(xL),1,'last')];
    dec = ceil(len/raw.maxPoints);
    if ~isinf(diff(xL))
        dec = floor(dec * (diff(xL)/diff(raw.xL)))+1;
    end
    
    set(h(i),'xdata',raw.x(ind(1):dec:ind(2)),'ydata',raw.y(ind(1):dec:ind(2)));
end

drawnow

end

function panCallback(~,ev)

xL=get(ev.Axes,'xlim');

h=findobj(ev.Axes,'tag','dec');

for i=1:length(h)
    raw=get(h(i),'userdata');
    len = length(raw.x);
    ind = [find(raw.x>=xL(1)-diff(xL),1,'first') find(raw.x<=xL(2)+diff(xL),1,'last')];
    dec = ceil(len/raw.maxPoints);
    dec = floor(dec * (diff(xL)/diff(raw.xL)))+1;
    
    set(h(i),'xdata',raw.x(ind(1):dec:ind(2)),'ydata',raw.y(ind(1):dec:ind(2)));
end

drawnow

end