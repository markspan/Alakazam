function onExportMeasurements(this)
%ONEXPORTMEASUREMENTS  Ribbon callback (Measurements tab): export
%   every Measure result in the workspace -- in EITHER tree, a
%   subject's own branch or a Grand Average's -- to one long-
%   format, R-compatible CSV (see exportMeasurementsCSV). Same
%   "one button, everything I've computed" bulk-export idea as
%   onExportGrandAverages.
%
%   Loads every node in both trees to check for EEG.measurements
%   (a Measure result), same "load and check" pattern
%   findGrandAverageCandidates already uses. For a Data & Analyses
%   node, the exported "subject" is its own root ancestor's name
%   (Workspace.Tree.rootOf, built for Apply to All Raw Files/Save
%   Template) -- the raw recording the branch descends from, not
%   the Measure node's own generic "Measure..." tree label; a
%   Grand Average node uses its own name directly (it has no
%   root/raw-file ancestor the same way).
    entries = this.collectMeasurementEntries();
    if isempty(entries)
        % LEGACY-JAVA-GUI: msgbox, see the note near onListEvents.
        msgbox(['There are no Measure results to export yet. Run the Measure ' ...
            'transformation on an Average or Grand Average first.'], 'Nothing to export');
        return;
    end

    exportsDir = this.Workspace.ExportsDirectory;
    if isempty(exportsDir) || ~isfolder(exportsDir)
        exportsDir = pwd;
    end
    [fileName, pathName] = uiputfile('*.csv', 'Export ERP Measures', ...
        fullfile(exportsDir, 'measurements.csv'));
    if isequal(fileName, 0)
        return; % cancelled
    end
    targetFile = fullfile(pathName, fileName);

    this.MainFigure.Pointer = 'watch';
    restorePointer = onCleanup(@() set(this.MainFigure, 'Pointer', 'arrow'));
    try
        exportMeasurementsCSV(entries, targetFile);
    catch err
        % LEGACY-JAVA-GUI: warndlg, see the note near onListEvents.
        warndlg(err.message, 'Could not export Measurements');
        return;
    end

    % Write a companion R analysis script (tidyverse + ggplot2) next to the CSV
    % so the export is ready to run stats/plots on, not just a table. Best
    % effort: a failure here must not lose the CSV the user just exported.
    rNote = '';
    try
        [~, stem] = fileparts(fileName);
        rFile = fullfile(pathName, [stem '.R']);
        fid = fopen(rFile, 'w');
        if fid >= 0
            fwrite(fid, generateRScript(fileName), 'char');
            fclose(fid);
            rNote = sprintf(['\n\nA companion R analysis script (tidyverse + ggplot2, ' ...
                'repeated-measures ANOVA + pairwise tests + plots) was written next to it:\n%s'], rFile);
        end
    catch
        rNote = '';
    end

    % LEGACY-JAVA-GUI: msgbox, see the note near onListEvents.
    msgbox(sprintf('Exported %d dataset(s)'' Measure results to:\n%s%s', numel(entries), targetFile, rNote), ...
        'Export complete');
end
