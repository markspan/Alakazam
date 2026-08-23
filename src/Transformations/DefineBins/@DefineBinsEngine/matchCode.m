function tf = matchCode(typStr, codes)
%MATCHCODE  True when TYPSTR matches any entry in CODES (exact, case-
%   insensitive, numeric-equal, or wildcard). CODES is normally a
%   `string` array (the parser's own native shape, one element per
%   alternative -- see anchorNode), but may also arrive as a cell
%   array of char (or a single bare char row vector for a one-code
%   matcher) after a round trip through jsonencode/jsondecode -- e.g. a
%   template saved by Alakazam.onSaveTemplate and replayed later via
%   Apply Template/applyStepToTarget, which never touches the parser at
%   all, only jsondecode. Left unnormalised, a bare char row vector
%   (jsondecode's shape for what was originally a scalar string, e.g.
%   "201") is numel==3, not 1: the loop below would iterate over its
%   individual CHARACTERS ('2','0','1') as if they were three separate
%   one-character codes, so a single-code matcher could never actually
%   match anything post-round-trip -- every next(code)/prev(code)
%   relation using it would then scan the entire event list on every
%   call (see evalRel's unbounded search loops) instead of usually
%   breaking after one or two events, which is what actually explains an
%   applied template appearing to hang.
    if ischar(codes)
        codes = {codes};
    end
    for i = 1:numel(codes)
        if iscell(codes)
            c = codes{i};
        else
            c = codes(i);
        end
        if contains(c, '?') || contains(c, '*')
            % Wildcard marker: ? = any one character, * = any run.
            if ~isempty(regexpi(typStr, DefineBinsEngine.wildcardToRegex(c), 'once'))
                tf = true; return;
            end
        else
            if strcmpi(typStr, c); tf = true; return; end
            va = str2double(typStr); vc = str2double(c);
            if ~isnan(va) && ~isnan(vc) && va == vc; tf = true; return; end
        end
    end
    tf = false;
end
