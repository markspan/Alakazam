function [EEG, options] = IBI_Export(input,opts)
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
    
[~,n,~] = fileparts(input.File);
if exist('opts', 'var')
    options = opts;
else    
    options = uiextras.settingsdlg(...
        'Description', 'Set the parameters for ''export'' ibi',...
        'title' , 'IBIExport options',...
        'separator' , 'File Parameters:',...
        {'Filename' ;'fname' }, [n '.csv'],...
        {'Open in Notepad?'; 'np'}, {'no', 'yes'},...
        'separator' , 'Use Labels:',...
        {'By Label' ;'bylabel' }, {'yes', 'no'},...
        'separator' , 'New branch:',...
        {'Calculate subsequent differences'; 'cdif'}, {'yes','no'},...
        {'Resample' ; 'rsamp'},  {'yes','no'});       
end

RTop = squeeze(input.IBIevent{1}.RTopTime(1:end-1))';
IBI = squeeze(input.IBIevent{1}.ibis)';
out = table(RTop,IBI);

if (~isfield(input,'lss'))
    input.lss=Tools.EEG2labeledSignalSet(input);
end

if isempty(input.lss.Labels)
    options.bylabel = 'no';
end

if strcmpi(options.bylabel, 'yes')  
    srate = input.srate;
    % Create the variables in the table
    % TODO exclude zero-duration blocks.
    for label = unique({input.urevent.code})
        types = {input.urevent.type};
        labels = {input.urevent.code};
        typeinlabels = types(strcmp(label, labels));
        for value = unique(typeinlabels)
            out = [out table(zeros(length(IBI),1))]; %#ok<AGROW>
            out.Properties.VariableNames(end) = matlab.lang.makeValidName(label + "_" + value);
        end
    end
    % and fill them with the correct values
    for ev = [input.urevent]
        label = ev.code;
        value = ev.type;
        t = out.RTop;
        d = out.(matlab.lang.makeValidName(label + "_" + value));
        tstart = ev.latency / srate;
        tend   = (ev.latency + ev.duration) / srate;
        d((t>tstart) & (t<tend)) = true;
        out.(matlab.lang.makeValidName(label + "_" + value)) = d;
    end
end

ExportsDir = evalin('caller', 'this.Workspace.ExportsDirectory');
writetable(out, fullfile(ExportsDir,options.fname))
if strcmp(options.np , 'yes')
    system(['notepad ' fullfile(ExportsDir,options.fname)]);
end

EEG=input;
if (strcmp(options.cdif, 'yes'))
    EEG.data = double([1.0./input.IBIevent{1}.ibis' [NaN diff(input.IBIevent{1}.ibis)]']);
    EEG.nbchan = 2;
else
    EEG.data = double(input.IBIevent{1}.ibis');
    EEG.nbchan = 1;
end

if (strcmp(options.rsamp, 'yes'))
    [EEG.data, EEG.times] = resample(EEG.data, double(EEG.IBIevent{1}.RTopTime(1:end-1)), EEG.srate);
else
    EEG.times = double(EEG.IBIevent{1}.RTopTime(1:end-1));
    EEG.srate = 0;
end    

EEG.YLabel = 'IBI in ms.';
EEG.data = EEG.data';
EEG = rmfield(EEG, 'IBIevent');

EEG.chanlocs(1).labels = 'RR interval';
EEG.chanlocs(2).labels = 'IBIdif';
EEG.chanlocs = EEG.chanlocs (1:2);



