classdef WorkSpace < handle
%WORKSPACE  The currently open session: its three working directories
%   (RawDirectory/CacheDirectory/ExportsDirectory), the two data-browser
%   trees (Tree, GrandAveragesTree), and the currently selected dataset
%   (EEG). Constructed once by Alakazam.m; see this class's own
%   constructor for how a workspace's directories are resolved (from a
%   named/default .wksp file, or passed in directly).

    properties
        Parent
        Name
        RawDirectory
        CacheDirectory
        ExportsDirectory
        Tree              % WorkSpaceTree, the data & analyses browser, hosted in Alakazam.DataTreePanel
        GrandAveragesTree % WorkSpaceTree, flat top-level grand-average nodes, hosted in Alakazam.GrandAveragesTreePanel
        ReportsTree       % WorkSpaceTree, flat top-level rendered-report nodes, hosted in Alakazam.ReportsTreePanel -- see Alakazam.persistReportNode
        ActiveTree        % WorkSpaceTree, whichever of Tree/GrandAveragesTree/ReportsTree was last interacted with -- see CreateTreeComponent
        Groups            % struct('subject',{},'group',{},'person',{},'session',{}): per-raw-file metadata -- between-subjects group, and the person/session identity behind a multi-session recording (day 1 vs day 2, ...) -- see editSubjects/groupFor/personFor/sessionFor
        EEG
    end
    
    methods
        function this = WorkSpace(myParent, varargin)
        %WORKSPACE  WORKSPACE(parent) / WORKSPACE(parent, name) reads
        %   directories from a .wksp file (the default one, or NAME);
        %   WORKSPACE(parent, raw, cache, exports) sets them directly. Any
        %   other NARGIN is a caller error.
        %
        %   NOTE: this used to be a single `if nargin==1||2||4` wrapping a
        %   nested `if nargin==1||2`, with `elseif nargin==4`/`else`
        %   attached to the OUTER if. Since the outer condition already
        %   included nargin==4, that elseif could never be reached -- the
        %   4-argument form silently left every directory unset. Written
        %   here as three plain, mutually exclusive branches instead, so
        %   there is only one place nargin is tested per case.
            this.Parent = myParent;
            this.CreateTreeComponent();
            this.Groups = struct('subject', {}, 'group', {}, 'person', {}, 'session', {});

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

                % Per-transformation remembered options, if the workspace
                % file carries any (see WorkSpace.save/load and
                % TransformSettings); absent on an older-format file, or
                % on the fallback-defaults path above (DIRS was never
                % assigned), both of which TransformSettings.loadFrom/this
                % isfield check treat as "none stored". This block runs
                % after the WHOLE try/catch, not just on failure -- it
                % used to be accidentally nested inside the catch body
                % (MATLAB's try/catch has a single closing `end` for both
                % branches, easy to misread as two separate blocks), so a
                % workspace's remembered settings were silently never
                % restored on a normal successful open, only on the
                % fallback path.
                if exist('DIRS','var') && isstruct(DIRS) && isfield(DIRS, 'TransformSettings')
                    TransformSettings.loadFrom(DIRS.TransformSettings);
                else
                    TransformSettings.reset();
                end
                if exist('DIRS','var') && isstruct(DIRS) && isfield(DIRS, 'Groups')
                    this.Groups = this.groupsFromStored(DIRS.Groups);
                end
            elseif nargin == 4
                this.RawDirectory     = varargin{1};
                this.CacheDirectory   = varargin{2};
                this.ExportsDirectory = varargin{3};
                TransformSettings.reset();
            else
                throw(MException('Alakazam:WorkSpace', [ ...
                    'WorkSpace must be called with a parent, and either 0 or 3 ' ...
                    'directories (0 = read the default workspace).']));
            end
        end
    end
end
