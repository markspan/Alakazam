function loadReports(this)
%LOADREPORTS  Populate the Reports tree (this.ReportsTree) from
%   ReportsDirectory/*_node.mat -- the node-cache Alakazam.persistReportNode
%   writes alongside every rendered report's .qmd/.html. Mirrors
%   WorkSpace.loadGrandAverages' own "flat folder, scan and re-add"
%   pattern, so a report node -- like a grand average -- now survives
%   closing and reopening the workspace, instead of only the files on
%   disk (see persistReportNode's own header comment).
    reportsDir = this.reportsDirectory();
    if ~exist(reportsDir, "dir")
        return; % nothing rendered yet
    end

    found = dir(fullfile(reportsDir, '*_node.mat'));
    opts = struct('canListEvents', false, 'canRecalculate', false, ...
        'canApplyToAll', false, 'canExportErpset', false);
    for i = 1:numel(found)
        file = fullfile(found(i).folder, found(i).name);
        loaded = load(file, "EEG");
        % .Label, not .id ('Report' for every node -- see
        % persistReportNode's own comment, it exists purely to route
        % AlakazamPlotter to ReportView, not to display).
        this.ReportsTree.addNode(loaded.EEG.Label, '', 'default', file, opts);
    end
end
