function [ varargout ] = plotEEG2( varargin )
Tools.ShowSliders
% -------------------------------------------------------
%    Based on
%
%    plotECG( X,Y, varargin ) ? Plot Very Long, Multichannel Signals ? Zoom & Scroll via Slider
%
%    Enables you to plot and zoom & scroll through signals with millions of samples.
%    There is one slider for scrolling and one for zooming.
%
%
%    Ver. 1.1.0
%
%    Created:         Daniel Frisch        (15.02.2015)
%    Last modified:   Daniel Frisch        (25.09.2016)
%
%
% -------------------------------------------------------
%
%
%   Input Arguments
%     X                     Vector of timesteps, or scalar sample rate. scalar or [N x 1] double
%     Y                     Signal vector, or signal matrix where each column represents one signal. [N x m] double
%     LineSpec              LineSpec string, max. 4 characters, see Matlab plot() documentation. string (optional, default: '.')
%                           If you define a marker here, set 'AutoMarkers' to 'none' so it won't be overridden.
%
%     Key-Value Parameters  (optional):
%       mmPerSec            Initial zoom in screen millimeters per second. scalar double (default: 50)
%                           If you change the figure size in this mode, the axis XLim will change such that mmPerSec stays the same.
%       secPerScreenWidth   Initial zoom setting in seconds that are displayed on screen at a time. scalar double
%                           If you change the figure size in this mode, the signal scale will change too, such that XLim stays the same.
%       ShowAxisTicks       Shows the axis ticks and labels and a grid. string, 'on' or 'off' (default: 'on')
%                           You can also change axis properties on the returned handles: hs.ax.XLabel.String = 'Seconds';
%       ShowInformationList Shows information about the location of the last clicks in the signal. function_handle or string
%                           Specify one of 'none' (default), 'std_InformationList', 'ecg_InformationList', as string,
%                           or define an own function like those with two inputs and cell output and pass its name or function_handle.
%                           Mouse clicks are captured only if no interactive mode (pan, zoom etc.) is active in the figure.
%       AutoStackSignals    Cell array of strings with signal names. Length must be equal to number of columns of Y, or 0. (default: {})
%                           Stacks the signals vertically, so for example a multipolar ECG can be shown.
%                           Example: {'I','II','III', 'aVR','aVL','aVF', 'V1','V2','V3','V4','V5','V6'}
%       SecondXAxisFunction Function handle that maps from the provided X values to a different x axis scale
%                           that will be displayed above the plotted signal. function_handle or string (default: 'none')
%                           Example: @(x)x/60^2, shows the time also in hours.
%       SecondXAxisLabel    Label of second x axis. Example: 'Time in h'. string (default: '')
%       YLimMode            'dynamic': dynamic y axis limits according to minimum and maximum of currently visible signal (default)
%                           'fixed'  : fixed y axis limits according to minimum and maximum of entire signal.
%                           In 'fixed' mode, you shouldn't apply filters that change the signal's mean much because YLim won't be updated.
%                           You can change the fixed interval afterwards using the returned axes handle: hs.ax.YLim = [-10,10];
%       AutoMarkers         Automatically shows the specified marker at the sample locations if you zoom in such that there are
%                           more than 5 pixes per sample. Use 'none' to disable this behaviour. string (default: '.')
%       ColorOrder          Custom ColorOrder for axes properties. [N x 3] double
%       ScrollCallback      Function handle that will be called when the signal is scrolled or zoomed. function_handle or string (default: 'none')
%                           An information structure will be passed to the function, with the fields
%                           - XLim (containing the left and right x-axis value)
%                           - ContinuousValueChange (whether it was called during or at the end of sliding)
%                           To keep the sliding smooth, you should not execute expensive code if ContinuousValueChange is true.
%       Parent              Parent figure. (default: new figure is created)
%                           Use delete(findall(hs.panel)) or close the figure to delete the old plot and its signals.
%                           The 'HandleVisibility' of the figure created by default is set to 'Callback' to prevent you from
%                           plotting into it accidentially from the command line.
%                           To close the created figures from the command line, you have to use "close all hidden" instead of "close all".
%       Units               Units for positioning plotECG in the parent figure. (default: normalized)
%       Position            Position of plotECG in the parent figure. (default: [0,0,1,1])
%
%
%   Output Arguments
%     h                     Returns the chart line objects as a vector. Use h to modify a chart line after it is created.
%     hs                    Returns a struct with handles to some more GUI objects for later modifiaction
%
%     You can set Name-Value parameters on the returned chart line handles:
%     set(h, 'LineWidth',3) etc.
%
%     Furthermore, you might want to change the X/YLabel:
%     hs.ax.XLabel.String = 'Seconds'; or: xlabel(hs.ax,'Seconds')
%
%
%
%   Example
%     X = 0:0.001:100-0.001;
%     Y = sin(2*pi*0.1*X) + sin(2*pi*X) + .1*sin(2*pi*50*X);
%     [h,hs] = plotECG(X,Y);
%     [h,hs] = plotECG(1000,Y, 'Filter','filter_FFT');
%
%% Dependencies
% [flist,plist] = matlab.codetools.requiredFilesAndProducts('plotECG.m'); [flist'; {plist.Name}']

% plotECG(): no dependencies
% built-in local filter function 'filter_bandpass_notch': Signal Processing Toolbox




%% Parse Inputs

args = varargin;
iSig = 1;
SIG = struct;
defaultXLabel = 'Time in s';
mm_default = 50;

