function tf = isAlakazamVersionNewer(latestTag, currentTag)
%ISALAKAZAMVERSIONNEWER  Is LATESTTAG a newer release than CURRENTTAG?
%   TF = isAlakazamVersionNewer(LATESTTAG, CURRENTTAG) compares two tags in
%   this repository's own 'V<digits>.<digits>...' convention on their
%   numeric components only, most-significant first. Any trailing text
%   (a git-describe suffix like '-7-gabc1234-dirty' on a developer
%   checkout, or a stray 'V0.4.3.6' with more than three components -- this
%   repository has both) is either ignored or compared component-by-component
%   as it appears; nothing here assumes exactly three.
%
%   A tag that does not start with V/v followed by a digit parses as all
%   zeros, so it reads as "not newer" rather than raising -- a malformed
%   response from the update check should read as "couldn't tell", not
%   crash the comparison.
%
%   See also CHECKFORALAKAZAMUPDATE, ALAKAZAMVERSION.

    latest  = versionParts(latestTag);
    current = versionParts(currentTag);

    n = max(numel(latest), numel(current));
    latest(end+1:n)  = 0;
    current(end+1:n) = 0;

    tf = false;
    for k = 1:n
        if latest(k) ~= current(k)
            tf = latest(k) > current(k);
            return;
        end
    end
end

% ======================================================================= %
function parts = versionParts(tag)
%VERSIONPARTS  The dotted numeric components after a leading V/v, or [0].
    numeric = regexp(tag, '^[vV](\d+(\.\d+)*)', 'tokens', 'once');
    if isempty(numeric)
        parts = 0;
        return;
    end
    parts = cellfun(@str2double, strsplit(numeric{1}, '.'));
end
