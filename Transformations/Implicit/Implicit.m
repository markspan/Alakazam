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
    
    % missing start gender/bigfive
    if contains(input.event(1).type, "end bigfive")
        ns = struct(type = {'start bigfive'}, latency=10, duration=1);
        input.event = [ns input.event];
    else
        if contains({input.event.type}, "start bigfive") & ~contains({input.event.type}, "end bigfive")
            sbf = contains({input.event.type}, "start bigfive");
            ns = struct(type = {'end bigfive'}, latency = input.event(sbf).latency+2000, duration=1);
            input.event = [ns input.event];
        end
    end
    idgender =  contains(cellstr({input.event.type}), "stop gender");
    input.event(idgender).type = "end gender";
    idgender = contains(cellstr({input.event.type}), "end gender");
    idg = find(idgender);
    if ~isempty(idg)
        if isempty(input.event(idg-1).type)
            input.event(idg-1).type = 'start gender';
        else
            ns = struct(type = {'start gender'}, latency=input.event(idg-1).latency+10, duration=1);
            input.event(idg).type = "end gender";
            % Shift elements to the right of the insertion point
            input.event = [input.event(1:idg-1), ns, input.event(idg:end)];
           
        end
        input.event(idg).type = 'end gender';
    else
        idgender = contains({input.event.type}, "start gender");
        idg = find(idgender);
        if ~isempty(idg)
            input.event(idg+1).type = 'end gender';
        else
            input.event(idg).type = '';
        end
    end

    id = contains(cellstr({input.event.type}), "start ");
    nid = contains(cellstr({input.event.type}), "start SAM");
    nid2 = contains(cellstr({input.event.type}), "start IAT");
    nid3 = contains(cellstr({input.event.type}), "start TASKS");
    id = (id & ~nid & ~nid2 & ~ nid3);
    events = {input.event};
    events = events{1};
    starts = events(id);
    id2 = contains(cellstr({input.event.type}), "end ");
    nid = contains(cellstr({input.event.type}), "end SAM");
    nid2 = contains(cellstr({input.event.type}), "end IAT");
    nid3 = contains(cellstr({input.event.type}), "end TASKS");
    id2 = (id2 & ~nid & ~nid2 & ~nid3);
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