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
ibis = [IBIS{:}];

POLARCHANNEL = find(strcmp('Unknown1', {ibis.channelname}), 1);
if (POLARCHANNEL == 1); BIPCHANNEL = 2; else; BIPCHANNEL = 1; end

if ~isempty(POLARCHANNEL)
    d = IBIS{1}.RTopTime(1) - IBIS{2}.RTopTime(1);
    firstibichan = sign(d); % if -1, first IBI is later, if 1, last IBI is later
    if abs(d)<.001
        EEG=input;
        return
    end
    if (firstibichan == -1); firstibichan = 1; else; firstibichan = 2; end
    if firstibichan == POLARCHANNEL
        % The first ibi was in the POLARCHANNEL: delete this first IBI.
        IBIS{POLARCHANNEL}.RTopTime = IBIS{POLARCHANNEL}.RTopTime(2:end);
        IBIS{POLARCHANNEL}.RTopVal = IBIS{POLARCHANNEL}.RTopVal(2:end);
        IBIS{POLARCHANNEL}.ibis = IBIS{POLARCHANNEL}.ibis(2:end);
    end
    
    %% The later trace has to be shifted
    shift = IBIS{BIPCHANNEL}.RTopTime(1) - IBIS{POLARCHANNEL}.RTopTime(1);
    disp(['The timeshift is: ' num2str(shift) ' sec'])

    EEG = input;
    shiftinsamples = int32(EEG.srate*abs(shift));
    EEG.IBIevent{POLARCHANNEL} = IBIS{POLARCHANNEL};
    EEG.IBIevent{POLARCHANNEL}.RTopTime = IBIS{POLARCHANNEL}.RTopTime + shift;
    ch = find(strcmp({input.chanlocs.labels},  IBIS{POLARCHANNEL}.channelname));
    EEG.data(ch,1:end-(shiftinsamples-1)) = EEG.data(ch,shiftinsamples:end);
end