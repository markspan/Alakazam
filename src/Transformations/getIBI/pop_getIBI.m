function [EEGstruct, par] = pop_getIBI(EEGstruct, varargin)
% POP_GETIBI Detects the Inter-Beat Interval (IBI) values from an ECG trace.
% This function uses interpolation to achieve millisecond precision.
%
% Syntax:
%   [EEGstruct, par] = pop_getIBI(EEGstruct, varargin)
%
% Inputs:
%   EEGstruct - Structure containing EEG data, ECG data, and relevant metadata.
%   varargin  - Optional parameter-value pairs to customize IBI detection.
%
% Outputs:
%   EEGstruct - Updated structure with detected IBI events.
%   par       - Parameters used for IBI detection.
%
% Algorithm developed by A.M. van Roon for PRECAR (CARSPAN preprocessing).
% Matlab version by M.M. Span (2021).

    % Initialize parameters
    par = [];
    ecgData = EEGstruct.data;
    ecgTimestamps = EEGstruct.times;

    % Parse optional parameters
    if (~isempty(varargin))
        par = varargin{1};
    end

    % Default values and channel handling
    try
        cn = unique({EEGstruct.chanlocs.labels});
    catch
        ecgid = 1;
        cn = 'ECG';
    end

    % Initialize parameters if specified
    if strcmp(par, 'Init')
        par = uiextras.settingsdlg(...
            'Description', 'Set the parameters for getIBI', ...
            'title', 'IBI options', ...
            'separator', 'Parameters:', ...
            {'Minimal Peak Distance'; 'MinPeakDistance'}, 0.3, ...
            {'Window Length'; 'Tw'}, 51, ...
            {'Limit in SD'; 'Nsd'}, 4, ...
            {'Max Interpolation Duration'; 'Tmax'}, 5, ...
            {'Use Channel'; 'channame'}, cn);
    end

    % Determine ECG channel ID
    try
        ecgid = contains({EEGstruct.chanlocs.labels}, par.channame);
    catch
        % Do nothing if channel name is not found: presume there is only
        % one channel and use that.
    end

    ecgData = ecgData(ecgid, :);
    par.MinPeakHeight = median(ecgData, 'omitnan') + (2 * std(ecgData, 'omitnan'));
    fSample = EEGstruct.srate;

    % Check for Polarband data and handle accordingly
    if isfield(EEGstruct, 'Polarchannels')
        if strcmp(EEGstruct.Polarchannels.chanlocs.labels, par.channame)
            ecgData = double(EEGstruct.Polarchannels.data);
            fSample = EEGstruct.Polarchannels.srate;

            if EEGstruct.Polarchannels.times(2) - EEGstruct.Polarchannels.times(1) > 5
                ecgTimestamps = EEGstruct.Polarchannels.times / 1000;
            else
                ecgTimestamps = EEGstruct.Polarchannels.times;
            end

            par.MinPeakHeight = median(ecgData, 'omitnan') + (1.5 * std(ecgData, 'omitnan'));
        end
    end

    % Convert MinPeakDistance from ms to samples
    MinPeakDistance = par.MinPeakDistance * fSample;

    % Find approximate peaks
    [vals, locs] = findpeaks(ecgData, 'MinPeakHeight', par.MinPeakHeight, 'MinPeakDistance', MinPeakDistance);
    disp(['*found ' int2str(length(vals)) ' r-tops'])

    % Calculate correction for peak times
    rc = max(abs(vals - ecgData(locs - 1)), abs(ecgData(locs + 1) - vals));
    try
        correction = (ecgData(locs + 1) - ecgData(locs - 1)) / fSample / 2 ./ abs(rc);
    catch ME
        causeException = MException('MATLAB:getIBI:divisionbyzero', 'rc is zero at some point in the data');
        ME = addCause(ME, causeException);
        rethrow(ME);
    end

    % Adjust event times with correction
    if size(ecgTimestamps(locs), 1) == size(correction, 2)
        ecgTimestamps = ecgTimestamps';
    end

    classID = IBIClassification(ecgTimestamps(locs) + correction, par.Tw, par.Nsd, par.Tmax);
    [cRTopTimes, ecgData, classID] = RTCorrection(ecgTimestamps(locs) + correction, ecgData(locs), classID);

    % Update EEG structure with detected IBI events
    if isfield(EEGstruct, 'IBIevent')
        i = min(length(EEGstruct.IBIevent) + 1, 2);
        for ie = 1:length(EEGstruct.IBIevent)
            if strcmpi(EEGstruct.IBIevent{ie}.channelname, par.channame)
                i = ie;
            end
        end
        EEGstruct.IBIevent{i}.channelname = par.channame;
        EEGstruct.IBIevent{i}.RTopTime = cRTopTimes;
        EEGstruct.IBIevent{i}.RTopVal = ecgData;
        EEGstruct.IBIevent{i}.ibis = round(diff(EEGstruct.IBIevent{i}.RTopTime), 3);
        EEGstruct.IBIevent{i}.classID = classID;
    else
        EEGstruct.IBIevent{1}.channelname = par.channame;
        EEGstruct.IBIevent{1}.RTopTime = cRTopTimes;
        EEGstruct.IBIevent{1}.RTopVal = ecgData;
        EEGstruct.IBIevent{1}.ibis = round(diff(EEGstruct.IBIevent{1}.RTopTime), 3);
        EEGstruct.IBIevent{1}.classID = classID;
    end
