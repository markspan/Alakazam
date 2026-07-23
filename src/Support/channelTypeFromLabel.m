function t = channelTypeFromLabel(label)
%CHANNELTYPEFROMLABEL  Guess a peripheral channel type from its label.
%   Returns one of the non-brain types eegChannelMask keys off ('EOG', 'ECG',
%   'EMG', 'GSR', 'RESP', 'TEMP', 'TRIG', 'MISC'), or '' when the label does
%   not look like a known peripheral (i.e. it is a scalp EEG channel or is
%   unrecognised). Matching is by substring on the upper-cased, separator-
%   stripped label, using only tokens that never occur inside a standard 10-5
%   scalp label (so 'HEOG'/'VEOG'/'EOGL' -> EOG, but 'TP7'/'POz'/'Oz' stay
%   empty). See also EEGCHANNELMASK, GUESSCHANNELTYPES.
    t = '';
    s = upper(strtrim(char(string(label))));
    if isempty(s)
        return;
    end
    s = regexprep(s, '[^A-Z0-9]', '');   % strip spaces/hyphens/brackets

    % type -> substrings that unambiguously mark it (never inside a 10-5 label)
    rules = { ...
        'EOG',  {'EOG', 'HEO', 'VEO'}; ...
        'ECG',  {'ECG', 'EKG'}; ...
        'EMG',  {'EMG'}; ...
        'GSR',  {'GSR', 'EDA', 'SCR', 'SCL'}; ...
        'RESP', {'RESP', 'PLETH'}; ...
        'TEMP', {'TEMP'}; ...
        'TRIG', {'TRIG', 'STIM', 'STATUS', 'MARKER'}; ...
        'MISC', {'AUDIO', 'PHOTO', 'DIODE', 'BIPOLAR'} };

    for i = 1:size(rules, 1)
        toks = rules{i, 2};
        if any(cellfun(@(tok) contains(s, tok), toks))
            t = rules{i, 1};
            return;
        end
    end
end
