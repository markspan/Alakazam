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
%% Export the IBI timeseries to a CSV file, optionally creating a new
% timeseries, the resampled IBI timeseries over the original time-axis.
% Can also create the IBI differences as a similar trace.

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

% Set options either from input or using a settings dialog
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

% Create a table with RTop and IBI columns
RTop = squeeze(input.IBIevent.RTopTime(1:end-1))';
IBI = squeeze(input.IBIevent.ibis)';
out = table(RTop,IBI);

if (~isfield(input,'lss'))
    input.lss=Tools.EEG2labeledSignalSet(input);
end

if isempty(input.lss.Labels)
    options.bylabel = 'no';
end

% If 'bylabel' option is set to 'yes', create additional columns in the table
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
    % Fill the created columns with the correct values
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

% Save the table to a CSV file in the Exports directory
ExportsDir = evalin('caller', 'this.Workspace.ExportsDirectory');
writetable(out, fullfile(ExportsDir,options.fname))

% Update EEG structure and optionally add IBI differences and/or resample
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

% Modify EEG structure for visualization
EEG.YLabel = 'IBI in ms.'
EEG.data = EEG.data';
EEG = rmfield(EEG, 'IBIevent');

% Update channel labels in EEG structure
EEG.chanlocs(1).labels = 'IBI';
EEG.chanlocs(2).labels = 'IBIdif';
EEG.chanlocs = EEG.chanlocs (1:2);
end

``` 
or this:

``` Matlab

function [EEG, options] = FlipECG(input,opts)
%% Flip the EGC trace if it is upside down....

%% Check for the EEG dataset input:
if (nargin < 1)
    throw(MException('Alakazam:FlipECG','Problem in FlipECG: No Data Supplied'));
end

options = []; % Initialize options

% Check if the 'data' field is present in the input structure
if ~isfield(input, 'data')
    throw(MException('Alakazam:FlipECG','Problem in FlipECG: No Correct Data Supplied'));
else
    EEG = input;
    ecgData = input.data;
end

% Check if there are multiple channels in the data
if (size(ecgData,1) > 1 )
    % Identify channels labeled as 'ECG' (case-insensitive)
    ecgid = startsWith({input.chanlocs.labels},'ECG', 'IgnoreCase', true);
    if sum(ecgid)>0
        % ECG trace found: copy it
        ecgData = ecgData(ecgid,:);

        % Flip the ECG trace
        necgData = -(ecgData - median(ecgData,2)) + median(ecgData,2);

        % Update the EEG data with the flipped ECG trace
        EEG.data(ecgid,:) = necgData;
    else
        throw(MException('Alakazam:FlipECG','Problem in FlipECG: No ECG trace Found/Supplied'));    
    end
end
