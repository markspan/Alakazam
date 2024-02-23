function [EEG, options] = Implicit(input,opts)
    %% Create Epochs from events
    % given event codes create extra labels, and give them a duration.
    % duration can be based on stop code, or given duration.
    
    %#ok<*AGROW>
    
    %% Check for the EEG dataset input:
    if (nargin < 1)
        ME = MException('Alakazam:Implicit','Problem in Implicit: No Data Supplied');
        throw(ME);
    end
    %% Called with options?
    if (nargin == 1)
        options = 'Init';
    else
        options = opts;
    end
    
    %% copy input to output.
    EEG = input;
    id = contains({input.event.type}, "start ");
    nid = contains({input.event.type}, "start SAM");
    id = (id & ~nid);
    events = {input.event};
    events = events{1};
    starts = events(id);
    id2 = contains({input.event.type}, "end ");
    nid = contains({input.event.type}, "end SAM");
    id2 = (id2 & ~nid);
    events = {input.event};
    events = events{1};
    ends = events(id2);
    
    %ids = {starts.type};
    ids = strrep({starts.type}, "start ", "");
    
    for i = 1:length(starts)
        try
            starts(i).type = ids(i);        
            starts(i).duration = ends(i).latency-starts(i).latency; %% in samples!
            starts(i).unit = 'samples';
        catch e
            starts(i) = [];
        end
    end
    %starts(end) =[];
    EEG.event = starts;
end