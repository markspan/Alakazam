function absPath = fromStoredPath(this, stored)
%FROMSTOREDPATH  Expand a portable stored path back to an absolute one.
%   The inverse of toStoredPath: a leading "~" is replaced by the user's home
%   directory. Anything else (an absolute drive, a network mount) is returned
%   unchanged. The result uses the platform's file separator, so an old
%   workspace that stored plain absolute paths keeps working.
%
%   See also TOSTOREDPATH, USERHOME.
    absPath = char(stored);
    if ~isempty(absPath) && absPath(1) == '~'
        absPath = [this.userHome(), absPath(2:end)];
    end
    absPath = strrep(strrep(absPath, '\', '/'), '/', filesep);
end
