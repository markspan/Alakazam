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
    %% copy input to output.
    EEG = input;
    id = contains({input.event.type}, "pressed");
    events = {input.event};
    events = events{1};
    starts = events(id);
    for i = 1:length(starts)-1
        starts(i).duration = starts(i+1).latency-starts(i).latency; %% in samples!
        starts(i).unit = 'samples';
    end
    EEG.event = starts;
end