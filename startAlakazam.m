function app = startAlakazam()
%STARTALAKAZAM Launch the Alakazam application.
%
%   app = startAlakazam() adds the authored source tree (src/) to the MATLAB
%   path and constructs the Alakazam app. The app itself adds the vendored
%   toolkits (EEGLAB, mlapptools, ...) that live at the repository root.
%
%   Run this from anywhere as long as this file is on the path (for example
%   from the repository root). If you prefer to launch with the bare command
%   'Alakazam', add the src/ folder to your MATLAB path once (pathtool or a
%   startup.m) and call the class directly.
%
%   See PROJECT_STRUCTURE.md for the authored/vendored layout.

    here = fileparts(mfilename('fullpath'));
    addpath(fullfile(here, 'src'));
    app = Alakazam();
end
