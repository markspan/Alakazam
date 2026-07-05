classdef EEGLabEnvironment
%EEGLABENVIRONMENT  Ensures EEGLAB and the plugins Alakazam needs are present.
%
%   Alakazam runs on top of EEGLAB and a handful of its import/analysis
%   plugins. This class isolates the "make the MATLAB environment ready"
%   concern from the application itself: it checks whether EEGLAB is on the
%   path, offers to download and install it if not, and then installs the
%   plugins Alakazam relies on. Nothing here touches application state, so the
%   methods are static.
%
%   Usage:
%       EEGLabEnvironment.ensure();   % called once at application startup
%
%   Installs go under <home>/Documents/MATLAB and are added to the path for
%   the session only (no savepath), leaving the user's global path untouched.
%   Plugin or FastICA failures warn rather than abort, so the app still starts
%   offline; a missing EEGLAB that the user declines to install is fatal.
%
%   See also ALAKAZAM.

    properties (Constant, Access = private)
        % Plugin registry name and a function it provides, per EEGLAB plugin.
        Plugins = { ...
            'bva-io',  'pop_loadbv';  ...  % BrainVision (.vhdr) import
            'ICLabel', 'iclabel'}          % IC classification

        EEGLabUrl  = 'https://sccn.ucsd.edu/eeglab/currentversion/eeglab_current.zip'
        FastIcaUrl = 'https://research.ics.aalto.fi/ica/fastica/code/FastICA_2.5.zip'
    end

    methods (Static)
        function ensure()
        %ENSURE  Make sure EEGLAB and the required plugins are available.
            EEGLabEnvironment.ensureEEGLab();
            EEGLabEnvironment.ensurePlugins();
        end
    end

    methods (Static, Access = private)
        function ensureEEGLab()
        %ENSUREEEGLAB  Put EEGLAB on the path, offering to install it if missing.
        %   EEGLAB is expected to be installed and already on the path. If it is
        %   not found, the user is asked for permission to download and install
        %   the latest version, which is then added to the path and launched.
            if ~isempty(which('eeglab'))
                return; % already available
            end

            answer = questdlg([ ...
                'EEGLAB was not found on the MATLAB path, and Alakazam requires it. ', ...
                'Download and install the latest EEGLAB now (about 150 MB) into ', ...
                'your Documents/MATLAB folder?'], ...
                'EEGLAB not found', ...
                'Download and install', 'Cancel', 'Download and install');
            if ~strcmp(answer, 'Download and install')
                error('Alakazam:eeglabMissing', ...
                    'EEGLAB is required but was not found on the MATLAB path.');
            end

            EEGLabEnvironment.installFromZip(EEGLabEnvironment.EEGLabUrl, 'eeglab', 'eeglab.m');
            eeglab;
        end

        function ensurePlugins()
        %ENSUREPLUGINS  Install the EEGLAB plugins (and FastICA) Alakazam uses.
        %   The registry plugins go through EEGLAB's plugin manager; FastICA is
        %   not in the registry, so it is downloaded directly. Each item is
        %   installed only if its entry function is missing.
            plugins = EEGLabEnvironment.Plugins;
            for i = 1:size(plugins, 1)
                pluginName = plugins{i, 1};
                probeFcn   = plugins{i, 2};
                if ~isempty(which(probeFcn))
                    continue; % plugin already provides this function
                end
                try
                    plugin_askinstall(pluginName, probeFcn, true);
                catch installError
                    warning('Alakazam:pluginInstall', ...
                        'Could not install EEGLAB plugin ''%s'': %s', ...
                        pluginName, installError.message);
                end
            end

            % FastICA is a standalone package (not in the EEGLAB registry).
            if isempty(which('fastica'))
                try
                    EEGLabEnvironment.installFromZip(EEGLabEnvironment.FastIcaUrl, 'FastICA', 'fastica.m');
                catch installError
                    warning('Alakazam:pluginInstall', ...
                        'Could not install FastICA: %s', installError.message);
                end
            end
        end

        function installFromZip(url, targetName, probeFile)
        %INSTALLFROMZIP  Download a zip, unzip under Documents/MATLAB, add to path.
        %   Downloads the archive at URL into a temporary file, unzips it under
        %   <home>/Documents/MATLAB/<targetName>, locates PROBEFILE in the
        %   unzipped tree and adds that folder to the MATLAB path. Errors if the
        %   download, unzip or probe-file lookup fails. We do not call savepath.
            home = getenv('USERPROFILE');
            if isempty(home)
                home = char(java.lang.System.getProperty('user.home'));
            end
            target = fullfile(home, 'Documents', 'MATLAB', targetName);
            if ~exist(target, 'dir')
                mkdir(target);
            end

            zipPath = fullfile(tempdir, [targetName '.zip']);
            try
                fprintf('Downloading %s ...\n', url);
                websave(zipPath, url, weboptions('Timeout', 600));
                fprintf('Unzipping into %s ...\n', target);
                unzip(zipPath, target);
            catch downloadError
                error('Alakazam:download', ...
                    'Could not download or unzip %s: %s', url, downloadError.message);
            end

            % The archive usually unzips into a versioned subfolder; locate the
            % probe file within it and add that folder to the path.
            found = dir(fullfile(target, '**', probeFile));
            if isempty(found)
                error('Alakazam:installMissing', ...
                    '%s was not found under %s after unzipping %s.', ...
                    probeFile, target, url);
            end
            addpath(found(1).folder);
        end
    end
end
