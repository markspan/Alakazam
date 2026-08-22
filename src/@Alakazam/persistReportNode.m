function newNode = persistReportNode(this, reportName, htmlFile, qmdFile)
%PERSISTREPORTNODE  Add a rendered Quarto report to its own Reports tree
%   as a top-level node, and display it -- the "output node" of
%   Alakazam.onExportMeasurements' report-rendering step (see
%   renderQuartoReport).
%
%   Unlike PERSISTRESULTNODE, a report is not the output of a real
%   transformation run on one specific dataset (onExportMeasurements
%   collects entries from potentially many datasets across the workspace
%   -- see collectMeasurementEntries), so there is no single natural
%   parent node to nest it under, and it does not belong mixed into Data
%   & Analyses's own per-subject branches either -- it gets its own peer
%   tree, Workspace.ReportsTree (hosted in Alakazam.ReportsTreePanel,
%   below Grand Averages -- see setupMainWindow), the same reasoning
%   Grand Averages already got its own tree instead of living as a node
%   inside Data & Analyses. Every "canX" opt is explicitly false
%   (bypassing WorkSpaceTree.optsFor, which infers those from fields --
%   DataFormat, Call, etc. -- a real transformation result carries and
%   this synthetic struct does not: List events/Recalculate/Apply to
%   All/Export ERPset would all be meaningless, and possibly crash,
%   against a report node).
%
%   Its own .mat (a "_node.mat" file) is saved next to the .qmd/.html it
%   wraps, in WorkSpace.reportsDirectory (ExportsDirectory/Reports, not
%   wherever the analyst happened to point the CSV export dialog) -- not
%   in the transformation-cache tree WorkSpace.treeTraverse rebuilds from,
%   but WorkSpace.loadReports scans that same Reports folder for
%   "_node.mat" files the same way loadGrandAverages scans
%   CacheDirectory/GrandAverages, so a report node -- like a grand
%   average -- DOES survive closing and reopening the workspace.
    reportEEG = struct();
    reportEEG.id = 'Report';
    % Routes to AlakazamPlotter.plotEpoched (see WorkSpace's isEpoched);
    % its own "Report" id check there runs before the DataFormat-based
    % branches this value would otherwise reach. Fixed for every report
    % node, so the human-readable name lives in .Label instead (used by
    % this function's own addNode call below, and by WorkSpace.loadReports
    % on reload).
    reportEEG.DataFormat = 'EPOCHED';
    reportEEG.DataType = 'REPORT';
    reportEEG.Label = reportName;
    reportEEG.ReportHtmlFile = htmlFile;
    reportEEG.ReportQmdFile = qmdFile;

    [folder, stem] = fileparts(htmlFile);
    reportEEG.File = fullfile(folder, [stem '_node.mat']);

    opts = struct('canListEvents', false, 'canRecalculate', false, ...
        'canApplyToAll', false, 'canExportErpset', false, 'canApplyTemplate', false);
    newNode = this.Workspace.ReportsTree.addNode(reportName, '', 'default', reportEEG.File, opts);
    this.Workspace.ReportsTree.SelectedNodes = newNode;
    this.Workspace.ActiveTree = this.Workspace.ReportsTree;

    % Persisted to disk under the variable name "EEG", matching every
    % other node's own cache file (see persistResultNode) -- so
    % re-selecting this node later in the same session (e.g. after
    % closing its tab) reloads correctly via the ordinary
    % loadNodeEEG/loadAndPlotNode path with no special-casing needed there.
    saveEegCache(reportEEG.File, reportEEG);
    this.Workspace.EEG = reportEEG;
end
