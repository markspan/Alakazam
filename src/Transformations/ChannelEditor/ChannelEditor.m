function [EEG, options] = ChannelEditor(input, varargin)
%% ChannelEditor  Edit channel labels, types and scalp coordinates.
%
%   An Alakazam-styled channel-location editor (the uifigure counterpart of
%   EEGLAB's pop_chanedit): edit labels/types/coordinates in a table, look up
%   standard 10-5 positions by label, or load a montage file. Only the channel
%   geometry (EEG.chanlocs) is changed; the data is untouched. This is what
%   scalp maps, interpolation, ICA and montage-based references depend on.
%
%   Signature (Alakazam transformation contract):
%     [EEG, options] = ChannelEditor(input)        % interactive dialog
%     [EEG, options] = ChannelEditor(input, opts)  % replay stored chanlocs
[opts, interactive] = TransTools.InitGuard(nargin, 'Alakazam:ChannelEditor', varargin{:});
if ~isfield(input, 'chanlocs') || isempty(input.chanlocs)
    throw(MException('Alakazam:ChannelEditor', ...
        'Problem in ChannelEditor: I''m afraid this dataset has no channel structure to edit.'));
end

if interactive
    elcFile = TransTools.Dipfit1005File('Alakazam:ChannelEditor');
    edited = ChannelEditorDialog(input.chanlocs, elcFile);
    if isempty(edited)
        EEG = [];   % cancelled -- no node, no compute
        options = [];   % the contract is two outputs; both must be assigned
        return;
    end
    options = struct('chanlocs', edited);
    TransformSettings.set('ChannelEditor', options);
else
    options = opts;
end

if ~isfield(options, 'chanlocs') || isempty(options.chanlocs)
    EEG = input;   % nothing to apply
    return;
end

EEG = input;
EEG.chanlocs = applyChanlocs(input.chanlocs, options.chanlocs);
EEG.nbchan   = numel(EEG.chanlocs);
end

% ======================================================================= %
function out = applyChanlocs(current, edited)
%APPLYCHANLOCS  Apply the edited channels. When the counts match (the common
%   case, including replay on the same montage), the edited set replaces the
%   current one directly; otherwise the edited fields are merged into the
%   current channels by label, so a stored edit still applies to a dataset
%   whose channel set differs.
    if numel(edited) == numel(current)
        out = edited;
        return;
    end
    out = current;
    editedLabels = lower(string({edited.labels}));
    for i = 1:numel(out)
        m = find(editedLabels == lower(string(out(i).labels)), 1);
        if isempty(m); continue; end
        for f = ["labels", "type", "X", "Y", "Z", "theta", "radius", ...
                 "sph_theta", "sph_phi", "sph_radius"]
            if isfield(edited, f)
                out(i).(char(f)) = edited(m).(char(f));
            end
        end
    end
end
