function offerReadmeInstead(this)
%OFFERREADMEINSTEAD  What Help does when the built page is not there.
%   The in-app help page is generated from README.MD and is not committed
%   (see .gitignore and Alakazam.onHelp), so a fresh clone has no copy
%   until someone builds one. That is an ordinary state rather than a
%   broken install, and the point of the Help button in the first place is
%   an audience who will not go hunting for documentation, so this offers
%   the README itself rather than just reporting the absence.
%
%   README.MD is opened in the system's own default handler (web with the
%   -browser flag on a file:// URL), not in a uihtml: raw Markdown rendered
%   as HTML would show every # and * as literal text, which reads worse
%   than the plain file does in whatever the user already uses for it.
    readmeFile = findReadme(this.RepoRoot);
    buildHint = sprintf(['The in-app help page has not been built in this copy yet.\n\n' ...
        'To build it (needs Node.js, once):\n' ...
        '    cd "%s"\n    npm install\n    npm run build\n' ...
        '    copy dist\\AlakazamHelp.html ..\\\n\n' ...
        'The same content is in README.MD in the meantime.'], ...
        fullfile(this.RootDir, 'help'));

    if isempty(readmeFile)
        uialert(this.MainFigure, buildHint, 'Help page not built yet', 'Icon', 'info');
        return;
    end

    selection = uiconfirm(this.MainFigure, buildHint, 'Help page not built yet', ...
        'Options', {'Open README.MD', 'Close'}, ...
        'DefaultOption', 1, 'CancelOption', 2, 'Icon', 'info');
    if strcmp(selection, 'Open README.MD')
        try
            web(['file:///' strrep(readmeFile, '\', '/')], '-browser');
        catch
            % Some platforms/installs have no external browser wired up;
            % MATLAB's own built-in one always works and still shows the file.
            web(readmeFile);
        end
    end
end

function file = findReadme(repoRoot)
%FINDREADME  The README's actual path, whatever its case, or '' if absent.
%   git records the file as README.MD, and everything in this repository now
%   names it that way. The directory is still listed rather than that
%   spelling assumed, because the two differ on Windows -- core.ignorecase
%   is on, so a working copy can hold readme.MD while the index holds
%   README.MD, and only one of them opens on a case-sensitive filesystem.
%   Listing costs nothing and cannot be wrong.
    file = '';
    entries = dir(fullfile(repoRoot, '*.MD'));
    entries = [entries; dir(fullfile(repoRoot, '*.md'))];
    for k = 1:numel(entries)
        if strcmpi(entries(k).name, 'readme.md')
            file = fullfile(repoRoot, entries(k).name);
            return;
        end
    end
end
