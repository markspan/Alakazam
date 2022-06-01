# Alakazam
Modular ECG analysis software package in MATLAB

![Screenshot](/ScreenShot.jpg)

The general idea is to create a user interface to do ECG analysis. This is work in progress!
Currently reading [Brainvision files](https://www.brainproducts.com/), [Cortrium files](https://www.cortrium.com/), EDF files / XDF files and .mat files made from [EEGLAB](https://sccn.ucsd.edu/eeglab/index.php)

The interface is based on the [Toolgroup](http://undocumentedmatlab.com/articles/matlab-toolstrip-part-2-toolgroup-app) demo, and is very much influenced by the "[Brainvision Analyser](https://www.brainproducts.com/promo_analyzer2.php)" interface.
Timeseries plotting based on [plotECG](https://nl.mathworks.com/matlabcentral/fileexchange/59296-daniel-frisch-kit-plot-ecg)  by Daniel Frisch. 
The generic data object used for a study is the [EEGLAB](https://sccn.ucsd.edu/eeglab/index.php) "EEG" structure. Alakazam does put some extra info in this structure when it writes its own .mat files.
Take a look at the "Transformations" directory to get the idea of how to add computations to the package.

This is a simple example from there:

``` Matlab
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
        {'By Label' ;'bylabel' }, {'yes', 'no'},...
        'separator' , 'New branch:',...
        {'Calculate subsequent differences'; 'cdif'}, {'yes','no'},...
        {'Resample' ; 'rsamp'},  {'yes','no'});       
end

RTop = squeeze(input.IBIevent.RTopTime(1:end-1))';
IBI = squeeze(input.IBIevent.ibis)';
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

EEG=input;
if (strcmp(options.cdif, 'yes'))
    EEG.data = double([input.IBIevent.ibis' [NaN diff(input.IBIevent.ibis)]']);
    EEG.nbchan = 2;
else
    EEG.data = double(input.IBIevent.ibis');
    EEG.nbchan = 1;
end

if (strcmp(options.rsamp, 'yes'))
    [EEG.data, EEG.times] = resample(EEG.data, double(EEG.IBIevent.RTopTime(1:end-1)), EEG.srate);
else
    EEG.times = double(EEG.IBIevent.RTopTime(1:end-1));
    EEG.srate = 0;
end    
EEG.YLabel = 'IBI in ms.'
EEG.data = EEG.data';
EEG = rmfield(EEG, 'IBIevent');

EEG.chanlocs(1).labels = 'IBI';
EEG.chanlocs(2).labels = 'IBIdif';
EEG.chanlocs = EEG.chanlocs (1:2);

``` 
or this:

``` Matlab

function [EEG, options] = FlipECG(input,opts)
%% Flip the EGC trace if it is upside down....

%% Check for the EEG dataset input:
if (nargin < 1)
    throw(MException('Alakazam:FlipECG','Problem in FlipECG: No Data Supplied'));
end

options = [];

if ~isfield(input, 'data')
    throw(MException('Alakazam:FlipECG','Problem in FlipECG: No Correct Data Supplied'));
else
    EEG = input;
    ecgData = input.data;
end

if (size(ecgData,1) > 1 )
    ecgid = startsWith({input.chanlocs.labels},'ECG', 'IgnoreCase', true);
    if sum(ecgid)>0
        %% there is an ECG trace: flip it
        ecgData = ecgData(ecgid,:);
        necgData = -(ecgData - median(ecgData,2)) + median(ecgData,2);
        EEG.data(ecgid,:) = necgData;
    else
        throw(MException('Alakazam:FlipECG','Problem in FlipECG: No ECG trace Found/Supplied'));    
    end
end
