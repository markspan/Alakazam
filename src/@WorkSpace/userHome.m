function home = userHome(~)
%USERHOME  Absolute path to the current user's home directory.
%   Uses USERPROFILE on Windows and HOME on Unix / macOS, falling back to the
%   JVM user.home property. Used to store and expand home-relative workspace
%   directories (see toStoredPath / fromStoredPath).
    home = getenv('USERPROFILE');
    if isempty(home)
        home = getenv('HOME');
    end
    if isempty(home)
        home = char(java.lang.System.getProperty('user.home'));
    end
end
