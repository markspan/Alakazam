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
        {'Minimal Peak Distance' ;'MinPeakDistance' }, .3, ...
        {'WinLength' ;'Tw' }, 51, ...
        {'limit in sd' ;'Nsd' }, 4, ...
        {'Max interpolation duration' ;'Tmax' }, 5, ...
        {'Use:'; 'channame'}, cn);
end

ecgid = contains({EEGstruct.chanlocs.labels},par.channame);
ecgData = ecgData(ecgid,:);
par.MinPeakHeight = median(ecgData,'omitnan')+(2*std(ecgData, 'omitnan'));
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
        %ecgData(ecgData < prctile(ecgData,.01) | ecgData > prctile(ecgData, 99.99)) = nan;
        par.MinPeakHeight = median(ecgData, 'omitnan')+(1.5*std(ecgData, 'omitnan'));
    end
end
%% convert MinPeakDistance from ms to samples
MinPeakDistance = par.MinPeakDistance*fSample;
%% Then, first find the (approximate) peaks
[vals,locs] = findpeaks(ecgData, 'MinPeakHeight', par.MinPeakHeight,...
    'MinPeakDistance',MinPeakDistance);
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

classID = IBIClassification(ecgTimestamps(locs) + correction, par.Tw, par.Nsd, par.Tmax); %% (p45 of CARSPAN MANUAL 2.0)
[cRTopTimes,ecgData, classID] = RTCorrection(ecgTimestamps(locs) + correction, ecgData(locs), classID);

%cRTopTimes = ecgTimestamps(locs) + correction;
%ecgData =  ecgData(locs);
%EEGstruct.data(ecgid,:) =  ecgData; 

if isfield(EEGstruct, 'IBIevent') 
    i = min(length(EEGstruct.IBIevent)+1,2);
    for ie = 1:length(EEGstruct.IBIevent)
        if strcmpi(EEGstruct.IBIevent{ie}.channelname , par.channame)
            i = ie;
        end
    end
    EEGstruct.IBIevent{i}.channelname = par.channame;
    EEGstruct.IBIevent{i}.RTopTime = cRTopTimes;
    EEGstruct.IBIevent{i}.RTopVal = ecgData;
    EEGstruct.IBIevent{i}.ibis = round(diff(EEGstruct.IBIevent{i}.RTopTime),3);
    EEGstruct.IBIevent{i}.classID = classID;
else    
    EEGstruct.IBIevent{1}.channelname = par.channame;
    EEGstruct.IBIevent{1}.RTopTime = cRTopTimes;
    EEGstruct.IBIevent{1}.RTopVal = ecgData;
    EEGstruct.IBIevent{1}.ibis = round(diff(EEGstruct.IBIevent{1}.RTopTime),3);
    EEGstruct.IBIevent{1}.classID = classID;
end
end

function [RTout, ecgData, classID] = RTCorrection(RTin, ecgData, classID)
    RTout = RTin;
    for i = 1:length(classID)-1
        if classID(i) == "S"
            RTout(i) = 0; % mark for removal
            ecgData(i) = nan;
            classID(i) = "";
        end
        if classID(i) == "L"
            if i>1
                delta = ecgData(i) / mean([ecgData(i-1), ecgData(i+1)]); 
                if (delta > 2.0)
                    %% interpolate a beat after this one,
                    % and recalculate *this* ibi
                    % nRT is the new RtopTime (halfway)
                    % and the associated IBI is now halved 
                    nRt     = mean([RTin(i), RTin(i+1)]);
                    nIBI    = ecgData(i)/2;
                    RTout   = [RTout(1:i) nRt RTout((i+1):end)];
                    classID(i) = 't'; 
                    %% t means an interpolated, previously long (L) IBI. 
                    % Always followed by an 'i', the interpolated rtop 

                    %% The actual interpolation(s) (Rtop and IBI)
                    ecgData = [ecgData(1:i) nIBI ecgData((i+1):end)];
                    classID = [classID(1:i) 'i' classID((i+1):end)];
                end
            end
        end
    end
    classID(classID=="") = [];% remove 
    RTout(RTout==0) = []; % remove 
    ecgData(isnan(ecgData)) = []; % remove 
end

function classID = IBIClassification(RTT, Tw, Nsd, Tmax)
    %%Classification:
    %
    %   default params:
    %       Tw = 50 (sec!) (###Implemented as 51 IBIs!###)
    %       Nsd = 4 (sd)
    %       T refractory = .3
    %       Tmax = 5 (sec)
    %
    %%
    %%
    % Normal beat: Calculate mean IBI around current over time Tw -> avIBIr
    %               Calculate the SD of this vaiable              -> SD(avIBIr)
    %               if the value is within the Running average and Nsd times
    %               the SD: This is a normal Beat
    % else:
    %       short beat: below this min value
    %       long beat : above this max value
    %

    %% Additional Classifications: 
    % vagal Inhibition (WARNING, no correction)
    % vagal activation (WARNING, no correction)
    
    %% Short followed by long:
    % remove R-peak, interpolate (WARNING)
    
    %% Short - Normal - Short
    % Interpolate (WARNING) @AvR What??
    
    %% Short Beat:
    % if IBI < Trefractory: 
    %   Remove R-peak 
    % Is implemented in the findpeaks function
    %% else:
    %   if nFit = 1: remove R-Peak %% @AvR: Q1: what is nFit?
    %   if nFit = 2: remove R-Peak, interpolate %  implemented
    %   if else: No correction, unknown artefact
    
    %% Long Beat:
    % if IBI > Tmax: Split Block (WARNING)
    % interpolate

    %% Output Labels:
    % N = Normal
    % L = Long
    % S = Short
    % T = Too long (@AvR: to interpolate?)

    % I = inhibition (NOT YET IMPLEMENTED)
    % A =  Activation (NOT YET IMPLEMENTED)

    % 1 = short-long 
    % 2 = short-normal-short

    IBI = diff(RTT);

    classID(1:length(IBI)+1) = "N"; %% The default

    avIBIr = movmean(IBI, Tw);
    SDavIBIr = movstd(IBI, Tw);
    
    lower = avIBIr - (Nsd .* SDavIBIr);
    higher = avIBIr + (Nsd .* SDavIBIr);

    classID(IBI > higher) = "L"; %% Long IBI
    classID(IBI < lower)  = "S"; %% Short IBI
    classID(IBI > Tmax)   = "T"; %% Too Long

    for i = 1:length(classID)-1
        if classID(i) == "S" && classID(i+1) == "L"
            classID(i) = "1"; %% Short - long
        end
        if i ~= length(classID)-2
            if classID(i) == "S" && classID(i+1) == "N" && classID(i+2) == "S" 
                classID(i) = "2"; %% short - normal - short
            end
        end
    end
    for id = unique(classID)
        d = "Found " + length(classID(classID==id)) + " " + id + " rtops";
        disp(d)
    end
end