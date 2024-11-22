function [EEG, opts] = EMGEpochSum(input, opts)
% EMGEpochSum: Summarizes EMG data by extracting pre- and post-event values
% and writes results to a CSV file.
% Extended to include max values, mean and max over different intervals
% based on start and end events, and trial number.


%% Input Validation
if nargin < 1
    % Check if at least one argument (input data) is provided
    error('Alakazam:EMGEpochSum', 'Problem in EMGSummary: No Data Supplied');
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
        'Description', 'Set the parameters for EMGEpochSum',...
        'title', 'Rectify options',...
        'separator', 'Parameters:',...
        {'Use:', 'channame'}, cn, ... % Channel name dropdown from available labels
        {'Pre-Time (s):', 'pretime'}, 10, ... % Pre-event time in seconds
        {'Post-Time (s):', 'posttime'}, 10, ... % Post-event time in seconds
        {'StartEvent', 'se'}, '2', ... % Pre-event time in seconds
        {'EndEvent:', 'ee'}, '8'); % Post-event time in seconds
end

% Extract event data from EEG structure
events = input.event;

% Process Each Event
chan = find(strcmp({EEG.chanlocs.labels}, opts.channame));
trialnumber = 1;
csvtable = table();  % Initialize the table

for i = 1:length(events)
    if strcmp(events(i).type, ['E' int2str(opts.se)])  % Start event
        start_latency = events(i).latency;
        % Find the corresponding end event
        for j = i+1:length(events)
            if strcmp(events(j).type, ['E' int2str(opts.ee)])  % End event
                end_latency = events(j).latency; % + (10 * EEG.srate);
                middle_latency = round((start_latency + end_latency) / 2);

                % Compute mean and max values in different intervals
                pre_startindex = max(start_latency - (EEG.srate * opts.pretime), 1);
                pre_endindex = middle_latency;
                post_startindex = middle_latency;
                %post_endindex = min(end_latency + (EEG.srate * opts.posttime), EEG.pnts);
                post_endindex = min(end_latency, EEG.pnts);

                % Pre and Post means and max values
                pre_mean = mean(EEG.data(chan, pre_startindex:pre_endindex)', 'omitnan');
                post_mean = mean(EEG.data(chan, post_startindex:post_endindex)', 'omitnan');
                pre_max = max(EEG.data(chan, pre_startindex:pre_endindex)', [], 'omitnan');
                post_max = max(EEG.data(chan, post_startindex:post_endindex)', [], 'omitnan');
                roundstart = mean(EEG.data(chan, pre_startindex-(opts.pretime*EEG.srate):pre_startindex+(opts.posttime*EEG.srate))', 'omitnan')
                % Create a table row for current event data
                eventnr = i
                line = table(eventnr, trialnumber, pre_mean, post_mean, pre_max, post_max, roundstart);

                % Append to CSV table or initialize if not exists
                if exist('csvtable', 'var')
                    csvtable = [csvtable; line]; %#ok<AGROW>
                else
                    csvtable = line;
                end

                trialnumber = trialnumber + 1;
                break;  % Break out of the inner loop once ee is found
            end
        end
    end
end

% Export Results to CSV
[~,name,~] = fileparts(EEG.filename);

ExportsDir = evalin('caller', 'this.Workspace.ExportsDirectory');
writetable(csvtable, fullfile(ExportsDir, [name, '.EE.csv']));
end
