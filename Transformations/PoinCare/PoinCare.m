function [pfigure, ropts] = PoinCare(input,opts)
%% Create a poincare plot for the IBI series
% The ibis are plotted agains a time-delayed version of the same values. If
% the 'bylabel' option is used, the plot has different partitions for each
% value the label takes on.

%#ok<*AGROW>
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
    ev = unique([input.event.type], 'stable');
    evc = ev;
end

ibix = input.IBIevent{1}.ibis(1:end-1);
ibiy = input.IBIevent{1}.ibis(2:end);
ibit = input.IBIevent{1}.RTopTime(1:end-2);

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
    for i = 1:length(evc)
        label = evc(i);
        event = [strcmp([input.event.type], label)];
        idx = ibit<0;
        for e = 1:length(input.event(event)) %% when there are more events
            elist = [input.event(event)];
            ev = elist(e);
            idx = idx | (ibit > ev.latency/input.srate) & (ibit < (((ev.latency+ev.duration)/input.srate)));
        end
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
    pSD1SD2 = SD1./SD2;
    cRMSSD = 1000 * (RMSSD./mIBI);
    Plotted = mIBI > 0;

    t = table(Plotted',N', mIBI', SD1', SD2', pSD1SD2', RMSSD', cRMSSD', SDNN', ...
        'VariableNames',["Plot","N","mean(IBI)","SD1","SD2","SD1/SD2","RMSSD","cRMSSD", "SDNN"], ... 
        'RowNames',evc);

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

    lPoincarePlot(t, x, y, tRR)

        % Update the bubble chart when table data changes
        function updatePlot(~,~)
            t = uit.DisplayData;
            lx = xlim(ax); ly = ylim(ax);
            lPoincarePlot(t,x,y,tRR)
            xlim(ax,lx); ylim(ax,ly);
        end
        function lPoincarePlot(t,xibis,yibis, tibis)
            cla(ax);
            xlabel(ax, "IBI(t)");
            ylabel(ax, "IBI(t+1)");
            m = ceil(10*max(ibix))/10;
            xlim(ax, [0 m])
            ylim(ax, [0 m])
            grid(ax, 'on')
            h = [];
            for i = 1:length(t.Plot)
                if (t.Plot(i))
                  col = ax.ColorOrder(mod(i-1,7)+1,:);
                  hold(ax, 'on')
                  h = scatter(ax,xibis{i}, yibis{i}, 'MarkerEdgeColor',col, 'DisplayName', char(t.Row(i)) );

                  [Labels{1:length(tibis{i})}] = deal(t.Row{i});
                  h.DataTipTemplate.DataTipRows(1) = dataTipTextRow("Period:",Labels);
                  h.DataTipTemplate.DataTipRows(2) = dataTipTextRow("IBI(t)::",'XData');
                  h.DataTipTemplate.DataTipRows(3) = dataTipTextRow("IBI(t+1):",'YData');
                  h.DataTipTemplate.DataTipRows(4) = dataTipTextRow("Time(s):",tibis{i});

                  e = plot_ellipse(ax, 2*t.SD1(i),2*t.SD2(i),mean(xibis{i}), mean(yibis{i}), 45, col);
                  dt = datatip(e,0,0,'Visible','off'); % weird hack to enable datatips on patches
                  e.DataTipTemplate.DataTipRows = dataTipTextRow("",Labels);
         end
            end
        end
    end
    
    PoinCarePlot(pfigure, ibix, ibiy, ibit, evc, input);

    pfigure.Visible = true;
end

function h=plot_ellipse(ax,a,b,cx,cy,angle,color)
%ax: axes to plot on
%a: width
%b: height 
%cx: horizontal center
%cy: vertical center
%angle: orientation ellipse in degrees
%color: color code (e.g., 'r' or [0.4 0.5 0.1])

angle=angle/180*pi;

r=0:0.1:2*pi+0.1;
p=[(a*cos(r))' (b*sin(r))'];

alpha=[cos(angle) -sin(angle)
    sin(angle) cos(angle)];

p1=p*alpha;
h = patch(ax, cx+p1(:,1),cy+p1(:,2),color,'EdgeColor',color);
h.FaceAlpha = .05;
end
