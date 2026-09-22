function hz = FrequencyFromLabel(label)
%FREQUENCYFROMLABEL  The stimulation frequency a bin's label names, in Hz.
%   HZ = TransTools.FrequencyFromLabel(LABEL) reads the first number followed
%   by "Hz" in LABEL ("RIFT 64Hz" -> 64, "SSVEP 7.5 Hz left" -> 7.5), or NaN
%   when there is none. A cell array or string array gives one value each.
%
%   Used where Alakazam has to know which frequency a condition flickered at
%   and nothing else records it: to propose RESS's rows, and to tell which
%   conditions can serve as a null for a RESS filter (see RESS). A label is
%   what the analyst named the bin, so the frequency is only as right as the
%   name; callers treat NaN as "unknown", never as "none".
%
%   See also RESS.
    if iscell(label) || (isstring(label) && ~isscalar(label))
        hz = cellfun(@TransTools.FrequencyFromLabel, cellstr(label));
        return;
    end
    token = regexp(char(string(label)), '(\d+(?:\.\d+)?)\s*[Hh][Zz]', 'tokens', 'once');
    if isempty(token)
        hz = NaN;
    else
        hz = str2double(token{1});
    end
end
