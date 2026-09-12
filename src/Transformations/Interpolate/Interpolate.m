function [EEG, options] = Interpolate(input, varargin)
%% Interpolate  Reconstruct bad channels from their neighbours.
%
%   Wraps EEGLAB's pop_interp (spherical-spline and related methods), driven by
%   an Alakazam channel-picker dialog. The chosen channels are rebuilt from the
%   surrounding good channels; the channel count is unchanged. Bad channels are
%   stored as labels and resolved to indices against the current dataset, so a
%   stored choice replays on another subject with the same montage.
%
%   Signature (Alakazam transformation contract):
%     [EEG, options] = Interpolate(input)        % interactive dialog
%     [EEG, options] = Interpolate(input, opts)  % replay a stored options struct
[opts, interactive] = TransTools.InitGuard(nargin, 'Alakazam:Interpolate', varargin{:});
if ~isfield(input, 'chanlocs') || isempty(input.chanlocs)
    throw(MException('Alakazam:Interpolate', ...
        'Problem in Interpolate: I''m afraid this dataset has no channel locations.'));
end
if ~anyHasPosition(input.chanlocs)
    throw(MException('Alakazam:Interpolate', ...
        ['Problem in Interpolate: the channels have no scalp positions, so there is ' ...
         'nothing to interpolate from. Would you run the Channel Editor first to look up ' ...
         'standard 10-5 positions by label?']));
end

if interactive
    options = InterpolateDialog(input.chanlocs, TransformSettings.get('Interpolate'));
    if isempty(options)
        EEG = [];   % cancelled -- no node, no compute
        return;
    end
    TransformSettings.set('Interpolate', options);
else
    options = opts;
end

badIdx = TransTools.LabelsToIdx(input, options.channels);
if isempty(badIdx)
    EEG = input;   % none of the stored channels are in this dataset -> no-op
    return;
end
method = 'spherical';
if isfield(options, 'method') && ~isempty(options.method)
    method = char(options.method);
end

EEG = pop_interp(input, badIdx, method);
% pop_interp rebuilds the struct through eeg_checkset, which does not carry
% Alakazam's own two fields across, so restore them. TransTools.FieldOr, not
% a bare input.DataType: interpolating does not change what kind of data this
% is, so a dataset that never had the fields set (one handed straight to the
% transform outside the app, say) should come back unchanged rather than error.
EEG.DataType   = TransTools.FieldOr(input, 'DataType', 'TIMEDOMAIN');
EEG.DataFormat = TransTools.FieldOr(input, 'DataFormat', shapeFormat(input));
end

% ======================================================================= %
function fmt = shapeFormat(input)
%SHAPEFORMAT  The DataFormat the data shape implies, for a dataset that
%   arrived without the field set. Same fallback SelectData uses.
    if size(input.data, 3) > 1
        fmt = 'EPOCHED';
    else
        fmt = 'CONTINUOUS';
    end
end

% ======================================================================= %
function tf = anyHasPosition(chanlocs)
    tf = false;
    for i = 1:numel(chanlocs)
        if isfield(chanlocs, 'X') && ~isempty(chanlocs(i).X) && ~any(isnan(chanlocs(i).X))
            tf = true; return;
        end
        if isfield(chanlocs, 'theta') && ~isempty(chanlocs(i).theta) && ~any(isnan(chanlocs(i).theta))
            tf = true; return;
        end
    end
end