if length(args)>=2 && isnumeric(args{1}) && isstruct(args{2})
    SIG.X0 = args{1};
    SIG.EEG = args{2};
    SIG.Y0 = double(args{2}.data);
    
    SIG.Event = struct;
    if isstruct(args{2}.event)
        if isfield(args{2}.event, 'latency') && isfield(args{2}.event, 'code') && isfield(args{2}.event, 'type')
            SIG.Event.Latencies = [args{2}.event.latency]/args{2}.srate;
            SIG.Event.Codes     = {args{2}.event.code};
            SIG.Event.Types     = {args{2}.event.type};
        end
    end
    args = args(3:end);
elseif length(args)>=1 && isnumeric(args{1})
    defaultXLabel = '';
    SIG.Y0 = args{1};
    SIG.X0 = 1;
    args = args(2:end);
    mm_default = 0.001;
else
    return;
end

% Check X and Y and change to column-oriented data
if numel(SIG.X0)==1 % X = sample rate
    validateattributes(SIG.X0,{'double'},{'nonempty','real','finite','scalar','positive'     }, 'plotEEG2','scalar X',1)
else % X = timestamps
    validateattributes(SIG.X0,{'double'},{'nonempty','real','finite','vector','nondecreasing'}, 'plotEEG2','vector X',1)
end
validateattributes(SIG.Y0,{'double'},{'nonempty','real','2d'}, 'plotEEG2','Y')

if size(SIG.X0,1)==1, SIG.X0=SIG.X0'; end % change to column vector
if isrow(SIG.Y0) || ~isscalar(SIG.X0) && size(SIG.Y0,1)~=size(SIG.X0,1)
    SIG.Y0=SIG.Y0';  % each column must be one signal
end

assert(isscalar(SIG.X0) || size(SIG.Y0,1)==size(SIG.X0,1),'Y must have dimensions such that one of its dimensions equals length(X) if X is not a scalar')
assert(size(SIG.Y0,1)>1, 'Signal must have at least two samples')
assert(nnz(~isfinite(SIG.Y0))<numel(SIG.Y0),'Y completely consists of infinite values')
if nnz(~isfinite(SIG.Y0))>.5*numel(SIG.Y0), warning('Y contains %.2f %% infinite values\n',nnz(~isfinite(SIG.Y0))/numel(SIG.Y0)*100); end
assert(nargout<=2,'Maximum 2 (instead of %u) output arguments are possible',nargout)

if isscalar(SIG.X0)
    period = 1/SIG.X0;
else
    period = median(diff(SIG.X0),'omitnan');
    %period = (SIG.X0(end)-SIG.X0(1))/(length(SIG.X0)-1);
end

assert(period>0,'The sampling period must be > 0')
if isscalar(SIG.X0)
    timeBoundary = [0, period*(size(SIG.Y0,1)-1)];
else
    xFinite = isfinite(SIG.X0);
    timeBoundary = [SIG.X0(find(xFinite,1,'first')),SIG.X0(find(xFinite,1,'last'))];
end

duration = diff(timeBoundary);
assert(duration>0,'The duration must be > 0')

lineSpec = '-';
if size(SIG.Y0,2)==1
    lineSpec = '-k';
end

if length(args)>=1 && isLineSpec(args{1})
    lineSpec = args{1};
    args = args(2:end);
end

parser = inputParser;
parser.FunctionName = 'plotEEG2';
TabControl = 0;

parser.addParameter('zoomval'           , .1           , @(x)validateattributes(x,{'double'},{'real','finite','nonnegative','scalar'}))
parser.addParameter('scaleval'          , 1.0          , @(x)validateattributes(x,{'double'},{'real','finite','nonnegative','scalar'}))
parser.addParameter('scrollval'         , 0            , @(x)validateattributes(x,{'double'},{'real','finite','nonnegative','scalar'}))
parser.addParameter('mmPerSec'           , mm_default  , @(x)validateattributes(x,{'double'},{'real','finite','positive','scalar'}))
parser.addParameter('secPerScreenWidth'  , 1           , @(x)validateattributes(x,{'double'},{'real','finite','positive','scalar'}))
parser.addParameter('ShowAxisTicks'      , 'on'        , @(x)any(validatestring(x,{'on','off'})))
parser.addParameter('ShowInformationList', 'none'      , @(x)validateattributes(x,{'char','function_handle'},{'vector','nonempty'}))
parser.addParameter('AutoStackSignals'   , {}          , @(x)iscellstr(x)) %#ok<ISCLSTR>
parser.addParameter('SecondXAxisFunction', 'none'      , @(x)validateattributes(x,{'char','function_handle'},{'vector','nonempty'}))
parser.addParameter('SecondXAxisLabel'   , ''          , @(x)validateattributes(x,{'char'},{}))
parser.addParameter('YLimMode'           , 'dynamic'   , @(x)any(validatestring(x,{'dynamic','fixed'})))
parser.addParameter('AutoMarkers'        , '.'         , @(x)any(validatestring(x,{'+','o','*','.','x','square','diamond','v','^','>','<','pentagram','hexagram','none'})))
parser.addParameter('ColorOrder'         , []          , @(x)validateattributes(x,{'double'},{'real','finite','nonnegative', '<=',1, 'size',[NaN,3]}))
parser.addParameter('ScrollCallback'     , 'none'      , @(x)validateattributes(x,{'char','function_handle'},{'vector','nonempty'}))
parser.addParameter('Parent'             , 0           , @(x)isscalar(x) && isgraphics(x) && x~=0)
parser.addParameter('Units'              , 'normalized', @(x)any(validatestring(x,{'pixels','normalized','inches','centimeters','points','characters'})))
parser.addParameter('Position'           , [0,0,1,1]   , @(x)validateattributes(x,{'double'},{'real','finite','nonnegative', 'size',[1 4]}))
parser.addParameter('TabControl'         , 0           , @(x)isscalar(x))

