function onExportGrandAverages(this)
%ONEXPORTGRANDAVERAGES  Toolbar callback (Grand Average tab):
%   export every Grand Average currently in
%   Workspace.GrandAveragesTree to one long-format, R-compatible
%   CSV (see exportGrandAveragesCSV). A bulk export of everything,
%   not a per-node action -- one button press is the simplest UI
%   for "get everything I have computed into R", and the resulting
%   long/tidy format already carries a grand_average column to
%   filter/facet by in R, so there is no real need for a
%   per-grand-average export instead.
    nodes = this.Workspace.GrandAveragesTree.allNodes();
    if isempty(nodes)
        % LEGACY-JAVA-GUI: msgbox, see the note near onListEvents.
        msgbox(['There are no Grand Averages to export yet. Use ' ...
            '"Define Grand Average..." first.'], 'Nothing to export');
        return;
    end

    exportsDir = this.Workspace.ExportsDirectory;
    if isempty(exportsDir) || ~isfolder(exportsDir)
        exportsDir = pwd;
    end
    [fileName, pathName] = uiputfile('*.csv', 'Export Grand Averages', ...
        fullfile(exportsDir, 'grand_averages.csv'));
    if isequal(fileName, 0)
        return; % cancelled
    end
    targetFile = fullfile(pathName, fileName);

    this.MainFigure.Pointer = 'watch';
    restorePointer = onCleanup(@() set(this.MainFigure, 'Pointer', 'arrow'));
    try
        exportGrandAveragesCSV(nodes, targetFile);
    catch err
        % LEGACY-JAVA-GUI: warndlg, see the note near onListEvents.
        warndlg(err.message, 'Could not export Grand Averages');
        return;
    end
    % LEGACY-JAVA-GUI: msgbox, see the note near onListEvents.
    msgbox(sprintf('Exported %d Grand Average(s) to:\n%s', numel(nodes), targetFile), ...
        'Export complete');
end
