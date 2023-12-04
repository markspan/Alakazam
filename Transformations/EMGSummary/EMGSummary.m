function [EEG, opts] = EMGSummary(input,opts)
%% Check for the EEG dataset input:
if (nargin < 1)
    throw(MException('Alakazam:EMGSummary','Problem in EMGSummary: No Data Supplied'));
end

if (nargin == 1)
    opts = 'Init';
end

EEG = input;
cn = {input.chanlocs.labels};

if strcmp(opts, 'Init')
    opts = uiextras.settingsdlg(...
        'Description', 'Set the parameters for EMGSummary',...
        'title' , 'Rectify options',...
        'separator' , 'Parameters:',...
        {'Use:'; 'channame'}, cn, ...
        {'Pre-Time (s): '; 'pretime'}, 10,...
        {'Post-Time (s): '; 'posttime'}, 10);
end

events = input.event;

chan = find(strcmp({EEG.chanlocs.labels}, opts.channame));
for i = 1:length(events)
    try
        id = string(strrep(EEG.filename, '.xdf', ''));
        evn = string(events(i).type);
        startindex = max(events(i).latency - (EEG.srate * opts.pretime),1);
        endindex = min(events(i).latency + (EEG.srate * opts.posttime), EEG.pnts);
        pre = mean(EEG.data(chan,startindex:events(i).latency)', 'omitnan'); %#ok<UDIM> 
        post = mean(EEG.data(chan,events(i).latency:endindex)', 'omitnan'); %#ok<UDIM> 
        line = table(id, evn, pre, post);
        if(exist('csvtable', 'var'))
            csvtable = [csvtable; line]; %#ok<AGROW> 
        else
            csvtable=line;
        end
    catch e %#ok<NASGU> 
        disp("should not occur in EMGSummary");
    end
end
fname = string(strrep(EEG.filename, '.xdf', '.csv'));
ExportsDir = evalin('caller', 'this.Workspace.ExportsDirectory');
writetable(csvtable, fullfile(ExportsDir,fname))

