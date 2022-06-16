function [EEG, options] = SelectData(input,opts)
%% Example Transformation simply calling EEGLAB function
% Transformations should return the transformed data in the EEG structure, 
% and an options variable ("options") it can understand. In this case, as
% we use the EEGLAB function, the commandline history is returned.
% Input must (in principle) contain a data structure (EEG), and optionally 
% the options variable obtained from a previous call. If this second
% variable is availeable, no user interaction takes place, but the
% Transformation is performed based op the given options. This second form
% occurs when the transformation is dragged in th tree upto another
% dataset. Simplest form.

%% Check for the EEG dataset input:
if (nargin < 1)
    ME = MException('Alakazam:SelectData','Problem in SelectData: No Data Supplied');
    throw(ME);
end

%% Was this a call from the menu? 
if (nargin == 1)
    options = 'Init';
else
    options = opts;
end

EEG = input;
%% if it was, call the interactive version of the Transformation
% in this case the pop_select version.
if (ischar(options))
    if (strcmpi(options, 'Init'))
        [EEG, options] = pop_select(input);
        if isfield(EEG, 'Polarchannels')
            ix1 = strfind(options, '[');
            ix2 = strfind(options, ']');
            if contains(options, 'time')
                EEG.Polarchannels = pop_select(EEG.Polarchannels, 'time', eval(options(ix1:ix2)));
            end
            if contains(options, 'channel')
                disp("No effect on polarchannels")
            end

        end
        % in EEGLAB, the second return value is the function call to recreate the
        % transformation.
    end
else

    eval(options.Param)
    if ~isstruct(options)
        nOptions.Param = options;
        options = nOptions;
    end
    if isfield(EEG, 'Polarchannels')
        ix1 = strfind(options.Param, '[');
        ix2 = strfind(options.Param, ']');
            if contains(options.Param, 'time')
                EEG.Polarchannels = pop_select(EEG.Polarchannels, 'time', eval(options.Param(ix1:ix2)));
            end
            if contains(options.Param, 'channel')
                disp("No effect on polarchannels")
            end
    end

    % so, when we evaluate this return value, it will recreate the
    % transformation on the "EEG" structure.
end

