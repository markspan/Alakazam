function [EEG, options] = PublicSpeaking(input,opts)
    %% Create Epochs from events
    % given event codes create extra labels, and give them a duration.
    % duration can be based on stop code, or given duration.
    
    %#ok<*AGROW>
    
    %% Check for the EEG dataset input:
    if (nargin < 1)
        ME = MException('Alakazam:PublicSpeaking','Problem in PublicSpeaking: No Data Supplied');
        throw(ME);
    end
    %% Called with options?
    if (nargin == 1)
        options = 'Init';
    else
        options = opts;
    end
    
    keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "A", "B", "C", "D", "E", "F"];
    names = ["SAM1", "Instructions","Baseline Standing","Baseline Sitting","Instructions2","Preparation",...
             "SAM2", "Wait for audience", "Presentation", ...
             "SAM3","Rest", ...
             "SAM4","Post Standing", "Post Sitting","DeBrief","End"];
    d = dictionary(keys, names);


    %% copy input to output.
    EEG = input;
    id = contains({input.event.type}, "pressed");
    events = {input.event};
    events = events{1};
    starts = events(id);
    %ids = {starts.type};
    ids = strrep({starts.type}, " pressed", "");
    
    for i = 1:length(starts)-1
        try
            starts(i).type = d(ids(i));        
            starts(i).duration = starts(i+1).latency-starts(i).latency; %% in samples!
            starts(i).unit = 'samples';
        catch e
            starts(i) = [];
        end
    end
    starts(end) =[];
    EEG.event = starts;
end