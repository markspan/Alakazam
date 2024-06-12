function [pfigure, ropts] = PoinCare(input,~) %#ok<*AGROW>
% PoinCare - Create a Poincare plot for the IBI series
%
% Syntax: [pfigure, ropts] = PoinCare(input, ~)
%
% Inputs:
%   input - Structure containing the IBI data and related event information
%       .IBIevent - Cell array of structures with IBI data
%       .filename - Name of the file containing the data
%       .event - Array of event structures
%           .type - Type of the event
%           .latency - Latency of the event
%           .duration - Duration of the event
%       .srate - Sampling rate of the data
%
% Outputs:
%   pfigure - Handle to the created Poincare plot figure
%   ropts - String indicating the type of plot created ('graph')
%
% Description:
%   This function creates an interactive Poincare plot of the inter-beat intervals (IBIs)
%   from the provided input data. It checks for the presence of IBI data and
%   generates the plot by comparing the IBI values at time t with those at
%   time t+1. The plot includes different partitions based on the event
%   types if specified. The function also calculates and displays various
%   heart rate variability (HRV) metrics.
%
% Example:
%   input = load('ibi_data.mat'); % Load IBI data
%   [pfigure, ropts] = PoinCare(input); % Create Poincare plot

% Set default return options
ropts = 'graph';
%% Check for the EEG dataset input:
if (nargin < 1)
    ME = MException('Alakazam:PoinCare','Problem in PoinCare: No Data Supplied');
    throw(ME);
end
if ~isfield(input, 'IBIevent')
    ME = MException('Alakazam:PoinCare','Problem in IBIExport: No IBIS availeable (yet)');
    throw(ME);
end

[~, name, ~]= fileparts(input.filename);
pfigure = uifigure('Name', name, 'Visible', false, 'Units', 'normalized');

ev = [];
if isfield(input, 'event') && isfield(input.event, 'type') && ~isempty({input.event.type})
    try
        ev = unique({input.event.type}, 'stable');
    catch
        ev = unique([input.event.type], 'stable');
    end
    evc = ev;
else
    evc = [];
end

%% define all events that are IBI
events = input.IBIevent{1};

%select the normals
normals = events.classID == 'N';