parser.parse(args{:})

SIG.AutoStackSignals = parser.Results.AutoStackSignals;
if ~isempty(SIG.AutoStackSignals)
    nStr = numel(SIG.AutoStackSignals);
    nSig = size(SIG.Y0,2);
    assert(nStr==nSig, 'You specified %u Strings in ''AutoStackSignals'', but the number of signals in Y is %u.',nStr,nSig);
end


%% Add the GUI components
zoomval = parser.Results.zoomval;
scrollval = parser.Results.scrollval;
scaleval = parser.Results.scaleval;

mmPerSec = [];
secPerScreenWidth = [];
if ismember('secPerScreenWidth',parser.UsingDefaults)
    mmPerSec = parser.Results.mmPerSec;
else
    secPerScreenWidth = parser.Results.secPerScreenWidth;
end

mmPerSec_slider = mmPerSec;
%% propScale_slider = 1;

N = round(duration / period)+1;
axWidth_cm = 100;
axWidth_px = 100;

TabControl = parser.Results.TabControl;

% Layout constants
fontSize = 11;
units = 'centimeters';
space = 0.05;
sliderHeight = .4;

%% checkboxHeight = 1;
%% editWidth = 2;

% Add components, save handles in a struct
hs = struct;
if parser.Results.Parent==0
    hs.parent = figure('Units','normalized', 'OuterPosition',[0.3,0.53,0.65,0.45], 'HandleVisibility','Callback');
else
    hs.parent = parser.Results.Parent;
    clf(hs.parent);
end

% Find parent figure
hs.fig = hs.parent;
while ~isempty(hs.fig) && ~strcmp('figure', get(hs.fig,'type'))
    hs.fig = get(hs.fig,'parent');
end

% Disable all interactive modes.
% Only then the WindowScrollWheelFcn can be set.
rotate3d(hs.fig,'off')
zoom(hs.fig,'off')
pan(hs.fig,'off')
% Now set custom WindowScrollWheelFcn
%hs.fig.WindowScrollWheelFcn = @figScroll;

hs.panel = uipanel(... % This uipanel can be put into another GUI
    'Parent',hs.parent,...
    'Units',parser.Results.Units,...
    'Position',parser.Results.Position,...
    'BorderWidth',1,...
    'SizeChangedFcn',@resizegui,...
    'Visible','off');

hs.ax2 = axes(...
    'Parent',hs.panel,...
    'ActivePositionProperty','Position',...
    'XAxisLocation','top',...
    'YAxisLocation','right',...
    'YTickLabel',{''},...
    'Color','none');
if strcmp(parser.Results.SecondXAxisFunction,'none')
    set(hs.ax2,'Visible','off')
end

hs.ax = axes(...
    'Parent',hs.panel,...
    'TickLabelInterpreter','none',...
    'ActivePositionProperty','Position');
if ~isempty(parser.Results.ColorOrder)
    hs.ax.ColorOrder = parser.Results.ColorOrder;
    hs.ax.NextPlot = 'replacechildren';
end

hs.scroll=findobj(hs.fig, 'Tag', 'Scroll');
if isempty(hs.scroll)
    hs.scroll = uicontrol(...
        'Tag', 'Scroll',...
        'Parent',hs.panel,...
        'Style','slider',...
        'Min',0,...
        'Value',scrollval,...
        'BackgroundColor', [.88 .66 .6],...
        'Max',1,...
        'SliderStep',[1e-4,.07],...
        'TooltipString','Click the slider through or mouse wheel to page forward one screen width.',...
        'Interruptible','on',...
        'Callback',{@redraw,true});
    hListener = addlistener(hs.scroll,'ContinuousValueChange',@redraw);
    setappdata(hs.scroll,'sliderListener',hListener);
end

hs.zoom=findobj(hs.fig, 'Tag', 'Zoom');
if isempty(hs.zoom)
    hs.zoom = uicontrol(...
        'Tag', 'Zoom',...
        'Parent',hs.panel,...
        'Style','slider',...
        'Min',0,...
        'Value',zoomval,...
        'Max',1,...
        'SliderStep',[1e-4,.07],...
        'TooltipString','Zoom',...
        'BackgroundColor', [.6 .88 .65],...
        'Interruptible','on',...
        'Callback',{@redraw,true});
    hListener = addlistener(hs.zoom,'ContinuousValueChange',@zoom_callback);
    setappdata(hs.zoom,'sliderListener',hListener);
    
end

    function zoom_callback(varargin)
        redraw(varargin{:});
        mmPerSec_slider = (axWidth_cm*10)/(numPoints*period);
    end

hs.scale=findobj(hs.fig, 'Tag', 'Scale');
if isempty(hs.scale)
    hs.scale = uicontrol(...
        'Tag', 'Scale',...
        'Parent',hs.panel,...
        'Style','slider',...
        'Min',0,...
        'Value',scaleval,...
        'Max',1000,...
        'SliderStep',[1e-4,.07],...
        'TooltipString','Scale',...
        'Interruptible','on',...
        'BackgroundColor', [.6 .65 .88],...
        'Callback',{@redraw,true});
    hListener = addlistener(hs.scale,'ContinuousValueChange',@scale_callback);
    setappdata(hs.scale,'sliderListener',hListener);
