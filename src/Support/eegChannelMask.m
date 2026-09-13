function mask = eegChannelMask(chanlocs)
%EEGCHANNELMASK  Logical row vector: which channels are scalp EEG (not a known
%   peripheral -- EOG/ECG/EMG/...).
%
%   Used to base a display's amplitude / colour scale on the brain channels
%   only, so a large-amplitude EOG or ECG channel (whose range is usually much
%   bigger than the EEG) does not squash the EEG into a faint band; and to
%   keep peripherals out of anything that is about brain channels, such as
%   ArtefactDetect's 'Scalp EEG only' scope or an ICA decomposition.
%
%   A channel's type is taken from .type when that is set, and GUESSED FROM
%   ITS LABEL otherwise (CHANNELTYPEFROMLABEL). The label is the point: a
%   channel called HEOG-left is an eye channel whether or not anyone filled
%   in a type field, and most recordings arrive with .type blank. This used
%   to key off .type alone and treat blank as EEG, which meant every
%   consumer silently degraded on an untyped dataset -- 'Scalp EEG only'
%   tested the eye channels anyway, and a display scaled off them. Callers
%   that want the guess PERSISTED into the dataset still run
%   GUESSCHANNELTYPES; this function only needs it for the decision at hand.
%
%   A channel counts as EEG when neither its type nor its label marks it as
%   one of the known non-brain kinds, so an unrecognised label (and every
%   standard 10-5 scalp label) is kept. If the mask would come out empty
%   (every channel a peripheral, or an empty chanlocs), every channel is
%   kept instead, so a scale or a channel selection computed from it never
%   collapses to nothing.
%
%   See also CHANNELTYPEFROMLABEL, GUESSCHANNELTYPES, CHANNELGROUP.
    n = numel(chanlocs);
    mask = true(1, n);
    if n == 0
        return;
    end
    nonEeg = ["EOG", "HEOG", "VEOG", "IEOG", "ECG", "EKG", "EMG", "GSR", ...
              "EDA", "SCR", "RESP", "RESPIRATION", "PLETH", "TEMP", "TRIG", ...
              "TRIGGER", "STIM", "STATUS", "MISC", "REF", "AUDIO", "PHOTO", ...
              "PHOTODIODE", "DIODE", "BIP", "BIPOLAR"];
    hasType = isfield(chanlocs, 'type');
    hasLabel = isfield(chanlocs, 'labels');
    for i = 1:n
        t = '';
        if hasType
            t = upper(strtrim(char(string(chanlocs(i).type))));
        end
        if isempty(t) && hasLabel
            % No recorded type: read it off the label instead.
            t = upper(channelTypeFromLabel(chanlocs(i).labels));
        end
        if ~isempty(t) && any(strcmp(t, nonEeg))
            mask(i) = false;
        end
    end
    if ~any(mask)
        mask = true(1, n); % never leave nothing to scale on
    end
end
