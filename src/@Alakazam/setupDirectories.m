function setupDirectories(this)
%SETUPDIRECTORIES  Put the authored source tree on the path.
%   All paths are resolved absolutely, so the app does not depend on the
%   current working directory. RootDir (src) holds the app code and the
%   +uiextras package (added by putting src on the path); the plot View
%   classes live in src/Views (added explicitly, since src itself is added
%   non-recursively); the Transformations are added with their subfolders.
    close all;
    warning("off", "MATLAB:ui:javacomponent:FunctionToBeRemoved");
    addpath(this.RootDir, '-end');
    % Authored source is grouped into folders under src (added explicitly, since
    % src itself is added non-recursively so the @class / +package folders are
    % not put on the path directly): the plot View classes, the uifigure
    % Dialogs, IO (import/export/format conversion) and Support helpers.
    for sub = {'Views', 'Dialogs', 'IO', 'Support'}
        addpath(fullfile(this.RootDir, sub{1}), '-end');
    end
    addpath(genpath(fullfile(this.RootDir, 'Transformations')));
end
