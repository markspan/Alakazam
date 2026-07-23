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
    addpath(fullfile(this.RootDir, 'Views'), '-end');
    addpath(genpath(fullfile(this.RootDir, 'Transformations')));
end
