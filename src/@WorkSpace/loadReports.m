function loadReports(this)
%LOADREPORTS  Populate the Reports tree (this.ReportsTree) from
%   ReportsDirectory/*_node.mat -- the node-cache Alakazam.persistReportNode
%   writes alongside every rendered report's .qmd/.html. Mirrors
%   WorkSpace.loadGrandAverages' own "flat folder, scan and re-add"
%   pattern, so a report node -- like a grand average -- now survives
%   closing and reopening the workspace, instead of only the files on
%   disk (see persistReportNode's own header comment).
%
%   SCOPED TO THIS WORKSPACE, as the grand averages are. The Reports folder
%   is a fixed subfolder of the Exports directory, and one Exports directory
%   is routinely shared by several workspaces, so a plain scan listed every
%   report any of them had rendered. A report now records the workspace that
%   made it (WorkSpace.ownerRecord: its Raw directory), and is listed where
%   that matches.
%
%   A REPORT MADE BEFORE THAT RECORD EXISTED is judged by its own data. A
%   report is built from one workspace's datasets, and its CSVs name them in
%   their dataset column by the recording they come from; one row that
%   names a recording of this workspace claims the report, and rows that
%   name only other recordings disown it. A report whose CSVs name no
%   recording at all (a cluster statistics report, whose tables are of
%   channels and times) cannot be judged and is listed, for the reason
%   loadGrandAverages gives: silently hiding a user's saved result is the
%   worse of the two errors.
%
%   See also WORKSPACE.OWNERRECORD, LOADGRANDAVERAGES,
%   ALAKAZAM.PERSISTREPORTNODE.
    reportsDir = this.reportsDirectory();
    if ~exist(reportsDir, "dir")
        return; % nothing rendered yet
    end

    recordings = recordingNames(this);
    found = dir(fullfile(reportsDir, '*_node.mat'));
    opts = struct('canListEvents', false, 'canRecalculate', false, ...
        'canApplyToAll', false, 'canExportErpset', false, 'canApplyTemplate', false);
    for i = 1:numel(found)
        file = fullfile(found(i).folder, found(i).name);
        meta = readEegCacheMeta(file);
        if ~belongsHere(this, file, meta, recordings)
            continue;
        end
        label = meta.Label;
        % .Label, not .id ('Report' for every node -- see
        % persistReportNode's own comment, it exists purely to route
        % AlakazamPlotter to ReportView, not to display).
        this.ReportsTree.addNode(label, '', 'default', file, opts);
    end
end

% ======================================================================= %
function tf = belongsHere(this, file, meta, recordings)
%BELONGSHERE  Whether the report whose node is FILE, with cache record META,
%   was made in this workspace: by its workspace record when it has one,
%   otherwise by the recordings its CSVs name (see the header). Read from
%   the small record, not the node, as every tree scan is (eegCacheMeta).
    tf = true;
    record = [];
    if isfield(meta, 'workspace')
        record = meta.workspace;
    end
    if isstruct(record) && isfield(record, 'raw') && ~isempty(record.raw)
        tf = samePath(this.fromStoredPath(record.raw), this.RawDirectory);
        return;
    end
    named = namedRecordings(file);
    if ~isempty(named)
        tf = any(ismember(named, recordings));
    end
end

function names = recordingNames(this)
%RECORDINGNAMES  The recordings of this workspace, as its tree's root
%   nodes name them: the names a report's dataset column uses.
    names = {};
    nodes = this.Tree.allNodes();
    if isempty(nodes)
        return;
    end
    names = {nodes([nodes.IsRoot]).Name};
end

function names = namedRecordings(nodeFile)
%NAMEDRECORDINGS  The recordings a report's CSVs name in their dataset
%   column, from the first rows of each: every row of a report comes from
%   the same workspace, so a few suffice, and a trial-level CSV can run to
%   millions of rows. Grand-average rows are left out, since they name the
%   grand average rather than a recording.
    names = {};
    [folder, nodeName] = fileparts(nodeFile);
    stem = regexprep(nodeName, '_node$', '');
    for csv = reshape(dir(fullfile(folder, [stem '*.csv'])), 1, [])
        names = [names, datasetColumn(fullfile(csv.folder, csv.name), 200)]; %#ok<AGROW>
    end
    names = unique(names);
end

function values = datasetColumn(file, maxRows)
%DATASETCOLUMN  The subject values of FILE's dataset column in its first
%   MAXROWS rows, or {} when it has no such column.
    values = {};
    fid = fopen(file, 'r', 'n', 'UTF-8');
    if fid < 0
        return;
    end
    closeFile = onCleanup(@() fclose(fid));
    header = splitCsvLine(fgetl(fid));
    col = find(strcmp(header, 'dataset'), 1);
    if isempty(col)
        return;
    end
    typeCol = find(strcmp(header, 'dataset_type'), 1);
    for r = 1:maxRows
        line = fgetl(fid);
        if ~ischar(line)
            break;
        end
        fields = splitCsvLine(line);
        if numel(fields) < col
            continue;
        end
        if ~isempty(typeCol) && numel(fields) >= typeCol && strcmp(fields{typeCol}, 'grand_average')
            continue;
        end
        values{end + 1} = fields{col}; %#ok<AGROW>
    end
    clear closeFile;
    values = unique(values(~cellfun(@isempty, values)));
end

function fields = splitCsvLine(line)
%SPLITCSVLINE  One CSV line as its fields, unquoted: a quoted field may hold
%   commas and doubled quotes, as csvField writes them.
    fields = {};
    if ~ischar(line)
        return;
    end
    tokens = regexp(line, '(?:^|,)("(?:[^"]|"")*"|[^,]*)', 'tokens');
    fields = cellfun(@(t) unquote(t{1}), tokens, 'UniformOutput', false);
end

function s = unquote(s)
    s = strtrim(s);
    if numel(s) >= 2 && s(1) == '"' && s(end) == '"'
        s = strrep(s(2:end - 1), '""', '"');
    end
end

function tf = samePath(a, b)
%SAMEPATH  Whether two directory paths name the same folder: separators
%   unified, a trailing one ignored, and case folded on Windows.
    norm = @(p) regexprep(strrep(strrep(char(p), '\', '/'), '//', '/'), '/$', '');
    if ispc
        tf = strcmpi(norm(a), norm(b));
    else
        tf = strcmp(norm(a), norm(b));
    end
end