end
    function scale_callback(varargin)
        redraw(varargin{:});
        %% propScale_slider = (axWidth_cm*10)/(numPoints*period);
    end

d = -log(N/7);

hs.list = uicontrol(...
    'Parent',hs.panel,...
    'Style','listbox',...
    'Max',2,...
    'FontSize',fontSize,...
    'Value',[]);
if strcmpi(parser.Results.ShowInformationList,'none')
    hs.list.Visible = 'off';
end


%% Create chart line handle

click_info.x = [];
click_info.y = [];

if ~strcmp(get(gcf, 'Tag'),'SingleChannelAlakazamWindow')
    hs.line = Tools.jplot(hs.ax,1,1:size(SIG.Y0,2),lineSpec, 'ButtonDownFcn',{@lineSelect, SIG.EEG}); % Safer: Don't allow unmatched name-value pairs. Plot can still be modified by handles.
    for iline = 1:length(hs.line)
        set(hs.line(iline), 'ButtonDownFcn',{@lineSelect, SIG.EEG});
        ud.Number = iline;
        try
            ud.Label = SIG.AutoStackSignals(iline);
        catch 
            ud.Label = '';
        end
        set(hs.line(iline), 'UserData',ud);
    end
else
    hs.line = Tools.jplot(hs.ax,1,1:size(SIG.Y0,2),lineSpec); % Safer: Don't allow unmatched name-value pairs. Plot can still be modified by handles.
end

% Remove 10^x axes factor
hs.ax2.XAxis.Exponent = 0;
hs.ax2.XAxis.ExponentMode = 'manual';
hs.ax2.YAxis.Exponent = 0;
hs.ax2.YAxis.ExponentMode = 'manual';
hs.ax.XAxis.Exponent = 0;
hs.ax.XAxis.ExponentMode = 'manual';
hs.ax.YAxis.Exponent = 0;
hs.ax.YAxis.ExponentMode = 'manual';

%set(hs.line,'PickableParts','none')
if strcmpi(parser.Results.ShowAxisTicks,'on')
    hs.ax.XLabel.String = defaultXLabel;
    hs.ax.TickLength = [0.001,0.001];
    hs.ax2.TickLength = [0.001,0.001];
    hs.ax2.XLabel.String = parser.Results.SecondXAxisLabel;
    hs.ax.XMinorGrid = 'on';
    if isempty(parser.Results.AutoStackSignals)
        hs.ax.YLabel.String = 'Voltage in mV';
    else
        hs.ax.YLabel.String = 'Channel';
    end
else
    set(hs.ax ,'XTick',[], 'YTick',[])
    set(hs.ax2,'XTick',[], 'YTick',[])
end

if ~isempty(SIG.AutoStackSignals) && strcmp(parser.Results.YLimMode,'fixed')
    % Stack signals horizontally.
    [sigPosVec,sigAddVec] = auto_stack_nooverlap(SIG.Y0);
    hs.ax.YTick = flip(sigPosVec);
    hs.ax.YTickLabel = flip(SIG.AutoStackSignals(:));
    hs.ax.TickLabelInterpreter = 'none';
else
    sigPosVec = zeros(1,size(SIG.Y0,2));
    sigAddVec = zeros(1,size(SIG.Y0,2));
end

Y0pos = bsxfun(@plus,SIG.Y0,sigAddVec);
range = [min(Y0pos(:)),max(Y0pos(:))];
dlt = diff(range)/50;
range(1) = range(1)-dlt;
range(2) = range(2)+dlt;
if strcmp(parser.Results.YLimMode,'fixed') && nnz(isnan(range))==0 && range(2)>range(1)
    hs.ax.YLimMode = 'manual';
    hs.ax2.YLimMode = 'manual';
    hs.ax.YLim = range;
    hs.ax2.YLim = range;
end

% Make figure visible after adding components
%btnDown()
redraw(true);
try getframe(hs.fig); catch, end % update system queue
resizegui

if ~isempty(mmPerSec)
    numPoints = axWidth_cm*10/(mmPerSec*period);
else
    numPoints = secPerScreenWidth/period;
end
zoomValue = log(numPoints/N)/d;
zoomValue = max(zoomValue,0);
zoomValue = min(zoomValue,1);
set(hs.zoom,'Value',zoomValue)
zoomValue = hs.zoom.Value;

% if events:

if isfield(SIG.Event, 'Latencies')
    lat = SIG.Event.Latencies(1);
    fullheight = get(hs.ax, 'YLim');
end
if exist('hs', 'var')
    if (isfield(hs, 'events'))
        clear hs.events;
    end
end

if isfield(SIG.Event, 'Latencies')
    hs.events = struct;
    hs.events.lineObj(1) = line([lat lat],[fullheight(1) fullheight(1)/1.01],  'LineWidth' , 2,  'LineStyle', '-','Color','r' );
    hs.events.labelObj(1) = text(lat, fullheight(1)/1.02,SIG.Event.Types(1), 'FontSize', 8);
    
    for event = 2:length(SIG.Event.Codes)
        lat = SIG.Event.Latencies(event);
        hs.events.lineObj(end+1) = line([lat lat],[fullheight(1) fullheight(1)/1.01],  'LineWidth' , 2, 'LineStyle', '-','Color','r' );
        hs.events.labelObj(end+1) = text(lat,fullheight(1)/1.02, SIG.Event.Types(event), 'FontSize', 8, 'Color', 'b');
    end
    % endif events
