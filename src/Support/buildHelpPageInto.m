function [ok, message] = buildHelpPageInto(helpDir, target)
%BUILDHELPPAGEINTO  Run the help builder in HELPDIR and put its page at
%   TARGET. [OK, MESSAGE] where MESSAGE explains a failure, for showing to
%   the analyst.
%
%   A PLAIN FUNCTION SO IT CAN BE TESTED. As a method under @Alakazam this
%   needed a running application to call at all, so the only thing a test
%   could reach was the shell command it happens to build. Here every
%   branch is exercisable: no builder, no node, a build that fails, a
%   builder that writes nothing.
%
%   TRIES THE BUILD BEFORE THE INSTALL, deliberately. node_modules is
%   gitignored but usually present in a working copy, and the build then
%   needs no network at all. Running npm install first would demand one
%   every time, which is the wrong thing to require of somebody who has
%   just opened Help on a machine in a lab.
%
%   NODE IS NOT A DEPENDENCY OF THE APPLICATION and this must not imply it
%   is. Alakazam analyses EEG perfectly well without it; the only thing
%   missing is a rendered copy of the README. Its absence is therefore
%   reported as a plain fact, and the caller keeps its own fallback.
%
%   See also ALAKAZAM.BUILDHELPPAGE, ALAKAZAM.ONHELP.
    ok = false;
    buildScript = fullfile(helpDir, 'build.mjs');

    if exist(buildScript, 'file') ~= 2
        message = sprintf(['The help builder is missing from this copy ' ...
            '(expected %s).'], buildScript);
        return;
    end
    if ~hasNode()
        message = ['Building the help page needs Node.js, which is not on this ' ...
            'machine''s PATH. Node is not needed for anything else in Alakazam.'];
        return;
    end

    [status, output] = runIn(helpDir, 'node build.mjs');
    if status ~= 0
        % Almost always a missing node_modules, which npm install fixes and
        % which is the one step needing the network. Retried rather than
        % reported, since the analyst can act on "Cannot find package
        % 'marked'" no better than this function can.
        [installStatus, installOutput] = runIn(helpDir, 'npm install');
        if installStatus ~= 0
            message = sprintf(['The help page could not be built. Installing its ' ...
                'one dependency failed, which usually means no network ' ...
                'connection:\n\n%s'], firstLines(installOutput, 12));
            return;
        end
        [status, output] = runIn(helpDir, 'node build.mjs');
    end
    if status ~= 0
        message = sprintf('The help page could not be built:\n\n%s', firstLines(output, 12));
        return;
    end

    built = fullfile(helpDir, 'dist', 'AlakazamHelp.html');
    if exist(built, 'file') ~= 2
        message = sprintf(['The builder reported success but wrote no page ' ...
            '(expected %s).'], built);
        return;
    end

    % The copy is the deploy step build.mjs deliberately leaves manual
    % (matching src/webtree). Done here because the whole point is that
    % nobody had to run the build by hand.
    [copied, copyMessage] = copyfile(built, target, 'f');
    if ~copied
        message = sprintf('The page was built but could not be copied to %s: %s', ...
            target, copyMessage);
        return;
    end

    ok = true;
    message = '';
end

% ======================================================================= %
function tf = hasNode()
%HASNODE  Whether node is callable. Asked by running it, not by looking for
%   it on the PATH: a version check is the only answer that accounts for
%   shims, version managers and PATH entries pointing at nothing.
    [status, ~] = system('node --version');
    tf = status == 0;
end

function [status, output] = runIn(folder, command)
%RUNIN  Run COMMAND with FOLDER as the working directory.
%   cd is part of the command rather than a MATLAB cd, so this cannot
%   leave the application in another directory if it throws.
    [status, output] = system(sprintf('cd /d "%s" && %s', folder, command));
end

function text = firstLines(output, n)
%FIRSTLINES  The first N lines of OUTPUT, for a dialog.
%   npm and node are both capable of several hundred lines of stack, and a
%   uialert showing all of it is one the analyst cannot read or dismiss
%   sensibly.
    lines = strsplit(strtrim(char(string(output))), newline);
    if numel(lines) > n
        lines = [lines(1:n), {sprintf('... (%d more lines)', numel(lines) - n)}];
    end
    text = strjoin(lines, newline);
end
