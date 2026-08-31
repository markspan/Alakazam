function onExportMeasurements(this)
%ONEXPORTMEASUREMENTS  Ribbon callback (Export/Report tab): export
%   every Measure result in the workspace -- in EITHER tree, a
%   subject's own branch or a Grand Average's -- to one long-
%   format, R-compatible CSV (see exportMeasurementsCSV). Same
%   "one button, everything I've computed" bulk-export idea as
%   onExportGrandAverages.
%
%   For a Data & Analyses node, the exported "subject" is its own root
%   ancestor's name (Workspace.Tree.rootOf, built for Apply to All Raw
%   Files/Save Template) -- the raw recording the branch descends from,
%   not the Measure node's own generic "Measure..." tree label; a Grand
%   Average node uses its own name directly (it has no root/raw-file
%   ancestor the same way).
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

    [restoreBusy, setBusy] = beginBusy(this.MainFigure, 'Exporting measurements...');
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
        [~, stem] = fileparts(fileName);
        reportsDir = this.Workspace.reportsDirectory();
        if ~exist(reportsDir, 'dir')
            mkdir(reportsDir);
        end
        % A timestamp, not just STEM, in both the file name and the tree
        % label below: reports live in their own fixed ReportsDirectory
        % now rather than next to the CSV, so two exports named the same
        % (e.g. the dialog's own remembered "measurements.csv" default)
        % would otherwise silently overwrite each other's report with no
        % warning -- unlike the CSV itself, which still gets uiputfile's
        % own overwrite prompt.
        stamp = datetime('now');
        stampTxt = char(string(stamp, 'yyyyMMdd_HHmmss'));

        % The report's own read_csv() call resolves its CSV filename
        % relative to the .qmd's own folder (ReportsDirectory), not
        % TARGETFILE's -- copy the CSV in alongside it (under the same
        % timestamped stem, so it can never collide with a different
        % export's own copy) rather than pointing the report at a
        % relative "../" back to wherever the analyst happened to save
        % it: that path would break the moment the report is shared/
        % moved on its own, and would silently start reading a DIFFERENT
        % file's contents if a later export overwrote the same CSV name
        % in place. This keeps each report a fully self-contained
        % snapshot of the data it was actually built from.
        reportCsvName = [stem '_' stampTxt '.csv'];
        [copyOk, copyMsg] = copyfile(targetFile, fullfile(reportsDir, reportCsvName));
        if ~copyOk
            throw(MException('Alakazam:onExportMeasurements', ...
                'I wasn''t able to copy the CSV into the Reports folder: %s', copyMsg));
        end

        % Generate the report text FIRST, before touching the .qmd file:
        % opening (and so truncating) it before generateQuartoReport has
        % actually succeeded would leave an empty, unexplained .qmd
        % behind if it throws -- exactly what a silent catch below used
        % to produce, with no way to tell why.
        qmdText = generateQuartoReport(entries, reportCsvName);
        qmdFile = fullfile(reportsDir, [stem '_' stampTxt '.qmd']);
        writeQmdFile(qmdFile, qmdText, 'Alakazam:onExportMeasurements');

        % Best effort, same "must not lose what already succeeded" spirit
        % as this whole block: if quarto/R are not on this machine, or the
        % render itself fails, fall back to exactly the old behaviour
        % (just the .qmd, with the manual render command) rather than
        % losing the .qmd note entirely.
        % Re-labelled because this, not the CSV export the opening message
        % names, is the slow part: quarto shells out to R, and a first run
        % installs the report's own packages before rendering anything.
        setBusy('Rendering the report (quarto + R). The first run also installs R packages, which can take a minute.');
        [htmlFile, renderError] = renderQuartoReport(qmdFile);
        if ~isempty(htmlFile)
            reportLabel = sprintf('Report (%s) - %s', stem, string(stamp, 'dd-MMM-yyyy HH:mm'));
            this.persistReportNode(reportLabel, htmlFile, qmdFile);
            this.Plotter.plotCurrent();
            reportNote = sprintf(['\n\nA companion Quarto report was rendered automatically and saved to ' ...
                'the Reports folder: see "%s" in the Reports tree.'], reportLabel);
        else
            reportNote = sprintf(['\n\nA companion Quarto report (tidyverse + ggplot2 + rstatix + gt, ' ...
                'tailored to your bin design) was written to the Reports folder:\n%s\n\n' ...
                '(Not rendered automatically: %s)\n\nRender it yourself with:\n' ...
                'quarto render "%s"'], qmdFile, renderError, qmdFile);
        end
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
