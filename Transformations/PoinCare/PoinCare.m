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

pfigure = figure('NumberTitle', 'off', 'Name', 'PoinCare','Tag', input.File, ...
    'Renderer', 'painters' , ...
    'Color' ,[.98 .98 .98], ...
    'PaperOrientation','landscape', ...
    'PaperPosition',[.05 .05 .9 .9], ...
    'PaperPositionMode', 'auto',...
    'PaperType', 'A0', ...
    'Units', 'normalized', ...
    'MenuBar', 'none', ...
    'Toolbar', 'none',...
    'DockControls','on', ...
    'Visible','off' ...
    );

ev = [];

if isfield(input, 'event') && isfield(input.event, 'type') && ~isempty({input.event.type})
    ev = unique({input.event.type});
    evc = ev(contains(ev, "pressed"));
end

%% simplest option....
if strcmp(options, 'Init')
    options = uiextras.settingsdlg(...
        'Description', 'Set the parameters for PoinCare Plot',...
        'title' , 'PoinCare options',...
        'separator' , 'Plot Parameters:',...
        {'Delta' ;'delta' }, 1,...
        {'Origin included'; 'origin'}, [true, false],...
        {'Dots or Lines?'; 'type'}, {'dots','lines', 'both'},...
        'separator' , 'Ellipses:',...
        {'Plot Ellipses' ;'ell' }, [true, false], ...
        'separator' , 'Use Labels:',...
        {'By Label' ;'bylabel' }, {'off', 'on'}, ...
        {'Label Contains:'; 'label'}, "pressed" , ...
        {'Use Unlabeled' ;'unlabeled' }, {'off', 'on'});
end

if length(options.label) ~=7 && ~strcmpi(options.label, "pressed")
    evc = ev(contains(ev, options.label));
end
if strcmp(options.type, 'lines')
    type = '-';
elseif strcmp(options.type, 'both')
    type = '-o';
else
    type = 'o';
end

pax = axes(pfigure);

ibix = input.IBIevent{1}.ibis(1:end-options.delta);
ibiy = input.IBIevent{1}.ibis(1+options.delta:end);
ibit = input.IBIevent{1}.RTopTime(1:end-1-options.delta);

if (~strcmp(options.bylabel, 'on'))
    %% This is the plot when no labels are used.
    label = "Full Epoch";
    [h, sd1,sd2] = PCPlot(pax,ibix,ibiy, ibit, type, input, options.ell,1, label);
    subplot(1,2,1,pax);
    PCInfo(label, sd1, sd2)
else
    h=[];
    sd1=[];
    sd2=[];
    for i = 1:length(evc)
        label = evc(i);
        event = [strcmp({input.event.type}, label)];
        idx = ibit<0;
        for e = 1:length(input.event(event)) %% when there are more events
            elist = [input.event(event)];
            ev = elist(e);
            idx = idx | (ibit > ev.latency/input.srate) & (ibit < (((ev.latency+ev.duration)/input.srate)));
        end
        [h(end+1), sd1(end+1),sd2(end+1)] = PCPlot(pax,ibix(idx),ibiy(idx), ibit(idx), type, input, options.ell,i, label);
        hold on
    end
    subplot(1,2,1,pax);
    PCInfo(evc, sd1, sd2)
end

if options.origin
    axes(pax)
    a=xlim;
    xlim([0 a(2)])
    ylim([0 a(2)])
end

xlabel("IBI_(_t_)");
ylabel("IBI_(_t_+_1_)");
legend(h);
legend('boxoff')
end

function PCInfo(name, sd1, sd2)
%% 
%   PCInfo plots the test statistics next to the plot
%
%
%%
anax = subplot(1,2,2);
plot(anax, 0);
set(anax, 'XTick', [], 'YTick', [], 'Box', 'off',...
    'Color', [.98 .98 .98], ...
    'XColor', 'none', 'YColor', 'none');

anax.Toolbar.Visible = 'off';
axis square;
set(anax,'TitleHorizontalAlignment', 'left');
title('Parameters:', 'Poincare')

pars = {};
for i = 1:length(sd1)
    %labels(i) = {[char(labels(i)) ' (sd1= '  num2str(sd1(i)) ' sd2= '  num2str(sd2(i)) ')']};
    pars{end+1} = name{i};
    pars{end+1} = "     SD1 = " + num2str(sd1(i)) + " s -" + "     SD2 = " + num2str(sd2(i)) + " s -" + "     SD2/SD1 = " + num2str(round(sd2(i)/sd1(i),2));
end
fs = 12;
if length(pars) > 45
    fs = fs / 2;
end
text(0,1,pars, 'VerticalAlignment', 'top', 'FontSize', fs);
end

function [h, sd1, sd2]=PCPlot(pax,ibix,ibiy,ibit, type, input, ell, i, label)
%% 
%   PCPlot plots the poincare map
%
%
%%

col = pax.ColorOrder(mod(i-1,7)+1,:);
hold on
h=scatter(pax,ibix, ibiy, type, 'MarkerEdgeColor',col, 'DisplayName', char(label) );
axis square;
title(pax, input.id);
grid minor;

if ell
    sd1 = round((sqrt(2)/2.0) * std(ibix-ibiy),3);
    sd2 = round( sqrt(2*std(ibix)^2) - (.5*std(ibix-ibiy)^2),3);
    plot_ellipse(4*sd1,4*sd2,mean(ibix), mean(ibiy), 45, col);
end

% make it into a subplot:

h.DataTipTemplate.DataTipRows(1).Label = "ibi_(_t_)";
h.DataTipTemplate.DataTipRows(2).Label = "ibi_(_t_+_1_)";
h.DataTipTemplate.DataTipRows(end+1:end+1) = dataTipTextRow("time (s):",ibit);
[k{1:length(ibit)}] = deal(label);
h.DataTipTemplate.DataTipRows(end+1:end+1) = dataTipTextRow("ID:",k);
end

function h=plot_ellipse(a,b,cx,cy,angle,color)
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

h = patch(cx+p1(:,1),cy+p1(:,2),color,'EdgeColor',color);
h.FaceAlpha = .05;

end
