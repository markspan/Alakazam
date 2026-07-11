classdef WorkSpace < handle
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

            if nargin == 1 || nargin == 4
            if nargin == 1
                DIRS = jsondecode(fileread(fullfile(this.Parent.RepoRoot, 'DefaultWorkSpace.wksp')));
                this.RawDirectory     = this.fromStoredPath(DIRS.RawDirectory);
                this.CacheDirectory   = this.fromStoredPath(DIRS.CacheDirectory);
                this.ExportsDirectory = this.fromStoredPath(DIRS.ExportsDirectory);
                % Per-transformation remembered options, if the default
                % workspace file carries any (see WorkSpace.save/load and
                % TransformSettings); absent on an older-format file, which
                % TransformSettings.loadFrom treats as "none stored".
                if isfield(DIRS, 'TransformSettings')
                    TransformSettings.loadFrom(DIRS.TransformSettings);
                else
                    TransformSettings.reset();
                end
            elseif nargin == 4
                this.RawDirectory = varargin{1};
                this.CacheDirectory = varargin{2};
                this.ExportsDirectory = varargin{3};
                TransformSettings.reset();
            end
            else
                throw('Workspace must be called with a parent, and either 3 of none directories (none = read default workspace)')
            end
        end
    end
end

