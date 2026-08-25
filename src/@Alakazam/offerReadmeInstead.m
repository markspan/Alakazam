function offerReadmeInstead(this)
%OFFERREADMEINSTEAD  What Help does when the built page is not there.
%   The in-app help page is generated from readme.MD and is not committed
%   (see .gitignore and Alakazam.onHelp), so a fresh clone has no copy
%   until someone builds one. That is an ordinary state rather than a
%   broken install, and the point of the Help button in the first place is
%   an audience who will not go hunting for documentation, so this offers
%   the README itself rather than just reporting the absence.
%
%   readme.MD is opened in the system's own default handler (web with the
%   -browser flag on a file:// URL), not in a uihtml: raw Markdown rendered
%   as HTML would show every # and * as literal text, which reads worse
%   than the plain file does in whatever the user already uses for it.
    readmeFile = fullfile(this.RepoRoot, 'readme.MD');
    buildHint = sprintf(['The in-app help page has not been built in this copy yet.\n\n' ...
        'To build it (needs Node.js, once):\n' ...
        '    cd "%s"\n    npm install\n    npm run build\n' ...
        '    copy dist\\AlakazamHelp.html ..\\\n\n' ...
        'The same content is in readme.MD in the meantime.'], ...
        fullfile(this.RootDir, 'help'));

    if exist(readmeFile, 'file') ~= 2
        uialert(this.MainFigure, buildHint, 'Help page not built yet', 'Icon', 'info');
        return;
    end

    selection = uiconfirm(this.MainFigure, buildHint, 'Help page not built yet', ...
        'Options', {'Open readme.MD', 'Close'}, ...
        'DefaultOption', 1, 'CancelOption', 2, 'Icon', 'info');
    if strcmp(selection, 'Open readme.MD')
        try
            web(['file:///' strrep(readmeFile, '\', '/')], '-browser');
        catch
            % Some platforms/installs have no external browser wired up;
            % MATLAB's own built-in one always works and still shows the file.
            web(readmeFile);
        end
    end
end
