function [EEGstruct, par] = pop_getIBI(EEGstruct,varargin)
%(ecgData, ecgTimestamps, varargin)
%  GETIBI Detects the IBI values from a ECG trace. Using interpolation to get ms. precision
% 
% Algorithm developed by A.M. van Roon for PRECAR (CARSPAN preprocessing).
% 
% Matlab version M.M.Span (2021)
par = [];
ecgData = EEGstruct.data;
ecgTimestamps = EEGstruct.times;

%% Parse the name - value pairs found in varargin
%------------------------------------------------------------------------------------------
if (~isempty(varargin))
    par = varargin{1};
end
%%  default values:
%% simplest option....
cn = unique({EEGstruct.chanlocs.labels});

if strcmp(par, 'Init')
    par = uiextras.settingsdlg(...
        'Description', 'Set the parameters for getIBI',...
        'title' , 'IBI options',...
        'separator' , 'Parameters:',...
        {'Minimal Peak Distance' ;'MinPeakDistance' }, .33, ...
        {'Use:'; 'channame'}, cn);
end

ecgid = contains({EEGstruct.chanlocs.labels},par.channame);
ecgData = ecgData(ecgid,:);
par.MinPeakHeight = median(ecgData,'omitnan')+(1.5*std(ecgData, 'omitnan'));
fSample = EEGstruct.srate;

%% if the data originate from a polarband: we have the original sampled 
%  data to calculate the ibis from. Do this.

if isfield(EEGstruct, 'Polarchannels') 
    if strcmp(EEGstruct.Polarchannels.chanlocs.labels, par.channame)
        ecgData = double(EEGstruct.Polarchannels.data);
        fSample = EEGstruct.Polarchannels.srate;

        if EEGstruct.Polarchannels.times(2)-EEGstruct.Polarchannels.times(1) >5
            ecgTimestamps = EEGstruct.Polarchannels.times/1000;
        else
            ecgTimestamps = EEGstruct.Polarchannels.times;
        end
        par.MinPeakHeight = median(ecgData, 'omitnan')+(1.5*std(ecgData, 'omitnan'));
    end
end


%% convert MinPeakDistance from ms to samples
MinPeakDistance = par.MinPeakDistance*fSample;


%% Then, first find the (approximate) peaks
[~,locs] = findpeaks(ecgData,'MinPeakHeight',par.MinPeakHeight,...
    'MinPeakDistance',MinPeakDistance);
vals = ecgData(locs);
disp(['*found '  int2str(length(vals))  ' r-tops'])
%% Now the algorithm can start.
%------------------------------------------------------------------------------------------
rc = max(abs(vals - ecgData(locs - 1)), abs(ecgData(locs + 1) - vals));
try
    correction =  (ecgData(locs + 1) - ecgData(locs - 1)) / fSample / 2 ./ abs(rc);
catch ME
    causeException = MException('MATLAB:getIBI:divisionbyzero', 'rc is zero at some point in the data');
    ME = addCause(ME,causeException);
    rethrow(ME);
end

%% Because the eventtimes for the r-top are interpolated they do not fit 
%% the event structure. We keep them separated

if size(ecgTimestamps(locs),1) == size(correction,2)
    ecgTimestamps = ecgTimestamps';
end

if isfield(EEGstruct, 'IBIevent') 
    i = min(length(EEGstruct.IBIevent)+1,2);
    for ie = 1:length(EEGstruct.IBIevent)
        if strcmpi(EEGstruct.IBIevent{ie}.channelname , par.channame)
            i = ie;
        end
    end
    EEGstruct.IBIevent{i}.channelname = par.channame;
    EEGstruct.IBIevent{i}.RTopTime = ecgTimestamps(locs) + correction;
    EEGstruct.IBIevent{i}.RTopVal = ecgData(locs);
    EEGstruct.IBIevent{i}.ibis = round(diff(EEGstruct.IBIevent{i}.RTopTime),3);
else    
    EEGstruct.IBIevent{1}.channelname = par.channame;
    EEGstruct.IBIevent{1}.RTopTime = ecgTimestamps(locs) + correction;
    EEGstruct.IBIevent{1}.RTopVal = ecgData(locs);
    EEGstruct.IBIevent{1}.ibis = round(diff(EEGstruct.IBIevent{1}.RTopTime),3);
end
end
