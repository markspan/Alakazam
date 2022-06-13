function [EEG, options] = TimeShiftPolar(input,opts)
%% Flip the EGC trace if it is upside down....

%% Check for the EEG dataset input:
if (nargin < 1)
    throw(MException('Alakazam:TimeShiftPolar','Problem in TimeShiftPolar: No Data Supplied'));
end

if (nargin == 1)
    options = 'Init';
else
    options = opts;
end

if ~isfield(input, 'IBIevent')
    throw(MException('Alakazam:TimeShiftPolar','Problem in TimeShiftPolar: No Correct Data Supplied'));
else
    if length(input.IBIevent) ~= 2
        throw(MException('Alakazam:TimeShiftPolar','Problem in TimeShiftPolar: Need two IBI streams'));
    end
    IBIS = input.IBIevent;
end

later = sign(IBIS{2}.RTopTime(1) - IBIS{1}.RTopTime(1)); % if -1, first IBI is later, if 1, last IBI is later
if later == -1 
    %% HACK
    later = 2;
    IBIS{2}.RTopTime = IBIS{2}.RTopTime(2:end);
    IBIS{2}.RTopVal = IBIS{2}.RTopVal(2:end);
    IBIS{2}.ibis = IBIS{2}.ibis(2:end);
else
    later = 2;
    %IBIS{2}.RTopTime = IBIS{2}.RTopTime(2:end);
    %IBIS{2}.RTopVal = IBIS{2}.RTopVal(2:end);
    %IBIS{2}.ibis = IBIS{2}.ibis(2:end);
end

%% The later trace has to be shifted
if (abs(IBIS{1}.ibis(1) - IBIS{2}.ibis(1)) < .05)
    shift = IBIS{1}.RTopTime(1) - IBIS{2}.RTopTime(1);
else
    % Yes, what do we do now?
    shift = IBIS{1}.RTopTime(1) - IBIS{2}.RTopTime(1);
end

EEG = input;
shiftinsamples = int32(EEG.srate*abs(shift));
EEG.IBIevent{later} = IBIS{later};
EEG.IBIevent{later}.RTopTime = IBIS{later}.RTopTime + shift;
ch = find(strcmp({input.chanlocs.labels},  IBIS{later}.channelname));
EEG.data(ch,1:end-(shiftinsamples-1)) = EEG.data(ch,shiftinsamples:end);



