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

    % Write a companion Quarto report (tidyverse + ggplot2 + rstatix + gt)
    % next to the CSV, generated to suit THIS export's own bin design (see
    % generateQuartoReport's own header: descriptive/paired/RM-ANOVA/one-
    % sample sections are chosen per window from EEG.bindesc, not
    % re-discovered at R runtime): rendering it (quarto render, self-
    % contained HTML) produces a short, APA-styled report with narrative
    % results prose, APA-formatted tables and embedded plots, not just a
    % console dump. Best effort: a failure here must not lose the CSV the
    % user just exported.
    reportNote = '';
    try
        % Generate the report text FIRST, before touching the file: opening
        % (and so truncating) the target file before generateQuartoReport
        % has actually succeeded would leave an empty, unexplained .qmd
        % behind if it throws -- exactly what a silent catch below used to
        % produce, with no way to tell why.
        qmdText = generateQuartoReport(entries, fileName);
        [~, stem] = fileparts(fileName);
        qmdFile = fullfile(pathName, [stem '.qmd']);
        fid = fopen(qmdFile, 'w');
        if fid < 0
            throw(MException('Alakazam:onExportMeasurements', 'Could not open "%s" for writing.', qmdFile));
        end
        closeFile = onCleanup(@() fclose(fid));
        fwrite(fid, qmdText, 'char');
        reportNote = sprintf(['\n\nA companion Quarto report (tidyverse + ggplot2 + rstatix + gt, ' ...
            'tailored to your bin design) was written next to it:\n%s\n\nRender it with:\n' ...
            'quarto render "%s"'], qmdFile, qmdFile);
    catch ME
        % Surfaced in the completion dialog below, not swallowed: a bare
        % `catch; reportNote = '';` here used to hide the real reason
        % (and, combined with opening the file too early, leave an empty
        % .qmd with no explanation at all).
        reportNote = sprintf('\n\n(Could not generate the companion Quarto report: %s)', ME.message);
    end

    % LEGACY-JAVA-GUI: msgbox, see the note near onListEvents.
    msgbox(sprintf('Exported %d dataset(s)'' Measure results to:\n%s%s', numel(entries), targetFile, reportNote), ...
        'Export complete');
end
