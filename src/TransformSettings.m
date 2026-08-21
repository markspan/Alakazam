classdef TransformSettings < handle
%TRANSFORMSETTINGS  Per-transformation "last used options" for the
%   currently open workspace.
%
%   A transformation's own 'Init' branch (see e.g. DefineBins.m) can seed
%   its dialog from the last options actually used in *this* workspace,
%   instead of a hardcoded literal default, and write the newly-chosen
%   ones back after an interactive run:
%
%       stored = TransformSettings.get('AutoGEDAI');   % [] if none yet
%       ...
%       TransformSettings.set('AutoGEDAI', opts);
%
%   Unlike AlakazamSettings (machine-wide, via a fixed schema), this store
%   has no fixed shape -- each transformation's stored value is whatever
%   struct it chooses to keep, and TRANSFORMID is used as a dynamic
%   fieldname, so it must be a valid MATLAB identifier (true of every
%   transform id today: it is the name of its own folder/entry function).
%
%   Deliberately scoped to the *currently open workspace*, not global like
%   AlakazamSettings: WorkSpace.save()/load() persist/restore the whole
%   store as one field of the .wksp JSON (see allValues/loadFrom), and
%   WorkSpace's constructor seeds it from the default workspace the same
%   way. A lazily-created singleton (like AlakazamSettings) so every
%   transformation call sees the same in-memory values regardless of how
%   it was reached.
%
%   See also ALAKAZAMSETTINGS, WORKSPACE.

    properties (SetAccess = private)
        Values   % struct: Values.(transformId) = whatever that transform stored
    end

    methods (Static)
        function obj = instance()
        %INSTANCE  The shared store object (created empty on first use).
            persistent theInstance
            if isempty(theInstance) || ~isvalid(theInstance)
                theInstance = TransformSettings();
            end
            obj = theInstance;
        end

        function opts = get(transformId)
        %GET  TRANSFORMID's last-used options in this workspace, or []
        %   if nothing has been stored for it yet (a fresh workspace, or a
        %   transformation that has never run interactively in this one).
            obj = TransformSettings.instance();
            if isfield(obj.Values, transformId)
                opts = obj.Values.(transformId);
            else
                opts = [];
            end
        end

        function set(transformId, opts)
        %SET  Remember OPTS as TRANSFORMID's last-used options.
            obj = TransformSettings.instance();
            obj.Values.(transformId) = opts;
        end

        function reset()
        %RESET  Clear every stored value (a brand new, empty workspace).
            obj = TransformSettings.instance();
            obj.Values = struct();
        end

        function loadFrom(values)
        %LOADFROM  Replace the whole store, e.g. from a loaded .wksp file's
        %   own TransformSettings field. Anything not a struct (including
        %   [] / missing, for a .wksp saved before this existed) resets to
        %   empty rather than erroring, so opening an older workspace file
        %   just starts with no remembered per-transform options.
            if isempty(values) || ~isstruct(values)
                values = struct();
            end
            obj = TransformSettings.instance();
            obj.Values = values;
        end

        function values = allValues()
        %ALLVALUES  The whole store, for WorkSpace.save() to serialise.
            values = TransformSettings.instance().Values;
        end
    end

    methods (Access = private)
        function this = TransformSettings()
            this.Values = struct();
        end
    end
end
