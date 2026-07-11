function [EEG, opts] = ReRef(EEG, opts)
%% Rereference the EEG data
%% Check for the EEG dataset input:
if (nargin < 1)
    ME = MException('Alakazam:ReRef','Problem in ReRef: No Data Supplied');
    throw(ME);
end

if (nargin < 2)
    opts = 'Init';
end

if (ischar(opts) || isstring(opts)) && strcmpi(opts, 'Init')
    % Interactive: EEGLAB's own dialog picks the reference; the second
    % return value is the command history needed to replay this exact
    % choice later (see SelectData.m for the same pattern). Returned as-is
    % (a plain command string, not yet wrapped in a struct) --
    % Alakazam.onTransformation wraps it in struct('Param', ...) itself
    % before persisting it, the same as every other pop_*-wrapping
    % transformation.
    [EEG, opts] = pop_reref(EEG);
else
    % Re-apply: replay the captured EEGLAB command on this EEG.
    if ~isstruct(opts)
        opts = struct('Param', opts);
    end
    eval(opts.Param);
end
