function input = plotFourier(input, theFig)
%%PlotFourier Plots data in a Brainvision-similar way for Frequencydomain
%data
% ALso creates interactive buttons to change the views, and includes
% callbacks for these function.

%Tools.HideSliders;
bands={'Sub-Delta',0,.5,[119 136 153]/255;
    'Delta',.5,3.5,[255 165 0]/255;
    'Theta',3.5,7.5,'r';
    'Alpha',7.5,12.5,'g';
    'Beta',12.5,30,'b';
    '', 30,1000,'k'
    };

hFig = theFig;
ud = hFig.UserData;
ud.EEG.Freqs = input.freqs;
ud.EEG.Lims = [ 0 floor(input.srate/2) 0 max(input.data(:)) ];
ud.EEG.CurrentTrial = 1;
set(theFig, 'Visible', 'off');
figure(theFig);

[nchan,~,nseg] = size(input.data);

h=max(1,floor(sqrt(nchan)));
w = ceil(nchan/h);

for p = 1:nchan
    ax(p) = uiextras.subplot_tight(w,h,p,[0.035,0.03]); %#ok<AGROW>
    cla;
    hold on;
   for band = 1:6
        tofill = find(ud.EEG.Freqs>cell2mat(bands(band,2)) & ud.EEG.Freqs <=cell2mat(bands(band,3)));
        if ~isempty(tofill)
          if tofill(1) >1
            tofill = [tofill(1)-1 tofill]; %#ok<AGROW>
          end
          area(ud.EEG.Freqs(tofill),input.data(p,tofill,ud.EEG.CurrentTrial), 'EdgeColor', 'k', 'EdgeAlpha', .33, 'FaceColor', cell2mat(bands(band,4)));
        end
   end
  
    
    hold off;
    ti(p) = title(sprintf('Channel %i: %s', p, input.chanlocs(p).labels)); %#ok<AGROW,NASGU>
    axis(ud.EEG.Lims);
    set(ax(p), 'ButtonDownFcn', {@axiscallback, ud.EEG.Freqs, input.data(p,:),sprintf('Channel %i: %s', p, input.chanlocs(p).labels) });
end
linkaxes(ax);

%tightfig;
uicontrol('Style', 'pushbutton', 'String', '+',...
    'Position', [20 5 20 20],...
    'Callback', {@zoomin, input});

uicontrol('Style', 'pushbutton', 'String', '-',...
    'Position', [50 5 20 20],...
    'Callback', {@zoomout, input});

uicontrol('Style', 'pushbutton', 'String', '^',...
    'Position', [80 5 20 20],...
    'Callback', {@blowup, input});

uicontrol('Style', 'pushbutton', 'String', 'v',...
    'Position', [110 5 20 20],...
    'Callback', {@smaller, input});

uicontrol('Style', 'pushbutton', 'String', '<',...
    'Position', [140 5 20 20],...
    'Callback', {@goleft, input});

uicontrol('Style', 'pushbutton', 'String', '>',...
    'Position', [170 5 20 20],...
    'Callback', {@goright, input});

if nseg > 1
    uicontrol('Style', 'pushbutton', 'String', '<<',...
        'Position', [230 5 20 20],...
        'Callback', {@TrialMinus, input});
    
    uicontrol('Style', 'pushbutton', 'String', '>>',...
        'Position', [260 5 20 20],...
        'Callback', {@TrialPlus, input});
    
    mtit(sprintf('Trial: %i',ud.EEG.CurrentTrial ));
end


function axiscallback( ~, ~, freqs, data, mytitle )
bands={'Sub-Delta',0,.5,[119 136 153]/255;
    'Delta',.5,3.5,[255 165 0]/255;
    'Theta',3.5,7.5,'y';
    'Alpha',7.5,12.5,'g';
    'Beta',12.5,30,'b';
    '', 30,1000,'k'
    };


