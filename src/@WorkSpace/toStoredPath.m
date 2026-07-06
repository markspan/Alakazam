function stored = toStoredPath(this, absPath)
%TOSTOREDPATH  Write a directory portably: home-relative paths become "~/...".
%   If ABSPATH lies inside the user's home directory, its home part is replaced
%   by "~" so a workspace saved on one machine opens on another (with the same
%   layout under home) regardless of the user name. Paths outside home, such as
%   another drive (G:\...) or a network mount (\\server\share), are stored
%   unchanged so they keep pointing at the same location. Any trailing
%   separator is preserved.
%
%   See also FROMSTOREDPATH, USERHOME.
    stored = char(absPath);
    home = this.userHome();
    if isempty(stored) || isempty(home)
        return;
    end

    % Compare with forward slashes; case-insensitively on Windows.
    normPath = strrep(stored, '\', '/');
    normHome = strrep(home, '\', '/');
    boundary = normHome;
    if ~endsWith(boundary, '/')
        boundary = [boundary '/'];
    end

    if ispc
        under = strcmpi(normPath, normHome) || strncmpi(normPath, boundary, numel(boundary));
    else
        under = strcmp(normPath, normHome) || strncmp(normPath, boundary, numel(boundary));
    end

    if under
        % Keep everything after the home part; the leading '/' (or empty) is
        % preserved, giving "~", "~/sub" or "~/sub/".
        stored = ['~' normPath(numel(normHome) + 1 : end)];
    end
end
