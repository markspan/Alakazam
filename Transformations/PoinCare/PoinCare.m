function [pfigure, options] = PoinCare(input,opts)
%% Create a poincare plot for the IBI series
% The ibis are plotted agains a time-delayed version of the same values. If
% the 'bylabel' option is used, the plot has different partitions for each
% value the label takes on.

%#ok<*AGROW>

%% Check for the EEG dataset input:
if (nargin < 1)
    ME = MException('Alakazam:PoinCare','Problem in PoinCare: No Data Supplied');
    throw(ME);
end
if ~isfield(input, 'IBIevent')
    ME = MException('Alakazam:PoinCare','Problem in IBIExport: No IBIS availeable (yet)');
    throw(ME);
end

%% Was this a call from the menu?
if (nargin == 1)
    options = 'Init';
else
    options = opts;
end

pfigure = uifigure('Visible', false, 'Units', 'normalized');

ev = [];
if isfield(input, 'event') && isfield(input.event, 'type') && ~isempty({input.event.type})
    ev = unique([input.event.type], 'stable');
    evc = ev;
end

%% simplest option....
if strcmp(options, 'Init')
    options = uiextras.settingsdlg(...
        'Description', 'Set the parameters for PoinCare Plot',...
        'title' , 'PoinCare options',...
        'separator' , 'Plot Parameters:',...
        {'Delta' ;'delta' }, 1,...
        {'Origin included'; 'origin'}, [true, false],...
        'separator' , 'Ellipses:',...
        {'Plot Ellipses' ;'ell' }, [true, false], ...
        'separator' , 'Use Labels:',...
        {'By Label' ;'bylabel' }, {'on', 'off'}, ...
        {'Use Unlabeled' ;'unlabeled' }, {'off', 'on'});
end


ibix = input.IBIevent{1}.ibis(1:end-options.delta);
ibiy = input.IBIevent{1}.ibis(1+options.delta:end);
ibit = input.IBIevent{1}.RTopTime(1:end-1-options.delta);

    function t = PoinCarePlot(fig,ibix, ibiy, ibit, options, evc, input)
    % Create table array
    RMSSD =[];
    mIBI = [];
    SD1=[];
    SD2=[];
    x={};
    y={};
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
        SD1(end+1) = round((sqrt(2)/2.0) * std(ibix(idx)-ibiy(idx)),3);
        SD2(end+1) = round( sqrt(2*std(ibix(idx))^2) - (.5*std(ibix(idx)-ibiy(idx))^2),3);
        RMSSD(end+1) = Tools.HRV.RMSSD(ibix(idx));
        mIBI(end+1) = mean(ibix(idx));
    end
    pSD1SD2 = SD1./SD2;
    cRMSSD = RMSSD./mIBI;
    Plotted = mIBI > 0;

    t = table(Plotted', SD1', SD2', pSD1SD2', RMSSD', mIBI', cRMSSD', ...
        'VariableNames',["Plot","SD1","SD2","SD1/SD2","RMSSD","mean(IBI)","cRMSSD"], ... 
        'RowNames',evc);

    gl = uigridlayout(fig, [1 2]);

    % Create UI figure
    % Create table UI component
    uit = uitable(gl);
    uit.Layout.Row = 1;
    uit.Layout.Column = 2;
    uit.Data = t;
    uit.ColumnSortable = false;
    uit.ColumnEditable = [true false false false false false false ];
    uit.DisplayDataChangedFcn = @updatePlot;

    % Create PoinCare chart
    ax = uiaxes(gl);
    ax.Layout.Row = 1;
    ax.Layout.Column = 1;
    
    lPoincarePlot(t, x, y)

        % Update the bubble chart when table data changes
        function updatePlot(~,~)
            t = uit.DisplayData;
            lPoincarePlot(t,x,y)
        end
        function lPoincarePlot(t,xibis,yibis)
            cla(ax);
            
            xlabel(ax, "IBI_(_t_)");
            ylabel(ax, "IBI_(_t_+_1_)");

            xlim(ax, [0 1])
            ylim(ax, [0 1])

            for i = 1:length(t.Plot)
                if (t.Plot(i))
                  col = ax.ColorOrder(mod(i-1,7)+1,:);
                  hold(ax, 'on')
                  scatter(ax,xibis{i}, yibis{i}, 'MarkerEdgeColor',col, 'DisplayName', char(t.Row(i)) );
                  plot_ellipse(ax, 4*t.SD1(i),4*t.SD2(i),mean(xibis{i}), mean(yibis{i}), 45, col);
                end
            end
        end
    end

    PoinCarePlot(pfigure, ibix, ibiy, ibit, options, evc, input);
    pfigure.Visible = true;
end

function h=plot_ellipse(ax,a,b,cx,cy,angle,color)
%a: width in pixels
%b: height in pixels
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
%     h.DataTipTemplate.DataTipRows(1).Label = "ibi_(_t_)";
%     h.DataTipTemplate.DataTipRows(2).Label = "ibi_(_t_+_1_)";
%     h.DataTipTemplate.DataTipRows(end+1:end+1) = dataTipTextRow("time (s):",ibit);
%     [k{1:length(ibit)}] = deal(label);
%     h.DataTipTemplate.DataTipRows(end+1:end+1) = dataTipTextRow("ID:",k);