events.ibis = events.ibis(normals(1:end-1));
ibix = events.ibis(1:end-1);
ibiy = events.ibis(2:end);
ibit = events.RTopTime(1:end-2);

    function t = PoinCarePlot(fig,ibix, ibiy, ibit, evc, input)
        % Create table array
        RMSSD =[]; SDNN = [];
        mIBI = [];
        SD1=[];
        SD2=[];
        x={};
        y={};
        tRR={};
        N=[];
        nEVC = strings(0,0);
        if (~isempty(evc))
            for i = 1:length(evc) % for each event type:
                label = evc(i);
                event = [strcmp({input.event.type}, label)];
                idx = ibit<0;
                for e1 = 1:length(input.event(event)) %% when there are more events
                    elist = [input.event(event)];
                    ev = elist(e1);
                    idx = idx | (ibit > ev.latency/input.srate) & (ibit < (((ev.latency+ev.duration)/input.srate)));
                end
                if sum(idx > 0)
                    nEVC(end+1)=evc(i);
                    idx = idx(1:length(ibix));
                    x{end+1} = ibix(idx);
                    y{end+1} = ibiy(idx);
                    tRR{end+1} = ibit(idx);
                    SD1(end+1) = round((sqrt(2)/2.0) * std(ibix(idx)-ibiy(idx)),3);
                    SD2(end+1) = round( sqrt(2*std(ibix(idx))^2) - (.5*std(ibix(idx)-ibiy(idx))^2),3);
                    if isempty(Tools.HRV.RMSSD(ibix(idx)))
                        RMSSD(end+1) = nan;
                    else
                        RMSSD(end+1) = 1000 * Tools.HRV.RMSSD(ibix(idx));
                    end
                    SDNN(end+1) = 1000 * Tools.HRV.SDNN(ibix(idx));
                    mIBI(end+1) = 1000 * mean(ibix(idx));
                    N(end+1) = sum(idx);
                end
            end
        else
            x{end+1} = ibix(:);
            y{end+1} = ibiy(:);
            tRR{end+1} = ibit(:);
            SD1(end+1) = round((sqrt(2)/2.0) * std(ibix(:)-ibiy(:)),3);
            SD2(end+1) = round( sqrt(2*std(ibix(:))^2) - (.5*std(ibix(:)-ibiy(:))^2),3);
            if isempty(Tools.HRV.RMSSD(ibix(:)))
                RMSSD(end+1) = nan;
            else
                RMSSD(end+1) = 1000 * Tools.HRV.RMSSD(ibix(:));
            end
            SDNN(end+1) = 1000 * Tools.HRV.SDNN(ibix(:));
            mIBI(end+1) = 1000 * mean(ibix(:));
            N(end+1) = length(x);
            evc = "full epoch"; %#ok<NASGU>
        end

        pSD1SD2 = SD1./SD2;
        cRMSSD = 1000 * (RMSSD./mIBI);
        Plotted = mIBI > 0;

        t = table(Plotted',N', mIBI', SD1', SD2', pSD1SD2', RMSSD', cRMSSD', SDNN', ...
            'VariableNames',["Plot","N","mean(IBI)","SD1","SD2","SD1/SD2","RMSSD","cRMSSD", "SDNN"], ...
            'RowNames',nEVC);
        fn = input.filename;
        [~,name,~] = fileparts(fn);

        writetable(t, ['./Data/' name '.csv'],'WriteRowNames',true);

        gl = uigridlayout(fig, [3 2]);

        % Create UI figure
        % Create table UI component
        uit = uitable(gl);
        uit.Layout.Row = [1,2];
        uit.Layout.Column = 2;
        uit.Data = t;
        uit.ColumnSortable = false;
        uit.ColumnEditable = [true false false false false false false false false];
        uit.BackgroundColor = [.91 .91 .91;
            .98 .98 .98];
        uit.DisplayDataChangedFcn = @updatePlot;
        style= uistyle('HorizontalAlignment','right');
        addStyle(uit,style,'table','');
        % Create PoinCare chart
        ax = uiaxes(gl);
        ax.Layout.Row = [1,3];
        ax.Layout.Column = 1;

        %guiPanel = uipanel(gl, title = "Parameters: ");
        %guiPanel.Layout.Column = 2;
        %guiPanel.Layout.Row = 3;

        lPoincarePlot(t, x, y, tRR, input.IBIevent{1}.classID(1:end-2));

        % Update the bubble chart when table data changes
        function updatePlot(~,~)
            t = uit.DisplayData;
            lx = xlim(ax); ly = ylim(ax);
            lPoincarePlot(t,x,y,tRR,input.IBIevent{1}.classID(1:end-2));
            xlim(ax,lx); ylim(ax,ly);
        end
        function lPoincarePlot(t,xibis,yibis, tibis, labs)
            cla(ax);
            xlabel(ax, "IBI(t)");
            ylabel(ax, "IBI(t+1)");
            m = ceil(10*max(ibix))/10;
            xlim(ax, [0 m])
            ylim(ax, [0 m])
            grid(ax, 'on')
            h = []; %#ok<NASGU>
            for ii = 1:length(t.Plot)
                if (t.Plot(ii))
                    col = ax.ColorOrder(mod(ii-1,7)+1,:);
                    hold(ax, 'on')
                    h = scatter(ax,xibis{ii}, yibis{ii}, 'MarkerEdgeColor',col, 'DisplayName', char(t.Row(ii)) );

                    [Labels{1:length(tibis{ii})}] = deal(t.Row{ii});
                    h.DataTipTemplate.DataTipRows(1) = dataTipTextRow("Period:",Labels);
                    h.DataTipTemplate.DataTipRows(3) = dataTipTextRow("IBI(t):",'XData');
                    h.DataTipTemplate.DataTipRows(2) = dataTipTextRow("Label",labs);
                    h.DataTipTemplate.DataTipRows(4) = dataTipTextRow("IBI(t+1):",'YData');
                    h.DataTipTemplate.DataTipRows(5) = dataTipTextRow("Time(s):",double(tibis{ii}));

                    el = plot_ellipse(ax, 2*t.SD1(ii),2*t.SD2(ii),mean(xibis{ii}), mean(yibis{ii}), 45, col);
                    dt = datatip(el,0,0,'Visible','off'); %#ok<NASGU> % weird hack to enable datatips on patches
                    [Labels{1:length(el.XData)}] = deal(t.Row{ii});
                    el.DataTipTemplate.DataTipRows(1)  = dataTipTextRow("", Labels);
                    el.DataTipTemplate.DataTipRows(2)=[];
                end
            end
        end
    end

PoinCarePlot(pfigure, ibix, ibiy, ibit, evc, input);
pfigure.Visible = true;

end

function h=plot_ellipse(ax,a,b,cx,cy,angle,color)
% plot_ellipse - Plot an ellipse on the given axes
%
% Syntax: h = plot_ellipse(ax, a, b, cx, cy, angle, color)
%
% Inputs:
%   ax - Axes handle to plot the ellipse on
%   a - Width of the ellipse
%   b - Height of the ellipse
%   cx - Horizontal center of the ellipse
%   cy - Vertical center of the ellipse
%   angle - Orientation of the ellipse in degrees
%   color - Color of the ellipse
%
% Outputs:
%   h - Handle to the plotted ellipse
%
% Description:
%   This function plots an ellipse on the specified axes with the given
%   dimensions, position, orientation, and color.
    angle=angle/180*pi;
    
    r=0:0.1:2*pi+0.1;
    p=[(a*cos(r))' (b*sin(r))'];
    
    alpha=[cos(angle) -sin(angle)
        sin(angle) cos(angle)];
    
    p1=p*alpha;
    h = patch(ax, cx+p1(:,1),cy+p1(:,2),color,'EdgeColor',color);
    h.FaceAlpha = .05;
end


