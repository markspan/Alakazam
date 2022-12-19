function [ varargout ] = plotECG( varargin )
%    Created:         Daniel Frisch        (15.02.2015)
%    Last modified:   M.Span               (07.09.2021)

%% Parse Inputs
args = varargin;
SIG = struct;
defaultXLabel = 'Time in s';
mm_default = 50;
SIG.X0 = 1;
if length(args)>=2 && isnumeric(args{1}) && isstruct(args{2}) && isfield(args{2}, 'data')
    % plotECG(X,Y)
    SIG.X0 = double(args{1});
    SIG.Y0 = double(args{2}.data);
    SIG.EEG = args{2};
    args = args(3:end);
elseif length(args)>=1 && isnumeric(args{1})
    % plotECG(Y)
    defaultXLabel = '';
    SIG.Y0 = args{1};
    SIG.X0 = 1;
    args = args(2:end);
    mm_default = 0.001;
end

% Check X and Y and change to column-oriented data
if numel(SIG.X0)==1 % X = sample rate
    validateattributes(SIG.X0,{'double'},{'nonempty','real','finite','scalar','positive'     }, 'plotECG','scalar X',1)
else % X = timestamps
    validateattributes(SIG.X0,{'double'},{'nonempty','real','finite','vector','nondecreasing'}, 'plotECG','vector X',1)
end
validateattributes(SIG.Y0,{'double'},{'nonempty','real','2d'}, 'plotECG','Y')

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
parser.FunctionName = 'plotECG';

parser.addParameter('mmPerSec'           , mm_default  , @(x)validateattributes(x,{'double'},{'real','finite','positive','scalar'}))
parser.addParameter('secPerScreenWidth'  , 1           , @(x)validateattributes(x,{'double'},{'real','finite','positive','scalar'}))
parser.addParameter('ShowAxisTicks'      , 'on'        , @(x)any(validatestring(x,{'on','off'})))
parser.addParameter('AutoStackSignals'   , {}          , @(x)iscellstr(x) || isstring(x))
parser.addParameter('YLimMode'           , 'dynamic'   , @(x)any(validatestring(x,{'dynamic','fixed'})))
parser.addParameter('AutoMarkers'        , '.'         , @(x)any(validatestring(x,{'+','o','*','.','x','square','diamond','v','^','>','<','pentagram','hexagram','none'})))
parser.addParameter('ColorOrder'         , []          , @(x)validateattributes(x,{'double'},{'real','finite','nonnegative', '<=',1, 'size',[NaN,3]}))
parser.addParameter('ScrollCallback'     , 'none'      , @(x)validateattributes(x,{'char','function_handle'},{'vector','nonempty'}))
parser.addParameter('Parent'             , 0           , @(x)isscalar(x) && isgraphics(x) && x~=0)
parser.addParameter('Units'              , 'normalized', @(x)any(validatestring(x,{'pixels','normalized','inches','centimeters','points','characters'})))
parser.addParameter('Position'           , [0,0,1,1]   , @(x)validateattributes(x,{'double'},{'real','finite','nonnegative', 'size',[1 4]}))
parser.addParameter('ShowIBIS'           , 'auto'      , @(x)any(validatestring(x,{'auto','off'})))
parser.addParameter('MaxIBIS'            , 175         , @(x)validateattributes(x,{'double'},{'real','finite','positive','scalar'}))
parser.addParameter('ShowEvents'         , 'auto'      , @(x)any(validatestring(x,{'auto','off'})))
parser.addParameter('MaxEvents'          , 30          , @(x)validateattributes(x,{'double'},{'real','finite','positive','scalar'}))
parser.addParameter('MaxAreas'           , 20          , @(x)validateattributes(x,{'double'},{'real','finite','positive','scalar'}))

parser.parse(args{:})

SIG.AutoStackSignals = parser.Results.AutoStackSignals;
if ~isempty(SIG.AutoStackSignals)
    nStr = numel(SIG.AutoStackSignals);
    nSig = size(SIG.Y0,2);
    assert(nStr==nSig, 'You specified %u Strings in ''AutoStackSignals'', but the number of signals in Y is %u.',nStr,nSig);
end

