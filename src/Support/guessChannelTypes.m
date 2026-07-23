function chanlocs = guessChannelTypes(chanlocs)
%GUESSCHANNELTYPES  Fill each channel's empty .type by label.
%   A blank type is set to the peripheral type its label implies
%   (channelTypeFromLabel: EOG/ECG/EMG/...), or to 'EEG' when the label is not
%   a known peripheral but the channel has a resolved scalp position. Channels
%   that already carry a type are left untouched, so a manual choice is never
%   overwritten. Used after a location lookup (FillChanlocs, the ChannelEditor
%   'Look up 10-5 locations' button) so eegChannelMask can tell brain channels
%   from peripherals -- an untyped dataset otherwise treats every channel as
%   EEG. See also CHANNELTYPEFROMLABEL, EEGCHANNELMASK.
    if isempty(chanlocs)
        return;
    end
    if ~isfield(chanlocs, 'type')
        [chanlocs.type] = deal('');
    end
    hasX = isfield(chanlocs, 'X');
    for i = 1:numel(chanlocs)
        if ~isempty(strtrim(char(string(chanlocs(i).type))))
            continue;   % keep an existing (possibly manual) type
        end
        t = channelTypeFromLabel(chanlocs(i).labels);
        if isempty(t) && hasX && ~isempty(chanlocs(i).X) && ~isnan(chanlocs(i).X)
            t = 'EEG';   % positioned, not a known peripheral -> scalp EEG
        end
        chanlocs(i).type = t;
    end
end
