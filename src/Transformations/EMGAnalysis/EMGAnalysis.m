function [EEG, opts] = EMGAnalysis(input, opts)
% EMGAnalysis: Analyzes EMG data, extracts event-based metrics, and generates CSV outputs.
% Generates a CSV file summarizing pre- and post-event data, and a separate file parsing specific event information.

%% Input Validation
if nargin < 1
    % Check if at least one argument (input data) is provided
    error('Alakazam:EMGAnalysis', 'Problem in EMGAnalysis: No Data Supplied');
end

if nargin == 1
    % If only input data is provided, initialize opts
    opts = 'Init';
end

% Assign input to EEG variable for processing
EEG = input;
% Extract channel labels from input
cn = {input.chanlocs.labels};

%% Initialize Options Dialog
if strcmp(opts, 'Init')
    % Create a settings dialog for the user to set parameters
    opts = uiextras.settingsdlg(...
        'Description', 'Set the parameters for EMGAnalysis',...
        'title', 'Rectify options',...
        'separator', 'Parameters:',...
        {'Use:', 'channame'}, cn, ... % Channel name dropdown from available labels
        {'Pre-Time (s):', 'pretime'}, 10, ... % Pre-event time in seconds
        {'Post-Time (s):', 'posttime'}, 10); % Post-event time in seconds
end

% Extract event data from EEG structure
events = input.event;

%% Process Each Event
% Find the index of the channel specified in opts
chan = find(strcmp({EEG.chanlocs.labels}, opts.channame));

% Initialize variable to store the last 'Stimulus' value when evn doesn't start with 'Showing'
lastStimulus = 'None';

% Loop through each event in the data
for i = 1:length(events)
    try
        % Extract filename without extension for ID
        id = string(strrep(EEG.filename, '.xdf', ''));
        % Extract event type as string
        evn = string(events(i).type);

        % Calculate indices for pre- and post-event windows
        startindex = max(events(i).latency - (EEG.srate * opts.pretime), 1);
        endindex = min(events(i).latency + (EEG.srate * opts.posttime), EEG.pnts);

        % Compute mean value in pre- and post-event windows, omitting NaNs
        pre = mean(EEG.data(chan, startindex:events(i).latency)', 'omitnan'); %#ok<UDIM>
        post = mean(EEG.data(chan, events(i).latency:endindex)', 'omitnan'); %#ok<UDIM>

        % Create a table row for current event data
        line = table(id, evn, pre, post);

        % Append to CSV table or initialize if not exists
        if exist('csvtable', 'var')
            csvtable = [csvtable; line]; %#ok<AGROW>
        else
            csvtable = line;
        end

        % Parsing additional information for the separate CSV
        Stimulus = "None";
        Target = "None";
        Duration = "NaN";
        totalduration = "NaN";
        aversionduration = "NaN";

        % Check if evn starts with 'Showing'
        if startsWith(evn, 'Showing')
            % Extract stimulus name after 'Showing' and up to a comma or end of string
            Stimulus = extractAfter(evn, 'Showing ');
            if contains(Stimulus, ',')
                Stimulus = extractBefore(Stimulus, ',');
            end
            % Remember this value for future lines
            lastStimulus = Stimulus;
        else
            % Use the remembered 'Stimulus' if not starting with 'Showing'
            Stimulus = lastStimulus;
        end

        % Check if evn starts with 'Fixation on'
        if startsWith(evn, 'Fixation on')
            % Extract target after 'Fixation on' and the first value for durations
            Target = extractBetween(evn, 'Fixation on ', ' Duration');
            DurationValues = regexp(evn, 'Duration: (\d+\.?\d*)/(\d+\.?\d*) Duration not on avar: (\d+\.?\d*)', 'tokens');
            
            if ~isempty(DurationValues)
                % Convert extracted values to numbers
                Duration = str2double(DurationValues{1}{1});
                totalduration = str2double(DurationValues{1}{2});
                aversionduration = str2double(DurationValues{1}{3});
            end
        end

        % Create a table row for the parsed event data
        
        parsedLine = table(id, Stimulus, Target, Duration, totalduration, aversionduration);

        % Append to parsed CSV table or initialize if not exists
        if exist('parsedCsvTable', 'var')
            parsedCsvTable = [parsedCsvTable; parsedLine]; %#ok<AGROW>
        else
            parsedCsvTable = parsedLine;
        end

    catch e %#ok<NASGU>
        % Display a message if an error occurs, which should not happen
        disp("should not occur in EMGAnalysis");
    end
end

%% Export Results to CSV
% Generate output filenames
basename = strrep(EEG.filename, '.xdf', '');
fname = string([basename, '.csv']);
fix_fname = string([basename, '_fix.csv']);

% Retrieve export directory path from caller workspace
ExportsDir = evalin('caller', 'this.Workspace.ExportsDirectory');

% Write the main CSV table to the specified directory
writetable(csvtable, fullfile(ExportsDir, fname));

% Write the parsed CSV table to the specified directory
writetable(parsedCsvTable, fullfile(ExportsDir, fix_fname));
end
