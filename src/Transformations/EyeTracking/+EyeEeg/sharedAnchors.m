function [startCode, endCode, shared] = sharedAnchors(codes, et)
%SHAREDANCHORS  The triggers both recordings have, and the two to anchor on.
%   [STARTCODE, ENDCODE, SHARED] = EyeEeg.sharedAnchors(CODES, ET) takes the
%   EEG's trigger numbers in event order (EyeEeg.triggerCodes) and a parsed
%   eye track, and returns the code of the FIRST EEG trigger the eye track
%   also has, the code of the LAST one, and the distinct codes they share.
%   All three are empty when nothing is shared.
%
%   First and last because that is how EYE-EEG uses its anchors: the first
%   event of the start code and the last event of the end code. Picking them
%   per recording like this is what lets one set of options replay onto
%   every subject, whatever each session's first and last triggers were.
%
%   See also EYEEEG.TRIGGERCODES, EYETRACKING.
    startCode = [];
    endCode = [];
    etCodes = [];
    if isstruct(et) && isfield(et, 'event') && ~isempty(et.event)
        etCodes = unique(et.event(:, 2))';
    end
    inBoth = find(ismember(codes, etCodes));
    shared = unique(codes(inBoth));
    if isempty(inBoth)
        return;
    end
    startCode = codes(inBoth(1));
    endCode = codes(inBoth(end));
end