hFig = gcf;
%figure;
in.data = data;
%plot(freqs,data);
hold on;
for band = 1:6
    tofill = find(freqs>cell2mat(bands(band,2)) & freqs <=cell2mat(bands(band,3)));
    if ~isempty(tofill)
       if tofill(1) > 1
           tofill = [tofill(1)-1 tofill]; %#ok<AGROW>
       end
       area(freqs(tofill),data(tofill), 'EdgeColor', cell2mat(bands(band,4)), 'FaceColor', cell2mat(bands(band,4)));
    end
end
plot (freqs, data);
hold off;

title(mytitle);
axis([0 max(freqs) 0 max(data)]);
in.srate = max(freqs)*2;

uicontrol('Style', 'pushbutton', 'String', '+',...
    'Position', [20 5 20 20],...
    'Callback', {@zoomin, in});

uicontrol('Style', 'pushbutton', 'String', '-',...
    'Position', [50 5 20 20],...
    'Callback', {@zoomout, in});

uicontrol('Style', 'pushbutton', 'String', '^',...
    'Position', [80 5 20 20],...
    'Callback', {@blowup, in});

uicontrol('Style', 'pushbutton', 'String', 'v',...
    'Position', [110 5 20 20],...
    'Callback', {@smaller, in});

uicontrol('Style', 'pushbutton', 'String', '<',...
    'Position', [140 5 20 20],...
    'Callback', {@goleft, in});

uicontrol('Style', 'pushbutton', 'String', '>',...
    'Position', [170 5 20 20],...
    'Callback', {@goright, in});


function TrialPlus( ~, ~, data)
hFig = gcf;
ud = hFig.UserData;
if ud.EEG.CurrentTrial < data.trials
    ud.EEG.CurrentTrial = ud.EEG.CurrentTrial + 1;
    set (gcf, 'UserData', ud);
end
plotFourier(data, gcf);

function TrialMinus( ~, ~, data)
hFig = gcf;
ud = hFig.UserData;
if ud.EEG.CurrentTrial > 1
    ud.EEG.CurrentTrial = ud.EEG.CurrentTrial - 1;
    set (gcf, 'UserData', ud);
end
plotFourier(data, gcf);

function zoomin( ~, ~, ~)
oldlim = xlim;
dist = oldlim(2)-oldlim(1);
xlim([oldlim(1) oldlim(1)+(dist/2)]);
hFig = gcf;
hFig.UserData.EEG.Lims = [xlim ylim];


function zoomout( ~, ~, data)
oldlim = xlim;
dist = oldlim(2)-oldlim(1);
xlim([oldlim(1) min(oldlim(1)+(dist*2), data.srate/2)]);
hFig = gcf;
hFig.UserData.EEG.Lims = [xlim ylim];

function blowup( ~, ~, ~)
oldlim = ylim;
dist = oldlim(2)-oldlim(1);
ylim([oldlim(1) oldlim(1)+(dist/2)]);
hFig = gcf;
hFig.UserData.EEG.Lims = [xlim ylim];

function smaller( ~, ~, ~)
oldlim = ylim;
dist = oldlim(2)-oldlim(1);
ylim([oldlim(1) oldlim(1)+(dist*2)]);
hFig = gcf;
hFig.UserData.EEG.Lims = [xlim ylim];

function goleft( ~, ~, ~)
oldlim = xlim;
dist = oldlim(2)-oldlim(1);
newlim = oldlim -(dist/10);
if (newlim(1) <0)
    newlim = newlim - newlim(1);
end
xlim(newlim);
hFig = gcf;
hFig.UserData.EEG.Lims = [xlim ylim];

function goright( ~, ~, data)
oldlim = xlim;
dist = oldlim(2)-oldlim(1);
newlim = oldlim +(dist/10);
if (newlim(2) > (data.srate/2))
    newlim = newlim - (newlim(2) - (data.srate/2));
end
xlim(newlim);
hFig = gcf;
hFig.UserData.EEG.Lims = [xlim ylim];


