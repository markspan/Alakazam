function [EEG, options] = Epoched_IBI_Export(input,opts)
%% function to export the IBI timeseries to an CSV file, optionally creating a new
% timeseries, the resampled IBI timeseries over the original time-axis. 
% can also create the IBI differences as a similar trace.

%% Check for the EEG dataset input:
if (nargin < 1)
    ME = MException('Alakazam:IBIExport','Problem in IBIExport: No Data Supplied');
    throw(ME);
end
if ~isfield(input, 'IBIevent')
    ME = MException('Alakazam:IBIExport','Problem in IBIExport: No IBIS availeable (yet)');
    throw(ME);
end

NDevices  = length(input.IBIevent);

[~,n,~] = fileparts(input.File);
if exist('opts', 'var')
    options = opts;
else    
    options = uiextras.settingsdlg(...
        'Description', 'Set the parameters for ''export'' ibi',...
        'title' , 'IBIExport options',...
        'separator' , 'File Parameters:',...
        {'Filename' ;'fname' }, [n '.csv'],...
        {'Open in Notepad?'; 'np'}, {'no', 'yes'}, ...
        {'Export eventdata', 'ed'}, {'yes', 'no'});
end

srate = input.srate;

RTop = [];  IBI = [];
Device = [];

for dev = 1:NDevices
    RTop = [RTop; squeeze(input.IBIevent{dev}.RTopTime(1:end-1))'];
    IBI  = [IBI;  squeeze(input.IBIevent{dev}.ibis)'];
    Device(end+1:length(RTop)) = dev;
end
Device = Device';

if strcmp(options.ed, 'yes') %% add the empatica data?
    zerodurationevents = input.event([input.event.duration]<=1);
    validevents = zerodurationevents(~isnan(str2double(string({zerodurationevents.type}))));

    %% do this for all possible types:
    % create a new column in the output: named as the type
    IBI = [IBI; str2double(strrep(string({validevents.type}), ',', '.')')];
    RTop  = [RTop; [validevents.latency]'/srate];
    Device(end+1:length(RTop)) = 0;
end

out = table(RTop,IBI,Device);
out.DeviceName = string(out.Device);
for dev = 1:NDevices
    out.DeviceName(out.Device == dev) = input.IBIevent{dev}.channelname;
end
out.DeviceName(out.Device == 0) = "Empatica";

% Create the variables in the table
% TODO exclude zero-duration blocks.

validevents = input.event([input.event.duration]>1);
for type = unique({validevents.type})
    %% do this for all possible types:
    % create a new column in the output: named as the type
    vals = out.IBI.*0;
    eventsofthistype = validevents(string({validevents.type}) == type);

    for i = 1: length(eventsofthistype)
        tstart = eventsofthistype(i).latency/srate;
        tend   = tstart + (eventsofthistype(i).duration/srate);
        vals((out.RTop > tstart) & (out.RTop < tend)) = true;
    end
    out.(strrep(strrep(string(matlab.lang.makeValidName(type)), 'Start', ...
        ''),'_', ''))  = vals;
end


out = sortrows(out,{'RTop','Device'});
ExportsDir = evalin('caller', 'this.Workspace.ExportsDirectory');
writetable(out, fullfile(ExportsDir,options.fname))
if strcmp(options.np , 'yes')
    system(['notepad ' fullfile(ExportsDir,options.fname)]);
end
EEG=input;
