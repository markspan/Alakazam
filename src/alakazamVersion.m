function info = alakazamVersion()
%ALAKAZAMVERSION  The application's own version and attribution metadata.
%   INFO = alakazamVersion() returns a scalar struct describing this build:
%   its version, who wrote it, where it lives, and how it is licensed. Used
%   by Alakazam.onAbout to fill the About box, and the one place any of it
%   is written down.
%
%   WHERE THE VERSION COMES FROM. Three sources, most authoritative first,
%   because the two installations Alakazam actually runs in can each answer
%   the question better than a hand-typed constant can:
%
%     1. A VERSION file beside startAlakazam. Written into the package by
%        .github/workflows/release.yml from the tag being published, so an
%        unzipped release states the exact release it is.
%     2. `git describe --tags --dirty` in a checkout. A developer running
%        from the repository sees what they are really running --
%        "V0.4.1-7-gabc1234-dirty" rather than the last number somebody
%        remembered to edit.
%     3. VERSION_FALLBACK below, when neither applies.
%
%   An earlier version of this file kept the constant deliberately and said
%   so, on the grounds that `git describe` reports nothing useful in a
%   release package with no .git directory. That reasoning was right about
%   git and wrong about the conclusion: the fix is for the package to carry
%   its version rather than for the repository to stop knowing its own. The
%   constant is still here, and still worth bumping alongside a tag, but it
%   is now the last resort rather than the only answer.
%
%   INFO.VersionSource names which of the three answered, which is the
%   first thing worth knowing about a version in a bug report.
%
%   The tag convention is a capital V (V0.4.1), matching every tag this
%   repository has carried and what the release workflow triggers on.
%
%   See also ALAKAZAM/ONABOUT, ALAKAZAM/ONHELP.

    % Bumped in the commit that gets tagged. Only reached when neither the
    % packaged VERSION file nor a git checkout is available.
    VERSION_FALLBACK = 'V0.4.3';

    % RESOLVED ON EVERY CALL, not cached. An earlier version held it in a
    % persistent, on the grounds that resolving it shells out to git and
    % nothing that could change the answer happens while the application is
    % running. That second half was simply untrue: tagging a release is
    % exactly the kind of thing done from another window with Alakazam still
    % open, and the About box then went on reporting the version, and the
    % dirty flag, from whenever it was first asked. The only caller is
    % Alakazam.onAbout -- a button somebody presses by hand, rarely -- so
    % the cache was saving one `git describe` on a click and buying a stale
    % answer at the one moment the answer matters.
    [version, source] = resolveVersion(VERSION_FALLBACK);

    info = struct( ...
        'Name',          'Alakazam', ...
        'Version',       version, ...
        'VersionSource', source, ...
        'Tagline',       'An interactive MATLAB workbench for EEG and event-related potential (ERP) analysis.', ...
        'Author',        'Mark M. Span', ...
        'Email',         'm.m.span@rug.nl', ...
        'Repository',    'https://github.com/markspan/Alakazam', ...
        'Issues',        'https://github.com/markspan/Alakazam/issues', ...
        'Releases',      'https://github.com/markspan/Alakazam/releases', ...
        'License',       'GNU General Public License (GPL)');
end

% ======================================================================= %
function [version, source] = resolveVersion(fallback)
%RESOLVEVERSION  The first of the three sources that answers.
    root = fileparts(fileparts(mfilename('fullpath')));

    version = packagedVersion(root);
    if ~isempty(version)
        source = 'release package';
        return;
    end

    version = describedVersion(root);
    if ~isempty(version)
        source = 'git checkout';
        return;
    end

    version = fallback;
    source = 'built in';
end

function version = packagedVersion(root)
%PACKAGEDVERSION  The tag this package was published from, or ''.
%   One line, written by the release workflow. Read defensively: a
%   truncated or hand-edited file should leave the About box working rather
%   than take the application down on startup.
    version = '';
    file = fullfile(root, 'VERSION');
    if exist(file, 'file') ~= 2
        return;
    end
    try
        text = strtrim(fileread(file));
    catch
        return;
    end
    % First line only, and only if it looks like this repository's own tag
    % convention -- so a VERSION file that turns out to hold something else
    % entirely falls through to git rather than being displayed as a version.
    text = strtrim(regexprep(text, '\r?\n.*$', ''));
    if ~isempty(regexp(text, '^[vV]\d', 'once'))
        version = text;
    end
end

function version = describedVersion(root)
%DESCRIBEDVERSION  `git describe` in a checkout, or ''.
%
%   -C rather than a cd: this runs inside a live application, and changing
%   the process's working directory out from under it (even briefly) is not
%   worth the risk of an error leaving it somewhere else.
%
%   --dirty is the point of doing this at all. A developer with uncommitted
%   changes is not running V0.4.1, and the About box saying so is what
%   stops a bug being reported against a version that never contained it.
    version = '';
    if exist(fullfile(root, '.git'), 'dir') ~= 7 && exist(fullfile(root, '.git'), 'file') ~= 2
        return;   % not a checkout (a worktree's .git is a file, not a folder)
    end
    try
        [status, output] = system(sprintf('git -C "%s" describe --tags --dirty', root));
    catch
        return;   % no git on PATH, or system() unavailable
    end
    if status ~= 0
        return;   % no tags reachable, or not a repository after all
    end
    output = strtrim(regexprep(strtrim(output), '\r?\n.*$', ''));
    if ~isempty(regexp(output, '^[vV]\d', 'once'))
        version = output;
    end
end
