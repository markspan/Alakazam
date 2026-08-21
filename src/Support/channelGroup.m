function groups = channelGroup(chanlocs)
%CHANNELGROUP  Each channel's display group, 'EEG'/'EOG'/'OTHER', as a
%   1 x N cellstr -- the same "brain vs peripheral" concept EEGCHANNELMASK
%   uses, but split three ways (not just EEG/not-EEG) so a caller scaling
%   EOG or other peripheral channels can use a range appropriate to THEIR
%   OWN typical amplitude, not one derived from EEG or from everything at
%   once (an EOG/ECG channel's amplitude usually dwarfs scalp EEG's).
%
%   A channel's own chanlocs.type wins when set (never overridden, same
%   convention GUESSCHANNELTYPES uses); otherwise the type is guessed from
%   its label (CHANNELTYPEFROMLABEL) without requiring GUESSCHANNELTYPES to
%   have been run first (e.g. via the ChannelEditor's "Look up 10-5
%   locations" button) -- a channel plainly labelled "EOG1"/"HEOG" groups
%   as EOG even in a freshly imported, untyped dataset.
%
%   EOG/HEOG/VEOG/IEOG group as 'EOG'; every other known peripheral
%   (ECG/EMG/GSR/RESP/...) groups as 'OTHER'; an explicit or unrecognised
%   'EEG' groups as 'EEG' (the same "unrecognised = scalp" fallback
%   EEGCHANNELMASK and GUESSCHANNELTYPES both use).
%
%   See also EEGCHANNELMASK, CHANNELTYPEFROMLABEL, GUESSCHANNELTYPES.
    n = numel(chanlocs);
    groups = repmat({'EEG'}, 1, n);
    if n == 0
        return;
    end
    eogTypes = ["EOG", "HEOG", "VEOG", "IEOG"];
    hasType = isfield(chanlocs, 'type');
    for i = 1:n
        t = '';
        if hasType
            t = upper(strtrim(char(string(chanlocs(i).type))));
        end
        if isempty(t)
            t = channelTypeFromLabel(chanlocs(i).labels);
        end
        if isempty(t) || strcmp(t, 'EEG')
            groups{i} = 'EEG';
        elseif any(strcmp(t, eogTypes))
            groups{i} = 'EOG';
        else
            groups{i} = 'OTHER';
        end
    end
end
