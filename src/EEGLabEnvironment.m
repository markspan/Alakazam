classdef EEGLabEnvironment
%EEGLABENVIRONMENT  Ensures EEGLAB, its plugins and required MATLAB
%   toolboxes are present.
%
%   Alakazam runs on top of EEGLAB and a handful of its import/analysis
%   plugins, plus the Signal Processing and Statistics and Machine Learning
%   toolboxes. This class isolates the "make the MATLAB environment ready"
%   concern from the application itself: it checks whether EEGLAB is on the
%   path, offers to download and install it if not, installs the plugins
%   Alakazam relies on, and warns if a required toolbox is missing. Nothing
%   here touches application state, so the methods are static.
%
%   Usage:
%       EEGLabEnvironment.ensure();   % called once at application startup
%
%   Installs go under <home>/Documents/MATLAB and are added to the path for
%   the session only (no savepath), leaving the user's global path untouched.
%   Plugin or FastICA failures warn rather than abort, so the app still starts
%   offline; a missing EEGLAB that the user declines to install is fatal. A
%   missing toolbox cannot be auto-installed (it needs a MATLAB licence), so
%   it is only reported, non-fatally. EEGLAB found on the path but never
%   actually run in this MATLAB session (its own subfolders and plugin
%   functions are only added to the path by eeglab() itself running) is
%   fatal too, with a dialog explaining to run eeglab once.
%
%   See also ALAKAZAM.

    properties (Constant, Access = private)
        % Plugin registry name and a function it provides, per EEGLAB plugin.
        Plugins = { ...
            'bva-io',  'pop_loadbv';   ...  % BrainVision (.vhdr) import
            'ICLabel', 'iclabel';      ...  % IC classification
            'dipfit',  'dipfitdefs'}        % head models + 10-20 electrode
                                             % template (AutoEyeICA, AutoGEDAI)

        EEGLabUrl  = 'https://sccn.ucsd.edu/eeglab/currentversion/eeglab_current.zip'
        FastIcaUrl = 'https://research.ics.aalto.fi/ica/fastica/code/FastICA_2.5.zip'

        % MATLAB toolbox name, a function it provides, and why Alakazam
        % needs it. Unlike the EEGLAB plugins above, a toolbox cannot be
        % silently downloaded here -- it needs a MATLAB licence and the
        % Add-On Explorer -- so ensureToolboxes only checks and informs.
        Toolboxes = { ...
            'Signal Processing Toolbox', 'butter', ...
                'window functions (Fourier) and multitaper spectral estimation (SpectralMeasure)'; ...
            'Statistics and Machine Learning Toolbox', 'pca', ...
                'required by EEGLAB and some of its plugins' ...
        }
    end

    methods (Static)
        function ensure()
        %ENSURE  Make sure EEGLAB, the required plugins and MATLAB toolboxes
        %   are available.
            EEGLabEnvironment.ensureEEGLab();
            EEGLabEnvironment.ensurePlugins();
            EEGLabEnvironment.ensureToolboxes();
        end

        function folder = pickNewestEEGLab(candidates)
        %PICKNEWESTEEGLAB  Choose the EEGLAB install to use from CANDIDATES
        %   (a cellstr of folders that each contain an eeglab.m). Returns ''
        %   when there is nothing usable. Pure: no disk access, so the
        %   choice can be tested without an EEGLAB install.
        %
        %   '_old' folders are skipped deliberately. EEGLAB's own
        %   eeglab_update renames the superseded install with that suffix
        %   and leaves it complete and working, so a plain search finds it
        %   and may well prefer it (dir returns 'eeglab2026.0.0_old' before
        %   'eeglab2026.1.0' in ASCII order) -- which would quietly pin
        %   Alakazam to the copy the user had just replaced.
            folder = '';
            if isempty(candidates)
                return;
            end
            names = candidates(~endsWith(candidates, '_old', 'IgnoreCase', true));
            if isempty(names)
                return;   % only superseded installs: treat as not found
            end
            % Sort by name first so the result never depends on dir's order,
            % then take the highest version, ties going to the last name.
            names = sort(names);
            keys  = cellfun(@EEGLabEnvironment.versionKey, names);
            folder = names{find(keys == max(keys), 1, 'last')};
        end

        function folder = findInstalled(targetName, probeFile)
        %FINDINSTALLED  Locate a previous installFromZip install on disk.
        %   FOLDER = FINDINSTALLED(TARGETNAME, PROBEFILE) looks for PROBEFILE
        %   under <home>/Documents/MATLAB/<targetName> (where installFromZip
        %   puts things) and returns its containing folder, or '' if not
        %   found. Does NOT check or modify the MATLAB path.
        %
        %   addpath is session-only (installFromZip deliberately never calls
        %   savepath), so a previously-downloaded plugin is not back on the
        %   path in a fresh MATLAB session even though it is still on disk.
        %   Callers use this to reattach an existing install (addpath the
        %   returned folder) instead of re-downloading, and -- for installs
        %   gated behind their own consent prompt, e.g. AutoGEDAI's -- to
        %   skip re-asking every session for something already agreed to.
            folder = '';
            home = getenv('USERPROFILE');
            if isempty(home)
                home = char(java.lang.System.getProperty('user.home'));
            end
            target = fullfile(home, 'Documents', 'MATLAB', targetName);
            if ~exist(target, 'dir')
                return;
            end
            found = dir(fullfile(target, '**', probeFile));
            if ~isempty(found)
                folder = found(1).folder;
            end
        end

        function installFromZip(url, targetName, probeFile)
        %INSTALLFROMZIP  Download a zip, unzip under Documents/MATLAB, add to path.
        %   If PROBEFILE is already present on disk from a previous install
        %   (see findInstalled), reattaches that folder to the path and
        %   returns without downloading anything. Otherwise downloads the
        %   archive at URL into a temporary file, unzips it under
        %   <home>/Documents/MATLAB/<targetName>, locates PROBEFILE in the
        %   unzipped tree and adds that folder to the MATLAB path. Errors if
        %   the download, unzip or probe-file lookup fails. We do not call
        %   savepath. Public (not just used at startup): individual
        %   transformations, e.g. AutoGEDAI, call this directly to install an
        %   optional plugin on first use, after their own consent prompt.
            existing = EEGLabEnvironment.findInstalled(targetName, probeFile);
            if ~isempty(existing)
                addpath(existing);
                return;
            end

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
                    'I wasn''t able to download or unzip %s, I''m afraid: %s', url, downloadError.message);
            end

            % The archive usually unzips into a versioned subfolder; locate the
            % probe file within it and add that folder to the path.
            found = dir(fullfile(target, '**', probeFile));
            if isempty(found)
                error('Alakazam:installMissing', ...
                    'I''m afraid %s was not found under %s after unzipping %s.', ...
                    probeFile, target, url);
            end
            addpath(found(1).folder);
        end
    end

    methods (Static, Access = private)
        function folder = newestEEGLabFolder()
        %NEWESTEEGLABFOLDER  The newest EEGLAB install under
        %   <home>/Documents/MATLAB/eeglab, or '' if there is none.
        %
        %   This used to be a hardcoded 'eeglab2026.0.0', which stopped
        %   resolving the moment EEGLAB updated itself: EEGLAB's own
        %   eeglab_update unzips the new release into a folder named after
        %   the NEW version and renames the previous one with an '_old'
        %   suffix, so the hardcoded name pointed at a folder that no longer
        %   existed. Any version-specific path here is wrong by
        %   construction; the version has to be discovered.
        %
        %   '_old' folders are skipped deliberately. They are complete,
        %   working installs, so a plain search finds them and may well
        %   prefer one (dir returns '..._old' before a higher version
        %   number in ASCII order) -- which would quietly pin Alakazam to
        %   the superseded copy the user just replaced.
            folder = '';
            home = getenv('USERPROFILE');
            if isempty(home)
                home = char(java.lang.System.getProperty('user.home'));
            end

            % Two places worth looking. The first is where installFromZip
            % puts EEGLAB. The second is beside Alakazam itself: EEGLAB's
            % eeglab_update unzips into whatever folder its dialog is
            % pointing at, which defaults to the current working directory,
            % so running it with Alakazam as the current folder installs
            % EEGLAB as a sibling of src/. That is a perfectly workable
            % layout, and Alakazam should find it rather than offer to
            % download a second copy.
            roots = { fullfile(home, 'Documents', 'MATLAB', 'eeglab'), ...
                      fileparts(fileparts(mfilename('fullpath'))) };

            candidates = {};
            for k = 1:numel(roots)
                if ~exist(roots{k}, 'dir')
                    continue;
                end
                % One level down, not a '**' recursive walk: an install is
                % always <root>/eeglab<version>/eeglab.m, and recursing
                % would scan every one of EEGLAB's own 4500-odd files.
                found = dir(fullfile(roots{k}, '*', 'eeglab.m'));
                candidates = [candidates, {found.folder}];   %#ok<AGROW>
                if exist(fullfile(roots{k}, 'eeglab.m'), 'file') == 2
                    candidates{end+1} = roots{k};            %#ok<AGROW>
                end
            end
            folder = EEGLabEnvironment.pickNewestEEGLab(candidates);
        end

        function key = versionKey(folderPath)
        %VERSIONKEY  A sortable number for an EEGLAB folder's version, so
        %   'eeglab2026.1.0' outranks 'eeglab2026.0.0'. A name carrying no
        %   version sorts lowest rather than erroring.
        %
        %   The last path segment is taken by hand, not with fileparts:
        %   fileparts('.../eeglab2026.1.0') reads the trailing '.0' as a
        %   file extension and hands back 'eeglab2026.1', losing the patch
        %   number.
            segments = regexp(folderPath, '[\\/]', 'split');
            segments = segments(~cellfun(@isempty, segments));
            if isempty(segments)
                key = 0;
                return;
            end
            nums = regexp(segments{end}, '\d+', 'match');
            n = min(3, numel(nums));
            key = 0;
            for k = 1:n
                key = key * 1000 + str2double(nums{k});
            end
            key = key * 1000^(3 - n);   % pad so 2026 < 2026.0.1
        end

        function ensureEEGLab()
        %ENSUREEEGLAB  Put EEGLAB on the path, offering to install it if missing.
        %   EEGLAB is expected to be installed and already on the path. If it is
        %   not found, the user is asked for permission to download and install
        %   the latest version, which is then added to the path and launched.

            if isempty(which('eeglab'))
                target = EEGLabEnvironment.newestEEGLabFolder();
                if ~isempty(target)
                    addpath(target);
                    eeglab('nogui')
                end
            end

            if ~isempty(which('eeglab'))
                EEGLabEnvironment.ensureEEGLabInitialized();
                return; % already available
            end

            % LEGACY-JAVA-GUI: questdlg is a classic Java/AWT dialog, not
            % a uifigure -- see migration.md's "old-style Java-based
            % graphics" checklist. Runs at app startup, before MainFigure
            % exists, so there is no uifigure yet to parent a modern
            % replacement to.
            answer = questdlg([ ...
                'EEGLAB was not found on the MATLAB path, and Alakazam requires it. ', ...
                'Download and install the latest EEGLAB now (about 150 MB) into ', ...
                'your Documents/MATLAB folder?'], ...
                'EEGLAB not found', ...
                'Download and install', 'Cancel', 'Download and install');
            if ~strcmp(answer, 'Download and install')
                error('Alakazam:eeglabMissing', ...
                    'I''m afraid EEGLAB is required but was not found on the MATLAB path.');
            end

            EEGLabEnvironment.installFromZip(EEGLabEnvironment.EEGLabUrl, 'eeglab', 'eeglab.m');
            eeglab;
        end

        function ensureEEGLabInitialized()
        %ENSUREEEGLABINITIALIZED  Make sure EEGLAB has actually been run at
        %   least once in this MATLAB session, not merely found on the path.
        %   Having eeglab.m on the path is not enough: EEGLAB adds its own
        %   subfolders and every plugin's functions (pop_loadset,
        %   plugin_askinstall, ...) to the path only when eeglab() itself
        %   runs -- something the fresh-install branch above does automatically
        %   (it calls eeglab; right after installing), but which a MATLAB
        %   install where EEGLAB was already on the path (e.g. carried over
        %   from a previous MATLAB version, or added by a startup.m) may never
        %   have done. Left undetected, this fails much later and far more
        %   cryptically -- "Undefined function 'plugin_askinstall'" inside
        %   ensurePlugins, then "Unrecognized function or variable
        %   'pop_loadset'" deep inside WorkSpace.loadSETFile, crashing the
        %   whole app construction -- instead of here, the one place that can
        %   actually explain what is wrong.

            if isempty(which('pop_loadset'))
               eeglab('nogui') 
            end
            if ~isempty(which('pop_loadset'))
                return; % EEGLAB has already been initialized this session
            end
            % LEGACY-JAVA-GUI: errordlg, see the note in ensureEEGLab
            % above (same "runs before MainFigure exists" reason).
            uiwait(errordlg([ ...
                'I''m afraid EEGLAB is on the MATLAB path, but has not been run yet in this ', ...
                'MATLAB session. EEGLAB only adds its own subfolders and plugin ', ...
                'functions (pop_loadset, plugin_askinstall, ...) to the path once ', ...
                'eeglab() itself actually runs, so Alakazam cannot use it just yet.', newline newline, ...
                'Would you run eeglab once (type "eeglab" at the MATLAB command prompt), ', ...
                'then start Alakazam again? You can close EEGLAB''s own window ', ...
                'once it opens; Alakazam does not need it to stay open.'], ...
                'EEGLAB not yet initialized'));
            error('Alakazam:eeglabNotInitialized', ...
                'I''m afraid EEGLAB has not been run yet in this MATLAB session. Would you run eeglab once, then start Alakazam again?');
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

        function ensureToolboxes()
        %ENSURETOOLBOXES  Warn if a required MATLAB toolbox is not usable.
        %   Checks each entry in Toolboxes by probing for a function it
        %   provides. A missing toolbox cannot be installed the way EEGLAB
        %   plugins are (it needs a MATLAB licence and the Add-On Explorer),
        %   so this only informs the user with a dialog; the app still
        %   starts, and only the features that need the missing toolbox
        %   will fail later when actually used.
            toolboxes = EEGLabEnvironment.Toolboxes;
            missing = {};
            for i = 1:size(toolboxes, 1)
                name     = toolboxes{i, 1};
                probeFcn = toolboxes{i, 2};
                why      = toolboxes{i, 3};
                if isempty(which(probeFcn))
                    missing{end + 1} = sprintf('%s (%s)', name, why); %#ok<AGROW>
                end
            end
            if isempty(missing)
                return;
            end
            % LEGACY-JAVA-GUI: warndlg, see the note in ensureEEGLab above.
            warndlg(sprintf([ ...
                'The following MATLAB toolbox(es) were not found:\n\n%s\n\n', ...
                'Alakazam will still start, but the features that need them ', ...
                'will fail. Install them from MATLAB''s Add-On Explorer ', ...
                '(Home tab > Add-Ons), or ask whoever manages your MATLAB licence.'], ...
                strjoin(missing, newline)), 'Missing MATLAB toolbox(es)');
        end
    end
end
