function [ok, message] = buildHelpPage(this)
%BUILDHELPPAGE  Put the manual at src/AlakazamHelp.html, for the Help button.
%   [OK, MESSAGE] = buildHelpPage(THIS). A thin wrapper over
%   buildHelpPageInto, which holds the logic so it can be tested without a
%   running application: the rendered manual (manual/manual.html) is used
%   when it is current, and rendered with Quarto first when it is not.
%
%   The page is not in version control (it embeds every figure of the
%   manual), so a fresh clone has none until this runs; a release ships the
%   rendered manual, so there it is a copy.
%
%   See also BUILDHELPPAGEINTO, ONHELP, OFFERMANUALINSTEAD.
    [ok, message] = buildHelpPageInto(fullfile(this.RepoRoot, 'manual'), ...
        fullfile(this.RootDir, 'AlakazamHelp.html'));
end
