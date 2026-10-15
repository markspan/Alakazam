function [codes, count] = triggerCodes(EEG)
%TRIGGERCODES  Each EEG event's trigger number, NaN where it has none.
%   [CODES, COUNT] = EyeEeg.triggerCodes(EEG) reads the numbers the way
%   EYE-EEG's own import reads them: the first run of digits in the event
%   type, so BrainVision's "S 12" is 12, "201" is 201, and "boundary" has
%   none. COUNT is how many events carry a number.
%
%   Read the same way as EYE-EEG reads them because the two have to agree:
%   what this calls a shared trigger is what the synchronisation will try to
%   match, and a disagreement would show a user a preview of a join that is
%   not the one that runs.
%
%   See also EYEEEG.SHAREDANCHORS, EYETRACKING.
    codes = nan(1, numel(EEG.event));
    for k = 1:numel(EEG.event)
        digits = regexp(char(string(EEG.event(k).type)), '\d+', 'match', 'once');
        if ~isempty(digits)
            codes(k) = str2double(digits);
        end
    end
    count = nnz(~isnan(codes));
end