end
resizegui
redraw(true)
hs.panel.Visible = 'on';

    function lineSelect(src, ~, EEG)
        % Switch to another Tab:
        % Plot only the selected channel: Use a new call to plotEEG2 (with the new parent).
        switch get(gcf, 'SelectionType')
            case 'open'
                if ~strcmp(get(gcf, 'Tag'),'SingleChannelAlakazamWindow')
                    %SingleChannelPlotFigure = findobj('Tag', 'SingleChannelAlakazamWindow');
                    %MultiChannelPlotFigure = findobj('Tag', 'AlakazamWindow');
                    %if (isempty(SingleChannelPlotFigure))
                    %    SingleChannelPlotFigure = figure('Tag',  'SingleChannelAlakazamWindow');
                    %end
                    SingleChannelPlotFigure = figure('Tag',  'SingleChannelAlakazamWindow');
                    try
                        data = pop_select(EEG,'channel', src.UserData.Number);
                    catch
                        data = EEG;
                    end
                    
                    mczoom      = get(hs.zoom , 'Value');
                    mcscale     = get(hs.scale , 'Value');
                    mcscroll    = get(hs.scroll, 'Value');
                    
                    figure(SingleChannelPlotFigure);
                    clf(SingleChannelPlotFigure);
                    
                    % could do with a remember of the positions...
                    % condider inheritance of the slider values....
                    Tools.plotEEG2(data.times/1000, data, 'YLimMode', 'fixed','zoomval',mczoom,'scaleval',mcscale,'scrollval',mcscroll, 'ShowInformationList','none','ShowAxisTicks','on', 'Parent', SingleChannelPlotFigure);
                    %CurrentPlot = plotEEG2(data.times/1000, data, 'ShowInformationList','none','ShowAxisTicks','on','YLimMode', 'dynamic', 'AutoStackSignals', {data.chanlocs.labels}, 'Parent', SingleChannelPlotFigure);
                    
                    if (TabControl ~= 0)
                        TabControl.SelectedIndex = 1;
                    end
                end
        end
        % disp(src.UserData);
    end

    function redraw(varargin)
        if ~ishandle(hs.line(1)) && length(varargin)>1
            % figure overplotted by normal plot()
            return
        end
        
        scaleValue = get(hs.scale,'Value');
        scrollValue = get(hs.scroll,'Value');
        %fprintf('scrollValue: %f\n',scrollValue)
        zoomValue   = get(hs.zoom,'Value');
        
        % zoomValue==0: numPoints=N
        % zoomValue==1: numPoints=7
        
        % N * exp(d*x)
        numPoints = N*exp(d*zoomValue);
        numPoints = round(numPoints);
        numPoints = max(numPoints,2);
        
        % scrollValue==0: startIndex=1;
        % scrollValue==1: startIndex=N-numPoints+1;
        startIndex = (N-numPoints)*scrollValue+1; % m*x+b
        endIndex = startIndex+numPoints;
        
        if ~isscalar(SIG.X0)
            startTime = timeBoundary(1)+period*(startIndex-1);
            [~,startIndex] = min(abs(startTime-SIG.X0));
            endTime = timeBoundary(1)+period*(endIndex-1);
            [~,endIndex] = min(abs(endTime-SIG.X0));
        end
        
        startIndex = round(startIndex);
        endIndex = round(endIndex);
        startIndex = max(startIndex,1);
        endIndex = min(endIndex,N);
        
        % Maximum factor_max values per pixel,
        % so very long signals don't hang Matlab
        factor = round(numPoints/max(1,axWidth_px));
        factor_max = 1000; % increase this if you want to find the "needle in the haystack" (single outlier sample)
        if factor>factor_max
            spc = floor(factor/factor_max);
        else
            spc = 1;
        end
        ind = startIndex:spc:endIndex;
        %fprintf('spc: %f\n',spc)
        
        if isscalar(SIG.X0)
            XData=period*(ind-1); 
        else
            XData = SIG.X0(ind); 
        end
        
        YData = SIG.Y0(ind,:);
        
        if isscalar(SIG.X0)
            startTime = XData(1);
            endTime = XData(end);
        end
        
        % Don't show much more samples than pixels.
        % Make sure that minimum and maximum data is shown anyway
        % (except if factor is > factor_max, for responsiveness)
        maxSamplesPerPixel = 2;
        if size(YData,1)/(axWidth_px*maxSamplesPerPixel) > 2
            factor = ceil(size(YData,1)/(max(1,axWidth_px)*maxSamplesPerPixel));
            remove = mod(size(YData,1),factor);
            XData = XData(1:(end-remove));
            YData = YData(1:(end-remove),:);
            XData = reshape(XData,factor,[]);
            XData = [min(XData,[],1);max(XData,[],1)];
            XData = XData(:)';
            YData = permute(YData,[3,1,2]);
            YData = reshape(YData,factor,[],size(YData,3));
            YData = [min(YData,[],1,'includenan');max(YData,[],1,'includenan')]; % preserves 'NaN' separations
            YData = [min(YData,[],1');max(YData,[],1)];
            YData = reshape(YData,[],size(YData,3));
        end
        
        % On the other hand, if there are much less samples than pixels,
        % show additional dots
        factor = size(YData,1)/max(1,axWidth_px);
        if ~strcmp(parser.Results.AutoMarkers,'none')
            if factor<0.2
                set(hs.line, 'Marker',parser.Results.AutoMarkers);
            else
                set(hs.line, 'Marker','none');
            end
        end
        
        if ~isempty(SIG.AutoStackSignals) && ~strcmp(parser.Results.YLimMode,'fixed')
            % Stack signals horizontally dynamically
            [sigPosVec,sigAddVec] = auto_stack(YData);
            hs.ax.YTick = flip(sigPosVec);
            hs.ax.YTickLabel = flip(SIG.AutoStackSignals(:));
            hs.ax.TickLabelInterpreter = 'none';
        end
        
        %MMS:
        if size(YData,2) >1
            sigMulVec = scaleValue*(zeros(1,size(YData,2))+1);
            YData = bsxfun(@times,YData,sigMulVec);
        else
        end
        %/MMS
        YData = bsxfun(@plus,YData,sigAddVec);
        
        
        % hs.ax2 limits
        if ~strcmp(parser.Results.SecondXAxisFunction,'none')
            ax2Limits = [feval(parser.Results.SecondXAxisFunction,startTime), feval(parser.Results.SecondXAxisFunction,endTime)];
            if ax2Limits(1)<ax2Limits(2)
                set(hs.ax2,'XDir','normal')
            else
                ax2Limits = flip(ax2Limits);
                set(hs.ax2,'XDir','reverse')
            end
            set(hs.ax2,'XLim',ax2Limits)
        end
        
        set(hs.line,'XData',XData);
        for iLine = 1:size(YData,2)
            set(hs.line(iLine),'YData',YData(:,iLine));
        end
        set(hs.ax,'XLim',[startTime,endTime])
        minY = min(YData(:));
        maxY = max(YData(:));
        delta = (maxY-minY)/50;
        minY = minY-delta;
        maxY = maxY+delta;
        if nnz(sigPosVec)>1
            minY = min([minY;sigPosVec(:)]);
            maxY = max([maxY;sigPosVec(:)]);
        end
        
        if strcmp(parser.Results.YLimMode,'dynamic') && nnz(isnan([minY,maxY]))==0 && maxY>minY
            set(hs.ax2,'YLim',[minY,maxY])
            set(hs.ax,'YLim',[minY,maxY])
        end
        if (size(YData,2) == 1) && (scaleValue >0)
            meanscale = (maxY+minY)/2;
            set(hs.ax,'YLim',([minY-meanscale,maxY-meanscale]/scaleValue)+meanscale);
        end
        % Big scrollbar if there is nothing to scroll
        if N<=numPoints
            majorStep = Inf;
            minorStep = .1;
        else % N > numPoints
            majorStep = max(1e-6,numPoints/(N-numPoints));
            % 100 steps per screen width
            minorStep = max(1e-6,(endTime-startTime)/(100*duration));
        end
        set(hs.scroll,'SliderStep',[minorStep,majorStep]);
        
        if ~strcmp(parser.Results.ScrollCallback,'none')
            arg.XLim = [startTime;endTime];
            arg.ContinuousValueChange = ~isempty(varargin) && ~(islogical(varargin{end}) && varargin{end});
            arg.hs = hs;
            feval(parser.Results.ScrollCallback,arg);
        end
    end



    function resizegui(varargin)
        
        try
            panelUnits = hs.panel.Units;
            
            % Centimeter layout
            set(hs.panel ,'Units',units);
            set(hs.ax    ,'Units',units);
            set(hs.ax2   ,'Units',units);
            set(hs.list  ,'Units',units);
            set(hs.scroll,'Units',units);
            set(hs.zoom  ,'Units',units);
            
            width = hs.panel.Position(3);
            height = hs.panel.Position(4);
            
            yPos = space;
            
            % Filter layout
            if isfield(SIG,'filter')
                filterHeight = layoutFilter(iSig,1,width-2*space);
                pos = [space,yPos,width-2*space,filterHeight];
                pos = [pos(1), pos(2), max(0,pos(3)), max(0,pos(4))];
                set(SIG.filter.panel, 'Units',units, 'Position',pos);
                yPos = pos(2)+pos(4)+4*space;
            end
            
            % Scale slider
            pos = [space,yPos,width-5*space,sliderHeight];
            pos = [pos(1), pos(2), max(0,pos(3)), max(0,pos(4))];
            set(hs.scale, 'Units',units, 'Position',pos)
            yPos = pos(2)+pos(4)+space;
            % Zoom slider
            pos = [space,yPos,width-5*space,sliderHeight];
            pos = [pos(1), pos(2), max(0,pos(3)), max(0,pos(4))];
            set(hs.zoom, 'Units',units, 'Position',pos)
            yPos = pos(2)+pos(4)+space;
            % Scroll slider
            pos = [space,yPos,width-5*space,sliderHeight];
            pos = [pos(1), pos(2), max(0,pos(3)), max(0,pos(4))];
            set(hs.scroll, 'Units',units, 'Position',pos)
            yPos = pos(2)+pos(4)+space;
            
            % List (I)
            if strcmpi(parser.Results.ShowInformationList,'none')
                listWidth = 0;
            else
                listWidth = 3;
                listWidth = min(listWidth,width/5);
            end
            
            % Axis
            if strcmpi(parser.Results.ShowAxisTicks,'on')
                insets = get(hs.ax,'TightInset');
                if isequal(hs.ax2.Visible,'on')
                    insets = insets + get(hs.ax2,'TightInset');
                end
            else
                insets = [0,0,0,0];
            end
            pos = [space,yPos,max(1,width-3*space-listWidth),max(1,height-yPos)];
            pos = [pos(1)+insets(1), pos(2)+insets(2), pos(3)-insets(1)-insets(3), pos(4)-insets(2)-insets(4)];
            pos = [pos(1), pos(2), max(0,pos(3)), max(0,pos(4))];
            set(hs.ax, 'Units',units, 'Position',pos)
            set(hs.ax2, 'Units',units, 'Position',pos)
            set(hs.panel,'Units',panelUnits);
            
            % List (II)
            if ~strcmpi(parser.Results.ShowInformationList,'none')
                axPos = hs.ax.Position;
                pos = [width-space-listWidth,axPos(2),listWidth,axPos(4)];
                set(hs.list, 'Units',units, 'Position',pos)
            end
            
            % Update axWidth_cm and axWidth_px
            set(hs.ax,'Units','centimeters');
            axWidth_cm=get(hs.ax,'Position'); axWidth_cm=axWidth_cm(3); axWidth_cm=max(axWidth_cm,0);
            set(hs.ax,'Units','pixels');
            axWidth_px=get(hs.ax,'Position'); axWidth_px=round(axWidth_px(3)); axWidth_px=max(axWidth_px,0);
            
            % Change zooming such that mmPerSec stays the same
            if ~isempty(varargin) && ~isempty(mmPerSec) % do this only for calls by GUI, not during the initialization call
                numPoints = axWidth_cm*10/(mmPerSec_slider*period);
                zoomValue = log(numPoints/N)/d;
                zoomValue = max(zoomValue,0);
                zoomValue = min(zoomValue,1);
                set(hs.zoom,'Value',zoomValue)
                redraw(true)
            end
        catch 
        end
    end




    function btnDown(varargin)
        % x and y location where button was pressed is stored
        % ShowInformationList function is called with these locations
        % and the returned strings  are displayed.
        % Numbers are converted to strings.
        x = hs.ax.CurrentPoint(1,1);
        y = hs.ax.CurrentPoint(1,2);
        click_info.x = [x;click_info.x];
        click_info.y = [y;click_info.y];
        
        %std_InformationList(hs,click_info)
        
        if strcmpi(parser.Results.ShowInformationList,'none')
            str = {};
        else
            str = feval(parser.Results.ShowInformationList, hs,click_info);
        end
        assert(iscell(str),'ShowInformationList function must return a cell array.')
        assert(isempty(str) || isvector(str), 'ShowInformationList function must return a cell vector.')
        
        % Convert numbers to strings
        
        for k = 1:length(str)
            if ~ischar(str{k})
                str{k} = num2str(str{k}); %#ok<AGROW>
            end
        end
        
        % Update uicontrol
        hs.list.String = str;
    end

if ~strcmpi(parser.Results.ShowInformationList,'none')
    hs.ax.ButtonDownFcn = @btnDown;
end

    function delete_plotEEG2(varargin)
        %fprintf('delete_plotECG\n')
        SIG = [];
        click_info = [];
        if isvalid(hs.fig)
            hs.fig.WindowScrollWheelFcn = '';
        end
    end

hs.ax.DeleteFcn    = @delete_plotEEG2;
hs.panel.DeleteFcn = @delete_plotEEG2;
hs.zoom.DeleteFcn  = @delete_plotEEG2;




%% Return output arguments

if nargout>=1
    varargout{1} = hs.line;
end
if nargout>=2
    varargout{2} = hs;
end


end











%% Helper Functions

% function y = editToSlider(edit,slider)
% y = str2double(get(edit,'String'));
% if y<=0
%     % negative value provided: use minimum possible value
%     y = slider.Min;
%     edit.String = num2str(y,4);
% end
% % Logarithmic Conversion
% a = slider.Min;
% b = slider.Max;
% r = log(a/b)/(a-b);
% p = a*exp(-log(a/b)*a/(a-b));
% if isnan(y)
%     % no valid number string typed: restore old value
%     y = p*exp(r*slider.Value);
%     edit.String = num2str(y,4);
% else
%     % convert to logarithmic scale
%     x = log(y/p)/r;
%     if x<slider.Min
%         slider.Value = slider.Min;
%     elseif x>slider.Max
%         slider.Value = slider.Max;
%     else
%         slider.Value = x;
%     end
% end
% drawnow
% end
% 
% 
% function y = sliderToEdit(edit,slider)
% x = slider.Value;
% % convert to exponential scale
% % y = p*exp(r*x), x:[a,b], y:[a,b]
% a = slider.Min;
% b = slider.Max;
% r = log(a/b)/(a-b);
% p = a*exp(-log(a/b)*a/(a-b));
% y = p*exp(r*x);
% edit.String = num2str(y,4);
% %edit.String = sprintf('%0.3g',y);
% end


function ls = isLineSpec(str)
ls = ischar(str) && length(str)<=4;
allowed = '-:.+o*xsd^v><phrgbcmykw';
for pos = 1:length(str)
    ls = ls && any(str(pos)==allowed);
end
end


% function str = func2str2(func)
% if ischar(func)
%     str = func;
% else
%     str = func2str(func);
% end
% end


% function str = function_file(func)
% if ischar(func)
%     funH = str2func(func);
%     funS = func;
% else
%     funH = func;
%     funS = func2str(func);
% end
% S = functions(funH);
% str = S.file;
% if isempty(str)
%     str = funS;
% else
%     str = sprintf('%s()   %s',funS,str);
% end
% end
% 

function [sigPosVec,sigAddVec] = auto_stack(YData)
% Stacks Signals Horizontally with little overlap
% Used after each scroll/zoom action for 'AutoStackSignals'
% with 'YLimMode' set to 'dynamic'.
% You might want to adjust this for your specific needs.

%YData = bsxfun(@minus,YData,YData(1,:));
signalMed = median(YData,1,'omitnan');
YData = bsxfun(@minus,YData,signalMed);
overlap = YData;
overlap = diff(overlap,1,2); % positive values are overlap
overlap(isnan(overlap)) = 0;
overlapS = sort(overlap,1,'descend');
index = max(1,round(size(overlapS,1)*.007));
signalSpacing = overlapS(index,:)*1.1;
stdd = std(YData,1,1);
stdd = min(stdd(1:end-1),stdd(2:end));
signalSpacing = max(signalSpacing, median(signalSpacing,'omitnan')*.5 );
signalSpacing = max(signalSpacing, stdd*4);
% Increas very small spacings
signalSpacing = max(signalSpacing, max(signalSpacing)./1000.*ones(size(signalSpacing)));
signalSpacing = max(eps,signalSpacing);
sigPosVec = -cumsum([0 signalSpacing]);
sigAddVec = sigPosVec-signalMed;
end


function [sigPosVec,sigAddVec] = auto_stack_nooverlap(YData)
% Stacks Signals Horizontally with strictly no overlap.
% Used for 'AutoStackSignals' with 'YLimMode' set to 'fixed'.
% You might want to adjust this for your specific needs.

signalMed = median(YData,1,'omitnan');
YData = bsxfun(@minus,YData,signalMed);
overlap = YData;
overlap = min(overlap(:,1:end-1),[],1) - max(overlap(:,2:end),[],1);
overlap(isnan(overlap)) = 0;
signalSpacing = -overlap*1.01;
% Increas very small spacings
signalSpacing = max(signalSpacing, max(signalSpacing)./1000.*ones(size(signalSpacing)));
signalSpacing = max(eps,signalSpacing);
sigPosVec = -cumsum([0 signalSpacing]);
sigAddVec = sigPosVec-signalMed;
% MMS:
sigAddVec = -((0:length(sigAddVec)-1))*mean(signalSpacing);
sigPosVec = sigAddVec;
end





%% Built-in Functions for 'ShowInformationList'


% function str = eeg_InformationList(hs,click)
% % click.x: [n x 1] array, first value is last click
% % click.y: [n x 1] array, first value is last click
% 
% if size(click.x,1)<2
%     click.x = [click.x;0;0];
%     click.y = [click.y;0;0];
% end
% 
% deltaX = abs(click.x(1)-click.x(2));
% freq = 1/deltaX;
% 
% str = {
%     
% 'BPM'
% freq*60
% ''
% 
% 'RR'
% deltaX
% ''
% 
% };
% end


% function str = std_InformationList(hs,click)
% % click.x: [n x 1] array, first value is last click
% % click.y: [n x 1] array, first value is last click
% 
% if size(click.x,1)<2
%     click.x = [click.x;0;0];
%     click.y = [click.y;0;0];
% end
% 
% deltaX = abs(click.x(1)-click.x(2));
% freq = 1/deltaX;
% deltaY = abs(click.y(1)-click.y(2));
% %fprintf('dx=%f; freq=%f, dy=%f\n',deltaX,freq,deltaY)
% 
% str = {
%     '<HTML>( &#916x <tt>&#8629</tt> 1/&#916x )</HTML>'
%     deltaX
%     freq
%     ''
%     
%     '<HTML>( &#916y )</HTML>'
%     deltaY
%     ''
%     
%     '<HTML>( x<sub>1</sub> <tt>&#8629</tt> x<sub>2</sub> )</HTML>'
%     click.x(2)
%     click.x(1)
%     ''
%     
%     '<HTML>( y<sub>1</sub> <tt>&#8629</tt> y<sub>2</sub> )</HTML>'
%     click.y(2)
%     click.y(1)
%     ''
%     
%     };
% end
% 
% 
% 
% 
% function str = Multi_InformationList(hs,click)
% % click.x: [n x 1] array, first value is last click
% % click.y: [n x 1] array, first value is last click
% 
% if size(click.x,1)<2
%     click.x = [click.x;0;0];
%     click.y = [click.y;0;0];
% end
% 
% deltaX = abs(click.x(1)-click.x(2));
% freq = 1/deltaX;
% deltaY = abs(click.y(1)-click.y(2));
% %fprintf('dx=%f; freq=%f, dy=%f\n',deltaX,freq,deltaY)
% 
% str = {
%     '<HTML>( &#916x <tt>&#8629</tt> 1/&#916x )</HTML>'
%     deltaX
%     freq
%     ''
%     
%     '<HTML>( &#916y )</HTML>'
%     deltaY
%     ''
%     
%     '<HTML>( x<sub>1</sub> <tt>&#8629</tt> x<sub>2</sub> )</HTML>'
%     click.x(2)
%     click.x(1)
%     ''
%     
%     '<HTML>( y<sub>1</sub> <tt>&#8629</tt> y<sub>2</sub> )</HTML>'
%     click.y(2)
%     click.y(1)
%     ''
%     
%     };
% end
% 



