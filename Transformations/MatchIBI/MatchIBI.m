function [EEG, options] = MatchIBI(input, ~)
%% function to match two IBI timeseries, NaN'ning suspect ibis
options = 'None';
%% Check for the EEG dataset input:
if (nargin < 1)
    ME = MException('Alakazam:MatchIBI','Problem in MatchIBI: No Data Supplied');
    throw(ME);
end
if ~isfield(input, 'IBIevent')
    ME = MException('Alakazam:MatchIBI','Problem in MatchIBI: No IBIS availeable (yet)');
    throw(ME);
end

NDevices  = length(input.IBIevent);
if NDevices < 2
    ME = MException('Alakazam:MatchIBI','Problem in MatchIBI: Need (at least) two IBI series to match');
    throw(ME);
end

srate = input.srate;
events = input.event;
% define events that are valid: not the empatica ones.
validevents = events(isnan(str2double(string({events.type}))));

IBI(1) = input.IBIevent{1};
IBI(2) = input.IBIevent{2};

% select only IBIS that occur between the first and last event
% and that are valid: not the empatica ones.
for c = 1:2
    IBI(c).ibis     = IBI(c).ibis(IBI(c).RTopTime > validevents(1).latency/srate & IBI(c).RTopTime < validevents(end).latency/srate);
    IBI(c).RTopTime = IBI(c).RTopTime(IBI(c).RTopTime > validevents(1).latency/srate & IBI(c).RTopTime < validevents(end).latency/srate);
    IBI(c).RTopVal  = IBI(c).RTopVal(IBI(c).RTopTime > validevents(1).latency/srate & IBI(c).RTopTime < validevents(end).latency/srate);
end

first = true;
while length(IBI(1).ibis) ~= length(IBI(2).ibis) || first 
    first = false;
    sl = min(length(IBI(1).ibis), length(IBI(2).ibis));
    dif = IBI(1).RTopTime(1:sl)-IBI(2).RTopTime(1:sl);

    % 1) find out which channel is weird: 1 or two:
    idx = find(abs(dif)>.2, 1 ); %%idx is the index of the first inequality
    for c = 1:2
        z(c) = (IBI(c).ibis(idx)-mean(IBI(c).ibis))/ std(IBI(c).ibis); %#ok<AGROW> 
    end
    [~,wc] = max(abs(z)); %% wc = weird
    if abs(z(wc)) < 1.4
        break;
    end
    disp(['Weirdness: ' num2str(z)]);

    % 2) additional of missing??
    if (z(wc) < 0 ) %% additional
    %if  IBI(wc).ibis(idx) < .38
        % 3) if additional: delete from weird channel 
        disp(['Removing IBI at timepoint:' num2str(IBI(wc).RTopTime(idx)) ' from channel: ' IBI(wc).channelname]);
        IBI(wc).ibis(idx) = [];        
        IBI(wc).RTopTime(idx) = [];
        IBI(wc).RTopVal(idx)  = [];
    else %% missing
        nwc = 3-wc;
        % 4) if missing: take the value from the correct channel
        disp(['Adding IBI at timepoint: ' num2str(IBI(nwc).RTopTime(idx)) ' to channel: ' IBI(wc).channelname]);
        IBI(wc).RTopTime = [IBI(wc).RTopTime(1:idx-1) IBI(nwc).RTopTime(idx) IBI(wc).RTopTime(idx-1:end)];
        IBI(wc).RTopVal  = [IBI(wc).RTopVal(1:idx-1) IBI(nwc).RTopVal(idx) IBI(wc).RTopVal(idx-1:end)];
        IBI(wc).ibis  = [IBI(wc).ibis(1:idx-1) IBI(nwc).ibis(idx) IBI(wc).ibis(idx-1:end)];
    end
    IBI(wc).ibis = round([diff(IBI(wc).RTopTime) IBI(3-wc).ibis(end)],3);
    tooshort = IBI(wc).ibis < .35;
    IBI(wc).ibis(tooshort) = [];
    IBI(wc).RTopTime(tooshort) = [];
    IBI(wc).RTopVal(tooshort) = [];
    IBI(wc).ibis = round([diff(IBI(wc).RTopTime) IBI(3-wc).ibis(end)],3);
    disp([int2str(length(IBI(1).ibis)) ' - ' int2str(length(IBI(2).ibis)) ]);
end

EEG=input;
EEG.IBIevent{1} = IBI(1);
EEG.IBIevent{2} = IBI(2);