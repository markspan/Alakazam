function onAbout(this)
%ONABOUT  Ribbon callback ('about'): show version, authorship and licence.
%   A small window beside Help, answering the questions someone asks when
%   they are about to report a problem or cite the tool: which version is
%   this, who wrote it, where does it live, how is it licensed. A singleton
%   like the help viewer -- a second click refocuses the open one rather
%   than stacking up copies.
%
%   WHY THIS IS A uihtml AND NOT A uialert. Not for want of an icon:
%   src/Icons/Alakazam.svg is a real vector and uiimage reads SVG happily,
%   so a native uifigure with a uiimage and a column of uilabels would
%   work. It is a uihtml because the useful part of an About box is the
%   links -- repository, releases, "report a problem" -- and getting those
%   laid out beside their labels, wrapping, and opening in the system
%   browser is a paragraph of HTML against a good deal more uigridlayout
%   and uihyperlink plumbing for the same result.
%
%   (An earlier draft had no choice in the matter: the artwork was a WebP,
%   which MATLAB cannot read at all -- uiimage rejects it with "Valid file
%   formats are one of the following: png, jpg, jpeg, gif, svg" and imread
%   cannot even identify the file on R2025b. Drawing the mark as an SVG
%   removed that constraint; this is now a preference, not a workaround.)
%
%   Version and attribution come from alakazamVersion, not from anything
%   read out of git: the copy most analysts run is an unzipped release
%   package with no repository in it at all.
%
%   See also ALAKAZAMVERSION, ABOUTPAGEHTML, ALAKAZAM/ONHELP.
    if ~isempty(this.AboutFigure) && isvalid(this.AboutFigure)
        figure(this.AboutFigure);
        return;
    end

    info = alakazamVersion();
    html = aboutPageHtml(info, fullfile(this.RootDir, 'Icons', 'Alakazam.svg'));

    this.AboutFigure = uifigure( ...
        'Name', ['About ' info.Name], ...
        ... % Taller than it was: the page now also credits the toolkits
        ... % Alakazam runs on. #wrap scrolls, so this is about how much is
        ... % visible without scrolling rather than what fits at all.
        'Position', centredOn(this.MainFigure, 580, 640), ...
        'Resize', 'off');
    grid = uigridlayout(this.AboutFigure, [1 1], 'Padding', [0 0 0 0]);
    % The page hands every external link back here rather than following it
    % itself: a uihtml embeds a browser with no window to open into, so an
    % ordinary <a> (even target="_blank") does nothing when clicked. See
    % aboutPageHtml's own note on the bridge.
    uihtml(grid, 'HTMLSource', html, ...
        'HTMLEventReceivedFcn', @(~, evt) openExternal(evt));
end

% ======================================================================= %
function openExternal(evt)
%OPENEXTERNAL  Open a link the About page was clicked on, in the real
%   browser. Anything that is not an http(s) address is ignored rather than
%   handed to web(): the page's own links are all fixed strings from
%   alakazamVersion and alakazamDependencies, so there is nothing else this
%   should ever be asked to open.
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
        web(url);                                % no system browser; use MATLAB's
    end
end

% ======================================================================= %
