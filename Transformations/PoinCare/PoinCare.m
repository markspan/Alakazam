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
        {'By Label' ;'bylabel' }, {'on', 'off'}, ...
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

if ~strcmp(options.bylabel, 'on')
    %% This is the plot when no labels are used.
    ibix = input.IBIevent{1}.ibis(1:end-options.delta);
    ibiy = input.IBIevent{1}.ibis(1+options.delta:end);

    sd1 = round((sqrt(2)/2.0) * std(ibix-ibiy),3);
    sd2 = round( sqrt(2*std(ibix)^2) - (.5*std(ibix-ibiy)^2),3);

    h=plot(pax, ibix, ibiy, ['r' type]);

    if options.origin
        a=xlim;
        xlim([0 a(2)])
        ylim([0 a(2)])
    end
    hold on
    plot (pax, xlim, ylim, ':b', 'LineWidth', 1);
    xlabel("IBI_(_t_)");
    ylabel("IBI_(_t_+_1_)");

    axis square;
    title(pax, input.id);
    grid minor;

    if options.ell
        plot_ellipse(2*sd1,2*sd2,mean(ibix), mean(ibiy), 45, get(h,'Color'));
    end

    % make it into a subplot:
    subplot(1,2,1,pax);

    %% create the info plot with the parameters
    anax = subplot(1,2,2);
    pars = {"     SD1 = " + num2str(sd1) + " s"};
    pars{end+1} = "     SD2 = " + num2str(sd2) + " s";
    pars{end+1} = "     SD2/SD1 = " + num2str(round(sd2/sd1,2));

    plot(anax, 0);
    set(anax, 'XTick', [], 'YTick', [], 'Box', 'off',...
        'Color', [.98 .98 .98], ...
        'XColor', 'none', 'YColor', 'none');
    anax.Toolbar.Visible = 'off';
    axis square;
    title('Parameters:', 'Poincare')
    set(anax,'TitleHorizontalAlignment', 'left');
    text(0,1,pars, 'VerticalAlignment', 'top');
else
    %% Same plot, but now for each of the levels of the selected label.
    ibix = input.IBIevent{1}.ibis(1:end-options.delta)';
    ibiy = input.IBIevent{1}.ibis(1+options.delta:end)';
    ibit = input.IBIevent{1}.RTopTime(1:end-1-options.delta)' * input.srate;
    sd1=[];sd2=[];name={};h=[];
    plot (pax, xlim, ylim, ':b', 'LineWidth', 1);

    for i = 1:length(evc)
        lab = evc(i);
        event = strcmp({input.event.type}, lab);
        try
            idx = ibit > input.event(event).latency & ibit < (input.event(event).latency+input.event(event).duration);
        catch e
        end
        if sum(idx) > 0
            ix = ibix(idx);
            iy = ibiy(idx);
            %% this is the 'subplot' per label:
            h(end+1) = plot(pax, ix, iy, type, 'MarkerSize', 8);
            col = get(h(i),'Color');
            hold on
            %calculate the parameters for the infopanes...
            sd1(end+1) = round( (sqrt(2)/2.0) * std(ix-iy), 3);
            sd2(end+1) = round( sqrt(2*std(ix)^2 ) - (.5*std(ix-iy)^2),3);
            name{end+1} = char(lab);
            if options.ell
                plot_ellipse(2*sd1(end),2*sd2(end),mean(ix), mean(iy), 45, col);
            end
        end
    end
   
    %% draw zoomed in to the dots, of from the origin?
    if options.origin
        a=xlim;
        xlim([0 1])
        ylim([0 1])
    end

    xlabel("IBI_(_t_)");
    ylabel("IBI_(_t_+_1_)");

    axis square;
    %title(pax, input.id);
    plot (pax, xlim, ylim, ':r', 'LineWidth', 1);
    grid minor;
    % make it into a subplot:
    subplot(1,2,1,pax);
    %% create the info plot with the parameters
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
        pars{end+1} = "     SD1 = " + num2str(sd1(i)) + " s";
        pars{end+1} = "     SD2 = " + num2str(sd2(i)) + " s";
        pars{end+1} = "     SD2/SD1 = " + num2str(round(sd2(i)/sd1(i),2));
    end
    text(0,1,pars, 'VerticalAlignment', 'top');
    legend(pax, evc, 'Location', 'southeast');

end
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