if ~strcmp(parser.Results.ShowIBIS, 'off')
    if ( isfield(SIG, 'EEG') && isfield(SIG.EEG, 'IBIevent'))
        SIG.ShowIBIS = 'on';
        SIG.IBIEVENTS =  SIG.EEG.IBIevent;
    else
        SIG.ShowIBIS = 'off';
    end
end

if ~strcmp(parser.Results.ShowEvents, 'off')
    if ( isfield(SIG, 'EEG') && isfield(SIG.EEG, 'event') && ~isempty(SIG.EEG.event))
        evlati = [SIG.EEG.event.latency];
        evdur = ones(1,length(SIG.EEG.event));

        if isfield(SIG.EEG.event, 'duration')
            empties = cellfun(@isempty, {SIG.EEG.event.duration});
            nonempties = ~empties;

            evdur(nonempties) = [SIG.EEG.event.duration];
            evdur(empties) = 1;
        end

        evlati = evlati(evdur < 1); % only events with a duration of 1: events
        evtypes = {SIG.EEG.event.type};

        try
            SIG.EventLabel = evtypes(evdur < 1);
            SIG.EventTime = SIG.EEG.times(evlati);
        catch ME
            SIG.EventLabel = [];
            SIG.EventTime = [];
        end
        evlati = [SIG.EEG.event.latency];
        %evdur = [SIG.EEG.event.duration];

        evlati = evlati(evdur > 0); % only events with longer: "Labels" or "Areas".
        if isfield(SIG.EEG.event, 'type')
            evtypes = {SIG.EEG.event.type};
        end

        [evlab{1:length(SIG.EEG.event)}] = deal('-');
        if isfield(SIG.EEG.event, 'code')
            evlab   = {SIG.EEG.event.code};
        end

        SIG.AreaEventLabel = strcat(evlab(evdur > 0) + " - " + evtypes(evdur > 0));
        SIG.AreaEventTime  = SIG.EEG.times(max(1,floor(evlati)));
        SIG.AreaEventDur   = evdur(evdur > 0) / SIG.EEG.srate;

        SIG.ShowEvents = 'on';
    else
        SIG.ShowEvents = 'off';
        a=0;
    end
end

%% Add the GUI components
mmPerSec = [];
secPerScreenWidth = [];
if ismember('secPerScreenWidth',parser.UsingDefaults)
    mmPerSec = parser.Results.mmPerSec;
else
    secPerScreenWidth = parser.Results.secPerScreenWidth;
end
mmPerSec_slider = mmPerSec;
% N = size(SIG.Y0,1); % number of data points
N = round(duration / period)+1;
axWidth_cm = 100;
axWidth_px = 100;

% Layout constants
%fontSize = 11;
units = 'centimeters';
space = 0.05;
sliderHeight = .35;
%checkboxHeight = 1;
%editWidth = 2;

% Add components, save handles in a struct
hs = struct;
if parser.Results.Parent==0
    % Create new figure
    hs.parent = figure('Units','normalized', 'OuterPosition',[0.3,0.53,0.65,0.45], 'HandleVisibility','Callback');
else
    hs.parent = parser.Results.Parent;
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
hs.fig.WindowScrollWheelFcn = @figScroll;

hs.panel = uipanel(... % This uipanel can be put into another GUI
    'Parent',hs.parent,...
    'Units',parser.Results.Units,...
    'Position',parser.Results.Position,...
    'BorderWidth',0,...
    'SizeChangedFcn',@resizegui,...
    'Visible','off');

hs.ax = axes(...
    'Parent',hs.panel,...
    'TickLabelInterpreter','none',...
    'ActivePositionProperty','Position');
if ~isempty(parser.Results.ColorOrder)
    hs.ax.ColorOrder = parser.Results.ColorOrder;
    hs.ax.NextPlot = 'replacechildren';
end

hs.scroll = uicontrol(...
    'Parent',hs.panel,...
    'Style','slider',...
    'Min',0,...
    'Value',0,...
    'Max',1,...
    'SliderStep',[1e-4,.07],...
    'TooltipString','Scroll the signal',...
    'Interruptible','on',...
    'Callback',{@redraw,true});
hListener = addlistener(hs.scroll,'ContinuousValueChange',@redraw);
setappdata(hs.scroll,'sliderListener',hListener);

hs.zoom = uicontrol(...
    'Parent',hs.panel,...
    'Style','slider',...
    'Min',0,...
    'Value',.5,...
    'Max',1,...
    'SliderStep',[1e-4,.07],...
    'TooltipString','Zoom the signal',...
    'Interruptible','on',...
    'Callback',{@redraw,true});
