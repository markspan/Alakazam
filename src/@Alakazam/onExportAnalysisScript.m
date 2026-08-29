function onExportAnalysisScript(this)
%ONEXPORTANALYSISSCRIPT  Ribbon action (Export/Report tab): write the whole
%   workspace's analysis out as a runnable MATLAB script.
%
%   Walks every root recording in the Data & Analyses tree, collects its
%   processing chain (the same (transformId, params) list a template
%   records, see collectBranchTree), adds the grand averages, and hands the
%   lot to exportAnalysisScript. The result is a plain .m file: a record of
%   what was run that can be read, edited, version-controlled and re-run
%   without the app.
%
%   Driven from the tree rather than from a scan of the cache directory,
%   for the same reason findGrandAverageCandidates is: a cache outlives the
%   workspaces that wrote it, and a script built from stale files would
%   describe an analysis this workspace never performed.
%
%   See also EXPORTANALYSISSCRIPT, MATLABLITERAL, COLLECTBRANCHTREE.
    [restoreBusy, setBusy] = beginBusy(this.MainFigure, 'Collecting the analysis...');

    subjects = struct('name', {}, 'rawFile', {}, 'cacheFile', {}, 'loader', {}, 'steps', {});
    nodes = this.Workspace.Tree.allNodes();
    if ~isempty(nodes)
        roots = nodes([nodes.IsRoot]);
    else
        roots = nodes;
    end

    for r = 1:numel(roots)
        steps = collectSubjectSteps(this, roots(r));
        if isempty(steps)
            continue;   % an imported recording nobody has processed yet
        end
        rawFile = rawFileFor(this, roots(r));
        subjects(end + 1) = struct( ...
            'name',      roots(r).Name, ...
            'rawFile',   rawFile, ...
            'cacheFile', roots(r).UserData, ...   % the imported dataset the script reads
            'loader',    loaderFor(rawFile), ...
            'steps',     steps); %#ok<AGROW>
    end

    if isempty(subjects)
        clear restoreBusy;
        % LEGACY-JAVA-GUI: msgbox, see the note near onListEvents.
        msgbox(['There is no analysis to export yet: no recording in this workspace has ' ...
            'had a transformation run on it. Would you process at least one first?'], ...
            'Nothing to export');
        return;
    end

    grandAverages = collectGrandAverages(this);

    setBusy('Writing the script...');
    try
        [code, sidecars] = exportAnalysisScript(subjects, grandAverages, struct( ...
            'rawDirectory', this.Workspace.RawDirectory, ...
            'cacheDirectory', this.Workspace.CacheDirectory, ...
            'outputDirectory', this.Workspace.ExportsDirectory));
    catch ME
        clear restoreBusy;
        % LEGACY-JAVA-GUI: warndlg, see the note near onListEvents.
        warndlg(sprintf('I wasn''t able to build the script: %s', ME.message), ...
            'Could not export the analysis');
        return;
    end

    exportsDir = this.Workspace.ExportsDirectory;
    if isempty(exportsDir) || ~isfolder(exportsDir)
        exportsDir = pwd;
    end
    clear restoreBusy;   % the save dialog must not open behind the indicator

    [fileName, pathName] = uiputfile({'*.m', 'MATLAB script (*.m)'}, ...
        'Export analysis as MATLAB code', fullfile(exportsDir, 'alakazam_analysis.m'));
    if isequal(fileName, 0)
        return;
    end

    target = fullfile(pathName, fileName);
    fid = fopen(target, 'w');
    if fid < 0
        warndlg(sprintf('I couldn''t open "%s" for writing.', target), 'Could not save');
        return;
    end
    closeFile = onCleanup(@() fclose(fid));
    fwrite(fid, code, 'char');
    clear closeFile;

    % The bin scripts travel beside the .m, and the script reads them back
    % from its own folder, so the two must be written to the same place.
    for k = 1:numel(sidecars)
        sidecarFile = fullfile(pathName, sidecars(k).name);
        sfid = fopen(sidecarFile, 'w');
        if sfid < 0
            warndlg(sprintf(['The script was written, but its bin script could not be saved ' ...
                'alongside it:\n\n%s\n\nThe script will not run until that file exists.'], ...
                sidecarFile), 'Bin script not saved');
            return;
        end
        closeSidecar = onCleanup(@() fclose(sfid));
        fwrite(sfid, sidecars(k).content, 'char');
        clear closeSidecar;
    end

    extra = '';
    if ~isempty(sidecars)
        extra = sprintf(' Its %d bin script(s) were written beside it as .binscript files.', ...
            numel(sidecars));
    end

    % LEGACY-JAVA-GUI: msgbox, see the note near onListEvents.
    msgbox(sprintf(['Wrote the analysis for %d recording(s) and %d grand average(s) to:\n\n%s\n\n' ...
        'It calls Alakazam''s own transformations, so it reproduces this analysis rather than ' ...
        'approximating it in another toolbox.%s'], ...
        numel(subjects), numel(grandAverages), target, extra), 'Analysis exported');
end

