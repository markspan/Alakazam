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
        % in EEGLAB, the second return value is the function call to recreate the
        % transformation.
    end
else
    % Normalize before eval, not after: options is always a struct by the
    % time Alakazam.onTransformation stores it (it wraps a bare value in
    % struct('Param', value) itself), but this function may be called
    % directly with a bare (non-struct) captured value too, in which case
    % options.Param would not exist yet if eval ran first.
    if ~isstruct(options)
        nOptions.Param = options;
        options = nOptions;
    end
    eval(options.Param)
    % EEGLAB's own EEG.times is sometimes left in seconds rather than ms
    % after pop_select; this ratio check (empirically, real recordings are
    % well under 500x xmax/times(end) when both are already in the same
    % unit) detects and corrects that rather than assuming a fixed unit.
    if (EEG.xmax / EEG.times(end) > 500)
        EEG.times = EEG.times*1000;
    end

    % so, when we evaluate this return value, it will recreate the
    % transformation on the "EEG" structure.
end