hListener = addlistener(hs.zoom,'ContinuousValueChange',@redraw);
setappdata(hs.zoom,'sliderListener',hListener);

    function zoom_callback(varargin)
        redraw(varargin{:});
        mmPerSec_slider = (axWidth_cm*10)/(numPoints*period);
    end

d = -log(N/7);

hs.scale = uicontrol(...
    'Parent',hs.panel,...
    'Style','slider',...
    'Min',0.001,...
    'Value',1,...
    'Max',100,...
    'SliderStep',[1e-4,.07],...
    'TooltipString','Scale the signal.',...
    'Interruptible','on',...
    'Callback',{@redraw,true});
hListener = addlistener(hs.scale,'ContinuousValueChange',@redraw);
setappdata(hs.scale,'sliderListener',hListener);

%% Create chart line handle

click_info.x = [];
click_info.y = [];

%hs.line = plot(hs.ax,1,1:size(SIG.Y0,2),lineSpec,parser.Unmatched); % Unmatched name-value pairs as plot parameters
hs.line = plot(hs.ax,1,1:size(SIG.Y0,2),lineSpec); % Safer: Don't allow unmatched name-value pairs. Plot can still be modified by handles.

hs.ax.XAxis.Exponent = 0;
hs.ax.XAxis.ExponentMode = 'manual';
hs.ax.YAxis.Exponent = 0;
hs.ax.YAxis.ExponentMode = 'manual';

if strcmpi(parser.Results.ShowAxisTicks,'on')
    hs.ax.XLabel.String = defaultXLabel;
    hs.ax.TickLength = [0.001,0.001];
    hs.ax.XMinorGrid = 'on';
    if isempty(parser.Results.AutoStackSignals)
        if (isfield(varargin{2}, 'YLabel') && ischar(varargin{2}.YLabel))
            hs.ax.YLabel.String = varargin{2}.YLabel;
        else
            hs.ax.YLabel.String = 'Voltage in mV';
        end
    else
        hs.ax.YLabel.String = 'Channel';
    end
else
    set(hs.ax ,'XTick',[], 'YTick',[])
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
    hs.ax .YLimMode = 'manual';
    hs.ax. YLim = range;
end


% Make figure visible after adding components

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

