function [EEG, opts] = EMGSummary(input, opts)
% EMGSummary: Summarizes EMG data by extracting pre- and post-event values.
% The function allows user input for settings and writes the results to a CSV file.

%% Input Validation
if nargin < 1
    % Check if at least one argument (input data) is provided
    error('Alakazam:EMGSummary', 'Problem in EMGSummary: No Data Supplied');
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
        'Description', 'Set the parameters for EMGSummary',...
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
    catch e %#ok<NASGU>
        % Display a message if an error occurs, which should not happen
        disp("should not occur in EMGSummary");
    end
end

%% Export Results to CSV
% Generate output filename by replacing .xdf with .csv
fname = string(strrep(EEG.filename, '.xdf', '.csv'));

% Retrieve export directory path from caller workspace
ExportsDir = evalin('caller', 'this.Workspace.ExportsDirectory');

% Write the CSV table to the specified directory
writetable(csvtable, fullfile(ExportsDir, fname));
end
