function [ok, message] = buildHelpPage(this)
%BUILDHELPPAGE  Generate src/AlakazamHelp.html from README.MD, in place.
%   [OK, MESSAGE] = buildHelpPage(THIS). A thin wrapper over
%   buildHelpPageInto, which holds the logic so it can be tested without a
%   running application.
%
%   WHY THE APP BUILDS IT AT ALL. The page is not in version control (about
%   5 MB of embedded screenshots regenerated from README.MD, see
%   .gitignore), so a fresh clone has no copy. Until now the Help button
%   could only explain how to build one, which asks an analyst to leave the
%   application, find a terminal and run three npm commands in order to
%   read the documentation.
%
%   See also BUILDHELPPAGEINTO, ONHELP, OFFERREADMEINSTEAD.
    [ok, message] = buildHelpPageInto(fullfile(this.RootDir, 'help'), ...
        fullfile(this.RootDir, 'AlakazamHelp.html'));
end