resizegui
redraw(true)
hs.panel.Visible = 'on';


    function redraw(varargin)
        if ~ishandle(hs.line(1)) && length(varargin)>1
            % figure overplotted by normal plot()
            return
        end

        set(gcf,'Pointer','watch');

        scaleValue = get(hs.scale,'Value');
        scrollValue = get(hs.scroll,'Value');
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

        if isscalar(SIG.X0), XData=period*(ind-1); else, XData = SIG.X0(ind); end
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

        %MMS:
        if size(YData,2) >1 %#ok<IFBDUP>
            sigMulVec = scaleValue*(zeros(1,size(YData,2))+1);
            YData = bsxfun(@times,YData,sigMulVec);
        else
            sigMulVec = scaleValue*(zeros(1,size(YData,2))+1);
            YData = bsxfun(@times,YData,sigMulVec);
        end

        if ~isempty(SIG.AutoStackSignals) && ~strcmp(parser.Results.YLimMode,'fixed')
            % Stack signals horizontally dynamically
            [sigPosVec,sigAddVec] = auto_stack(YData);
            hs.ax.YTick = flip(sigPosVec);
            hs.ax.YTickLabel = flip(SIG.AutoStackSignals(:));
            hs.ax.TickLabelInterpreter = 'none';
        end
        YData = bsxfun(@plus,YData,sigAddVec);

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

        prevIBI = findobj(hs.ax, 'Tag', 'ibi');
        delete(prevIBI);
        prevevent = findobj(hs.ax, 'Tag', 'event');
        delete(prevevent);

        %% plot the ibis: each a color

        if ~strcmp(SIG.ShowIBIS, 'off')
            for i = 1:length(SIG.IBIEVENTS)
                SIG.RTop = SIG.IBIEVENTS{i}.RTopTime;
                SIG.ibi = SIG.IBIEVENTS{i}.ibis;
                SIG.IBICLASS = SIG.IBIEVENTS{i}.classID;
                showRTi = (SIG.RTop>startTime) & (SIG.RTop < endTime);
                showRTi = showRTi(1:length(SIG.ibi));
                plottedIBIS = SIG.RTop(showRTi);
                Labels = SIG.ibi(showRTi);
                prelab = SIG.IBICLASS(showRTi);
                %cols = lines(length(SIG.IBIEVENTS));
                cols = dictionary(["N" "L" "S" "T" "1" "2" "i"], ["blue" "red" "red" "yellow" "green" "green" "magenta"]);
                if (length(plottedIBIS) < parser.Results.MaxIBIS)
                    if i == 1
                        for rt = 1:length(plottedIBIS)
                            cursor(hs.ax,  ...
                                plottedIBIS(rt), ...
                                [],@uiextras.delCursor,...
                                'Color', cols(prelab(rt)),...
                                'LineStyle', '-.', ...
                                'Label',  strcat(prelab(rt), " - " , num2str(Labels(rt))), ...
                                'LabelVerticalAlignment', 'top', ...
                                'LabelHorizontalAlignment', 'right',...
                                'Tag', 'ibi',...
                                'ID', [i rt]);
                            % ,...
                        end
                    else
                        for rt = 1:length(plottedIBIS)
                            cursor(hs.ax,  ...
                                plottedIBIS(rt), ...
                                [],@uiextras.delCursor,...
                                'Color', cols(i,:),...
                                'LineStyle', '-.', ...
                                'Label',  Labels(rt), ...
                                'LabelVerticalAlignment', 'bottom', ...
                                'LabelHorizontalAlignment', 'right',...
                                'Tag', 'ibi',...
                                'UserData', [i rt]);
                            % ,...

                        end
                    end
                end
            end
        end

        if ~strcmp(SIG.ShowEvents, 'off')
            %% Plot the Events: no duration: blue cursor
            showEvents = (SIG.EventTime>startTime) & (SIG.EventTime < endTime);
            plottedEv = SIG.EventTime(showEvents);
            Labels = SIG.EventLabel(showEvents);
            if (length(plottedEv) < parser.Results.MaxEvents)
                for rt = 1:length(plottedEv)
                    cursor(hs.ax, ...
                        plottedEv(rt), ...
                        [],[],...
                        'Color', [.1,.3,.8,.5],...
                        'LineStyle', ':', ...
                        'Label',  Labels(rt), ...
                        'LabelVerticalAlignment', 'bottom', ...
                        'LabelHorizontalAlignment', 'center',...
                        'LabelOrientation', 'horizontal', ...
                        'FontSize', 8, ...
                        'Tag', 'event',...
                        'UserData', rt);
                    % ,...
                end
            end
            %% now plot the areas: greenish label

            %% This needs refining: this will show the area when the **start** is in the view
            % should be if any part of the area is within the view. Think
            % Mark! Would be fun if the label would say in the view.....

            showEvents = (SIG.AreaEventTime>startTime) & (SIG.AreaEventTime < endTime);

            plottedEv = SIG.AreaEventTime(showEvents);
            plottedDur = SIG.AreaEventDur(showEvents);
            Labels = SIG.AreaEventLabel(showEvents);

            if (length(plottedEv) < parser.Results.MaxAreas)
                for rt = 1:length(plottedEv)
                    label(hs.ax, ...
                        plottedEv(rt), ...
                        plottedDur(rt), ...
                        Labels(rt), ...
                        [.1,.8,.7], ...
                        [],[],...
                        'EdgeColor', [.1 .8 .5], ...
                        'FaceAlpha', .15, ...
                        'EdgeAlpha', .25, ...
                        'Tag', 'event',...
                        'UserData', rt);
                    %                         'LineStyle', ':', ...
                    %                         'Label',  , ...
                    %                         'LabelVerticalAlignment', 'bottom', ...
                    %                         'LabelHorizontalAlignment', 'center',...
                    %                         'LabelOrientation', 'horizontal', ...
                    %                         'FontSize', 8, ...
                end
            end
        end

        if strcmp(parser.Results.YLimMode,'dynamic') && nnz(isnan([minY,maxY]))==0 && maxY>minY
            set(hs.ax,'YLim',[minY,maxY])
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
        set(gcf,'Pointer','arrow');

    end

    function resizegui(varargin)

        panelUnits = hs.panel.Units;

        % Centimeter layout
        set(hs.panel ,'Units',units);
        set(hs.ax    ,'Units',units);
        set(hs.scale ,'Units',units);
        set(hs.scroll,'Units',units);
        set(hs.zoom  ,'Units',units);

        width = hs.panel.Position(3);
        height = hs.panel.Position(4);

        yPos = space;

        % Zoom slider
        pos = [space,yPos,width-2*space,sliderHeight];
        pos = [pos(1), pos(2), max(0,pos(3)), max(0,pos(4))];
        set(hs.zoom, 'Units',units, 'Position',pos)
        yPos = pos(2)+pos(4)+space;

        % Scroll slider
        pos = [space,yPos,width-2*space,sliderHeight];
        pos = [pos(1), pos(2), max(0,pos(3)), max(0,pos(4))];
        set(hs.scroll, 'Units',units, 'Position',pos)
        yPos = pos(2)+pos(4)+space;

        % Scale slider
        pos = [space,yPos,width-2*space,sliderHeight];
        pos = [pos(1), pos(2), max(0,pos(3)), max(0,pos(4))];
        set(hs.scale, 'Units',units, 'Position',pos)
        yPos = pos(2)+pos(4)+space;

        % Axis
        if strcmpi(parser.Results.ShowAxisTicks,'on')
            insets = get(hs.ax,'TightInset');
        else
            insets = [0,0,0,0];
        end

        pos = [space,yPos,max(1,width-3*space),max(1,height-1.6*yPos)];
        pos = [pos(1)+insets(1), pos(2)+insets(2), pos(3)-insets(1)-insets(3), pos(4)-insets(2)-insets(4)];
        pos = [pos(1), pos(2), max(0,pos(3)), max(0,pos(4))];

        set(hs.ax, 'Units',units, 'Position',pos)
        set(hs.panel,'Units',panelUnits);

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
    end


    function figScroll(~,callbackdata)
        scrollCount = callbackdata.VerticalScrollCount;
        val = hs.scroll.Value + scrollCount*hs.scroll.SliderStep(2);
        val = max(hs.scroll.Min,val);
        val = min(hs.scroll.Max,val);
        hs.scroll.Value = val;
        redraw(true);
    end


    function delete_plotECG(varargin)
        %fprintf('delete_plotECG\n')
        SIG = [];
        click_info = [];
        if isvalid(hs.fig)
            hs.fig.WindowScrollWheelFcn = '';
        end
    end