% ----------------------------------------------------------------------- %
function steps = collectSubjectSteps(this, rootNode)
%COLLECTSUBJECTSTEPS  Every processing step below ROOTNODE, flattened with
%   parent indices. collectBranchTree starts AT the file it is given and
%   includes it, but a root node is the raw import rather than a
%   transformation, so each of its children is collected separately and the
%   results are stitched into one list whose parents point at the raw
%   import (-1).
    steps = struct('transformId', {}, 'params', {}, 'parent', {});
    [folder, stem] = fileparts(rootNode.UserData);
    childDir = fullfile(folder, stem);
    if exist(childDir, 'dir') ~= 7
        return;
    end
    childMat = dir(fullfile(childDir, '*.mat'));
    for k = 1:numel(childMat)
        branch = this.collectBranchTree(fullfile(childMat(k).folder, childMat(k).name));
        offset = numel(steps);
        for b = 1:numel(branch)
            step = branch(b);
            if step.parent < 1
                step.parent = -1;               % hangs off the raw import
            else
                step.parent = step.parent + offset;
            end
            steps(end + 1) = step; %#ok<AGROW>
        end
    end
end

function file = rawFileFor(this, rootNode)
%RAWFILEFOR  The recording a root node was imported from. The root's own
%   cache file is named after it (see WorkSpace.resolveCachePaths), so the
%   raw file is that stem in the raw directory; the extension is recovered
%   by looking, since the cache stem does not carry it.
    [~, stem] = fileparts(rootNode.UserData);
    rawDir = this.Workspace.RawDirectory;
    for ext = {'.set', '.vhdr', '.erp', '.mat'}
        candidate = fullfile(rawDir, [stem ext{1}]);
        if exist(candidate, 'file') == 2
            file = candidate;
            return;
        end
    end
    file = fullfile(rawDir, stem);
end

function loader = loaderFor(rawFile)
    [~, ~, ext] = fileparts(rawFile);
    switch lower(ext)
        case '.vhdr'; loader = 'bva';
        case '.erp';  loader = 'erp';
        case '.mat';  loader = 'mat';
        otherwise;    loader = 'set';
    end
end

function gas = collectGrandAverages(this)
%COLLECTGRANDAVERAGES  The workspace's grand averages, read back from each
%   saved node's own etc.GrandAverage record (see GrandAverage), which is
%   where the source list and the weighting were kept.
    gas = struct('name', {}, 'weighted', {}, 'sources', {}, 'subjects', {}, 'cell', {});
    nodes = this.Workspace.GrandAveragesTree.allNodes();
    for i = 1:numel(nodes)
        file = nodes(i).UserData;
        if isempty(file) || exist(file, 'file') ~= 2
            continue;
        end
        loaded = load(file, 'EEG');
        record = struct('sources', {{}}, 'weighted', false);
        if isfield(loaded.EEG, 'etc') && isfield(loaded.EEG.etc, 'GrandAverage')
            record = loaded.EEG.etc.GrandAverage;
        end
        sources = getOr(record, 'sources', {});
        gas(end + 1) = struct('name', nodes(i).Name, ...
            'weighted', logical(getOr(record, 'weighted', false)), ...
            'sources', {sources}, ...
            'subjects', {subjectsBehind(this, sources)}, ...
            'cell', {designCellOf(loaded.EEG)}); %#ok<AGROW>
    end
end

function text = designCellOf(EEG)
%DESIGNCELLOF  The design cell a grand average came from, as readable text,
%   or '' when it was assembled by hand. Recorded by saveGrandAverage (see
%   designCellSpecs); carried into the exported script as a comment so the
%   generated code says what a grand average REPRESENTS, not only which
%   recordings happened to go into it.
    text = '';
    if ~isfield(EEG, 'etc') || ~isfield(EEG.etc, 'DesignCell')
        return;
    end
    cell = EEG.etc.DesignCell;
    parts = {};
    for field = {'group', 'session'}
        if isfield(cell, field{1})
            value = strtrim(char(string(cell.(field{1}))));
            if ~isempty(value) && ~any(strcmp(value, {'(no group)', '(no session)'}))
                parts{end + 1} = value; %#ok<AGROW>
            end
        end
    end
    text = strjoin(parts, ', ');
end

function names = subjectsBehind(this, sources)
%SUBJECTSBEHIND  Which recordings a grand average was actually built from.
%
%   Its own record keeps the cache FILES it combined, which a standalone
%   script cannot use: those paths belong to this machine's cache and mean
%   nothing where the script runs. But each one sits under the cache folder
%   named for the recording it descends from (see WorkSpace.resolveCachePaths),
%   so the recording names are recoverable from the paths, and the script can
%   then select by name from the averages it computed itself.
%
%   Without this a grand average has to be emitted over EVERY average the
%   script produces, which is wrong for any workspace whose grand averages
%   were built from a subset (a patient group, a pilot exclusion).
    names = {};
    cacheDir = this.Workspace.CacheDirectory;
    if isempty(cacheDir) || isempty(sources)
        return;
    end
    if cacheDir(end) ~= filesep
        cacheDir(end + 1) = filesep;
    end
    for i = 1:numel(sources)
        source = char(string(sources{i}));
        if ~startsWith(source, cacheDir)
            continue;   % from another cache entirely; not resolvable here
        end
        relative = source(numel(cacheDir) + 1:end);
        parts = strsplit(relative, filesep);
        stem = regexprep(parts{1}, '\.mat$', '');
        if ~isempty(stem) && ~any(strcmp(names, stem))
            names{end + 1} = stem; %#ok<AGROW>
        end
    end
end

function value = getOr(s, name, default)
    if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
        value = s.(name);
    else
        value = default;
    end
end