end

function [RTout, ecgData, classID] = RTCorrection(RTin, ecgData, classID)
% RTCorrection Corrects R-top times and interpolates to handle short and long IBIs.
%
% Syntax:
%   [RTout, ecgData, classID] = RTCorrection(RTin, ecgData, classID)
%
% Inputs:
%   RTin     - Initial R-top times.
%   ecgData  - ECG data corresponding to R-top times.
%   classID  - Classification of IBIs.
%
% Outputs:
%   RTout    - Corrected R-top times.
%   ecgData  - Adjusted ECG data.
%   classID  - Updated classification of IBIs.

    RTout = RTin;
    for i = 1:length(classID) - 1
        if classID(i) == "S"
            RTout(i) = 0; % Mark for removal
            ecgData(i) = nan;
            classID(i) = "";
        end
        if classID(i) == "L"
            if i > 1
                delta = ecgData(i) / mean([ecgData(i - 1), ecgData(i + 1)]);
                if (delta > 2.0)
                    % Interpolate a beat after this one and recalculate this IBI
                    nRt = mean([RTin(i), RTin(i + 1)]);
                    nIBI = ecgData(i) / 2;
                    RTout = [RTout(1:i) nRt RTout((i + 1):end)];
                    classID(i) = 't'; % Mark as interpolated, previously long IBI
                    ecgData = [ecgData(1:i) nIBI ecgData((i + 1):end)];
                    classID = [classID(1:i) 'i' classID((i + 1):end)];
                end
            end
        end
    end
    classID(classID == "") = []; % Remove empty classifications
    RTout(RTout == 0) = []; % Remove marked R-top times
    ecgData(isnan(ecgData)) = []; % Remove NaN values
end

function classID = IBIClassification(RTT, Tw, Nsd, Tmax)
%% IBIClassification Classifies IBIs based on statistical thresholds.
%
% Syntax:
%   classID = IBIClassification(RTT, Tw, Nsd, Tmax)
%
% Inputs:
%   RTT  - R-top times.
%   Tw   - Window length for moving average (default: 50 seconds).
%   Nsd  - Number of standard deviations for classification threshold (default: 4).
%   Tmax - Maximum duration for IBI (default: 5 seconds).
%
% Outputs:
%   classID - Classification of IBIs ('N', 'L', 'S', 'T', '1', '2').
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

    classID(IBI > higher) = "L"; % Long IBI
    classID(IBI < lower)  = "S"; % Short IBI
    classID(IBI > Tmax)   = "T"; % Too Long

    for i = 1:length(classID)-1
        if classID(i) == "S" && classID(i+1) == "L"
            classID(i) = "1";  % Short-long sequence
        end
        if i ~= length(classID)-2
            if classID(i) == "S" && classID(i+1) == "N" && classID(i+2) == "S" 
                classID(i) = "2"; % Short-normal-short sequence
            end
        end
    end

    % Display classification counts
    for id = unique(classID)
        d = "Found " + length(classID(classID==id)) + " " + id + " rtops";
        disp(d)
    end
end