hs.ax.DeleteFcn    = @delete_plotECG;
hs.panel.DeleteFcn = @delete_plotECG;
hs.zoom.DeleteFcn  = @delete_plotECG;

%% Return output arguments

if nargout>=1
    varargout{1} = hs.line;
end
if nargout>=2
    varargout{2} = hs;
end


end

%% Helper Functions

function y = editToSlider(edit,slider)
y = str2double(get(edit,'String'));
if y<=0
    % negative value provided: use minimum possible value
    y = slider.Min;
    edit.String = num2str(y,4);
end
% Logarithmic Conversion
a = slider.Min;
b = slider.Max;
r = log(a/b)/(a-b);
p = a*exp(-log(a/b)*a/(a-b));
if isnan(y)
    % no valid number string typed: restore old value
    y = p*exp(r*slider.Value);
    edit.String = num2str(y,4);
else
    % convert to logarithmic scale
    x = log(y/p)/r;
    if x<slider.Min
        slider.Value = slider.Min;
    elseif x>slider.Max
        slider.Value = slider.Max;
    else
        slider.Value = x;
    end
end
drawnow
end


function y = sliderToEdit(edit,slider)
x = slider.Value;
% convert to exponential scale
% y = p*exp(r*x), x:[a,b], y:[a,b]
a = slider.Min;
b = slider.Max;
r = log(a/b)/(a-b);
p = a*exp(-log(a/b)*a/(a-b));
y = p*exp(r*x);
edit.String = num2str(y,4);
%edit.String = sprintf('%0.3g',y);
end


function ls = isLineSpec(str)
ls = ischar(str) && length(str)<=4;
allowed = '-:.+o*xsd^v><phrgbcmykw';
for pos = 1:length(str)
    ls = ls && any(str(pos)==allowed);
end
end


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
overlap(isinf(overlap)) = 100000;

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







