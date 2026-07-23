function list = ReferenceChoices(labels, preferred)
%REFERENCECHOICES  Channel labels as a dropdown cellstr, with a sensible
%   reference channel put first (TransTools.PutFirst). The previously chosen
%   PREFERRED wins if it is still present; otherwise the first photodiode-like
%   channel (by label) is picked, so the coherence transforms default their
%   reference to the flicker recording when there is one.
    labels = cellfun(@(s) char(string(s)), labels, 'UniformOutput', false);
    pick = '';
    if ~isempty(char(string(preferred))) && any(strcmpi(labels, preferred))
        pick = preferred;
    else
        hit = find(~cellfun(@isempty, regexpi(labels, ...
            'photodiode|diode|photo|^pd$|lum|sensor|erg', 'once')), 1);
        if ~isempty(hit); pick = labels{hit}; end
    end
    if isempty(pick)
        list = labels;
    else
        list = TransTools.PutFirst(labels, pick);
    end
end
