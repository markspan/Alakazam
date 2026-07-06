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
        Panel
        Tree
        ToolBox
        ToolBoxGroup
        RawFileIcon
        TimeSeriesIcon
        FrequenciesIcon
        javaObjects
        RootNode
        TreeRoot
        EEG
        jmenu
    end
    
    methods
        function this = WorkSpace(myParent, varargin)
            this.Parent = myParent;
            this.CreateTreeComponent();

            if nargin == 1 || nargin == 4
            if nargin == 1
                DIRS = load(fullfile(this.Parent.RepoRoot, 'DefaultWorkSpace.wksp'), '-mat');
                this.RawDirectory     = this.fromStoredPath(DIRS.RawDirectory);
                this.CacheDirectory   = this.fromStoredPath(DIRS.CacheDirectory);
                this.ExportsDirectory = this.fromStoredPath(DIRS.ExportsDirectory);
            elseif nargin == 4
                this.RawDirectory = varargin{1};
                this.CacheDirectory = varargin{2};
                this.ExportsDirectory = varargin{3};
            end
            else
                throw('Workspace must be called with a parent, and either 3 of none directories (none = read default workspace)')
            end
        end
    end
end

