function mask = eegChannelMask(chanlocs)
%EEGCHANNELMASK  Logical row vector: which channels are scalp EEG (not a known
%   peripheral -- EOG/ECG/EMG/... -- by chanlocs.type).
%
%   Used to base a display's amplitude / colour scale on the brain channels
%   only, so a large-amplitude EOG or ECG channel (whose range is usually much
%   bigger than the EEG) does not squash the EEG into a faint band.
%
%   A channel counts as EEG when its type is empty/absent or 'EEG' -- so an
%   untyped dataset (the common case) behaves exactly as before, every channel
%   kept. It is excluded only when explicitly typed as one of the known
%   non-brain channels below. If that would leave nothing (every channel typed
%   non-EEG, or an empty chanlocs), every channel is kept instead, so a scale
%   computed from the mask never collapses to empty.
    n = numel(chanlocs);
    mask = true(1, n);
    if n == 0 || ~isfield(chanlocs, 'type')
        return;
    end
    nonEeg = ["EOG", "HEOG", "VEOG", "IEOG", "ECG", "EKG", "EMG", "GSR", ...
              "EDA", "SCR", "RESP", "RESPIRATION", "PLETH", "TEMP", "TRIG", ...
              "TRIGGER", "STIM", "STATUS", "MISC", "REF", "AUDIO", "PHOTO", ...
              "PHOTODIODE", "DIODE", "BIP", "BIPOLAR"];
    for i = 1:n
        t = upper(strtrim(char(string(chanlocs(i).type))));
        if ~isempty(t) && any(strcmp(t, nonEeg))
            mask(i) = false;
        end
    end
    if ~any(mask)
        mask = true(1, n); % never leave nothing to scale on
    end
end
