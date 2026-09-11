function app = startAlakazam(workspaceFile)
%STARTALAKAZAM Launch the Alakazam application.
%
%   app = startAlakazam() adds the authored source tree (src/) to the MATLAB
%   path and constructs the Alakazam app, opened with the repository's
%   default workspace (DefaultWorkSpace.wksp). The app itself adds the
%   vendored toolkits (EEGLAB, mlapptools, ...) that live at the repository
%   root.
%
%   app = startAlakazam(workspaceFile) opens with WORKSPACEFILE instead of
%   the repository default -- a bare name (no path separator, e.g.
%   "MyProject.wksp") resolves next to DefaultWorkSpace.wksp, under the
%   repository root; a relative or absolute path is used as given. Useful
%   for always launching straight into a particular project's workspace
%   without going through "Open WorkSpace"'s file picker every time.
%
%   Run this from anywhere as long as this file is on the path (for example
%   from the repository root). If you prefer to launch with the bare command
%   'Alakazam', add the src/ folder to your MATLAB path once (pathtool or a
%   startup.m) and call the class directly...
%
%   IF AN UPDATE WAS DOWNLOADED (the Update button in Alakazam's About
%   group) but not yet applied, this swaps it in first -- see
%   applyPendingAlakazamUpdate for why that has to happen here, before src/
%   is even on the path, rather than from inside the running app that
%   downloaded it. An analyst who used Update sees nothing different: they
%   quit Alakazam and run startAlakazam again the way they always would, and
%   the new version is just what starts.
%
%   See PROJECT_STRUCTURE.md for the authored/vendored layout.

    here = fileparts(mfilename('fullpath'));
    applyPendingAlakazamUpdate(here);
    addpath(fullfile(here, 'src'));
    if nargin >= 1
        app = Alakazam(workspaceFile);
    else
        app = Alakazam();
    end
end
