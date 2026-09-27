function onHelp(this)
%ONHELP  Ribbon callback ('help'): show the in-app help page
%   (src/AlakazamHelp.html, the manual in manual/, prepared by
%   buildHelpPage). A
%   singleton window, like the app's own MainFigure: a second click just
%   refocuses the one already open rather than stacking up copies, since
%   this is a read-only reference the user dips in and out of alongside
%   their actual work, not a per-dataset window.
%
%   Loaded lazily, on first use, not at Alakazam startup: the page embeds
%   every figure of the manual (about 10 MB), which would otherwise be dead
%   weight in memory on every launch whether or not Help is ever opened.
%
%   The page is NOT in version control (see .gitignore). A fresh clone
%   therefore has none until it is prepared, so its absence is a normal
%   state to be explained, not an install fault: offerManualInstead offers
%   to prepare it (buildHelpPage), and the PDF manual or the README if that
%   cannot be done. When the rendered manual is newer than the page, the
%   page is prepared again first, which is a copy.
    if ~isempty(this.HelpFigure) && isvalid(this.HelpFigure)
        figure(this.HelpFigure);
        return;
    end

    htmlFile = fullfile(this.RootDir, "AlakazamHelp.html");
    if exist(htmlFile, "file") ~= 2
        this.offerManualInstead();
        return;
    end
    rendered = fullfile(this.RepoRoot, "manual", "manual.html");
    if exist(rendered, "file") == 2 && dir(rendered).datenum > dir(htmlFile).datenum
        this.buildHelpPage();   % a newer manual: refresh the page from it
    end

    this.HelpFigure = uifigure("Name", "Alakazam Help", "Position", fitOnScreen([160 120 1000 700]));
    grid = uigridlayout(this.HelpFigure, [1 1], "Padding", [0 0 0 0]);
    % Every link in the page is handed back here rather than followed in
    % place: a uihtml embeds a browser with no window to open into, so an
    % ordinary <a> does nothing when clicked. buildHelpPageInto injects the
    % bridge that sends them here.
    uihtml(grid, "HTMLSource", htmlFile, ...
        "HTMLEventReceivedFcn", @(~, evt) openExternal(evt));
end

% ======================================================================= %
function openExternal(evt)
%OPENEXTERNAL  Open a link the help page was clicked on, in the real
%   browser. Only http(s): the manual's outside links are DOIs and web
%   addresses, and anything else would resolve against MATLAB's own server
%   and fail anyway.
    if ~strcmp(evt.HTMLEventName, 'openUrl')
        return;
    end
    url = char(string(evt.HTMLEventData));
    if isempty(regexp(url, '^https?://', 'once'))
        return;
    end
    try
        web(url, '-browser');
    catch
        web(url);
    end
end
