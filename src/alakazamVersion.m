function info = alakazamVersion()
%ALAKAZAMVERSION  The application's own version and attribution metadata.
%   INFO = alakazamVersion() returns a scalar struct describing this build:
%   its version, who wrote it, where it lives, and how it is licensed. Used
%   by Alakazam.onAbout to fill the About box, and the one place any of it
%   is written down.
%
%   VERSION IS MAINTAINED BY HAND, and deliberately so. The obvious
%   alternative -- shelling out to `git describe` -- works only in a git
%   checkout, and the copy of Alakazam most analysts run is an unzipped
%   release package with no .git directory at all (see
%   .github/workflows/release.yml, which builds that package from
%   `git archive`). A version that silently reads "unknown" in exactly the
%   installation whose version someone is trying to report would defeat the
%   point of showing it. So: bump VERSION here in the same commit that gets
%   tagged, and the two stay together in the package as well as the repo.
%
%   The tag convention is a capital V (V0.4.1), matching every tag this
%   repository has carried and what the release workflow now triggers on.
%
%   See also ALAKAZAM/ONABOUT, ALAKAZAM/ONHELP.
    info = struct( ...
        'Name',       'Alakazam', ...
        'Version',    'V0.4.1', ...
        'Tagline',    'An interactive MATLAB workbench for EEG and event-related potential (ERP) analysis.', ...
        'Author',     'Mark M. Span', ...
        'Email',      'm.m.span@rug.nl', ...
        'Repository', 'https://github.com/markspan/Alakazam', ...
        'Issues',     'https://github.com/markspan/Alakazam/issues', ...
        'Releases',   'https://github.com/markspan/Alakazam/releases', ...
        'License',    'GNU General Public License (GPL)');
end
