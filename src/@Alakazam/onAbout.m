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
        'Position', centredOn(this.MainFigure, 560, 460), ...
        'Resize', 'off');
    grid = uigridlayout(this.AboutFigure, [1 1], 'Padding', [0 0 0 0]);
    uihtml(grid, 'HTMLSource', html);
end

% ======================================================================= %
function pos = centredOn(parent, width, height)
%CENTREDON  A WIDTH x HEIGHT position centred over PARENT, falling back to
%   the screen centre when the parent is unavailable. The app is normally
%   up by the time About can be clicked, but nothing here needs to depend
%   on that.
    try
        p = parent.Position;
        pos = [p(1) + (p(3) - width) / 2, p(2) + (p(4) - height) / 2, width, height];
    catch
        screen = get(groot, 'ScreenSize');
        pos = [(screen(3) - width) / 2, (screen(4) - height) / 2, width, height];
    end
end
