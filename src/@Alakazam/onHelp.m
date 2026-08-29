function onHelp(this)
%ONHELP  Ribbon callback ('help'): show the in-app help page
%   (src/AlakazamHelp.html, built from the repository's own README.MD --
%   see src/help/README.md to rebuild it after editing the README). A
%   singleton window, like the app's own MainFigure: a second click just
%   refocuses the one already open rather than stacking up copies, since
%   this is a read-only reference the analyst dips in and out of alongside
%   their actual work, not a per-dataset window.
%
%   Built lazily, on first use, not at Alakazam startup: the page embeds
%   every screenshot the README references as a base64 data URI (a few MB
%   once assembled -- see src/help/build.mjs), which would otherwise be
%   dead weight loaded into memory on every single launch whether or not
%   the analyst ever opens Help.
%
%   The built page is NOT in version control (see .gitignore): it is ~5 MB
%   of embedded screenshots regenerated from README.MD, which would put a
%   5 MB diff in history on every README edit. A fresh clone therefore does
%   not have it until someone runs the build, so its absence is a normal
%   state to be explained, not an install fault to warn about -- and the
%   fallback below offers the README itself, which is the same content.
    if ~isempty(this.HelpFigure) && isvalid(this.HelpFigure)
        figure(this.HelpFigure);
        return;
    end

    htmlFile = fullfile(this.RootDir, "AlakazamHelp.html");
    if exist(htmlFile, "file") ~= 2
        this.offerReadmeInstead();
        return;
    end

    this.HelpFigure = uifigure("Name", "Alakazam Help", "Position", [160 120 1000 700]);
    grid = uigridlayout(this.HelpFigure, [1 1], "Padding", [0 0 0 0]);
    uihtml(grid, "HTMLSource", htmlFile);
end
