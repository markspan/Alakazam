classdef WorkSpace < handle
% Unit tests for WorkSpace class
% These tests use MATLAB's built-in unittest framework.
% They are lightweight and do not require external files.
    % WorkSpace Class:
    % Alakazam
    % Functions pertaining to directories used.
    
    properties
        Parent
        Name
        RawDirectory
        CacheDirectory
        ExportsDirectory
        Tree              % WorkSpaceTree, the data & analyses browser, hosted in Alakazam.DataTreePanel
        GrandAveragesTree % WorkSpaceTree, flat top-level grand-average nodes, hosted in Alakazam.GrandAveragesTreePanel
        ActiveTree        % WorkSpaceTree, whichever of Tree/GrandAveragesTree was last interacted with -- see CreateTreeComponent
        EEG
    end
    
    methods
        function this = WorkSpace(myParent, varargin)
            this.Parent = myParent;
            this.CreateTreeComponent();

            if nargin == 1 || nargin == 2 || nargin == 4
                if nargin == 1 || nargin == 2
                    if nargin == 2
                        % An explicit default workspace, e.g. from
                        % startAlakazam(name) -- a bare filename (no path
                        % separator) resolves alongside DefaultWorkSpace.wksp,
                        % under RepoRoot; anything else (relative or
                        % absolute) is used as given.
                        requested = char(varargin{1});
                        if any(requested == filesep) || any(requested == '/') || any(requested == '\')
                            workspaceFile = requested;
                        else
                            workspaceFile = fullfile(this.Parent.RepoRoot, requested);
                        end
                    else
                        workspaceFile = fullfile(this.Parent.RepoRoot, 'DefaultWorkSpace.wksp');
                    end
                    try
                        DIRS = jsondecode(fileread(workspaceFile));
                        this.RawDirectory     = this.fromStoredPath(DIRS.RawDirectory);
                        this.CacheDirectory   = this.fromStoredPath(DIRS.CacheDirectory);
                        this.ExportsDirectory = this.fromStoredPath(DIRS.ExportsDirectory);
                    catch ME
                        if strcmp(ME.identifier, 'MATLAB:undefinedVarOrClass') || ...
                           contains(ME.message, 'No such file or directory') || ...
                           contains(ME.message, 'cannot open')
                            % Initialize with sensible defaults relative to RepoRoot
                            this.RawDirectory     = fullfile(this.Parent.RepoRoot, 'Data', 'EEG');
                            this.CacheDirectory   = fullfile(this.Parent.RepoRoot, 'Data', 'Cache');
                            this.ExportsDirectory = fullfile(this.Parent.RepoRoot, 'Data', 'Exports');
                        else
                            rethrow(ME);
                        end
                    end

                    % Per-transformation remembered options, if the
                    % workspace file carries any (see WorkSpace.save/load
                    % and TransformSettings); absent on an older-format
                    % file, or on the fallback-defaults path above (DIRS
                    % was never assigned), both of which
                    % TransformSettings.loadFrom/this isfield check treat
                    % as "none stored". This block runs after the WHOLE
                    % try/catch, not just on failure -- it used to be
                    % accidentally nested inside the catch body (MATLAB's
                    % try/catch has a single closing `end` for both
                    % branches, easy to misread as two separate blocks),
                    % so a workspace's remembered settings were silently
                    % never restored on a normal successful open, only on
                    % the fallback path.
                    if exist('DIRS','var') && isstruct(DIRS) && isfield(DIRS, 'TransformSettings')
                        TransformSettings.loadFrom(DIRS.TransformSettings);
                    else
                        TransformSettings.reset();
                    end
                end
                elseif nargin == 4
                    this.RawDirectory = varargin{1};
                    this.CacheDirectory = varargin{2};
                    this.ExportsDirectory = varargin{3};
                    TransformSettings.reset();
            else
                throw('Workspace must be called with a parent, and either 3 of none directories (none = read default workspace)')
            end
        end
    end
end

