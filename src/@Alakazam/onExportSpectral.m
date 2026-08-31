function onExportSpectral(this)
%ONEXPORTSPECTRAL  Ribbon callback (Export/Report tab): export every
%   SpectralMeasure result in the workspace -- in either tree, a subject's
%   branch or a Grand Average's -- to one long-format, R-compatible CSV (see
%   exportSpectralCSV). The frequency-domain sibling of onExportMeasurements.
    entries = this.collectSpectralEntries();
    if isempty(entries)
        % LEGACY-JAVA-GUI: msgbox, see the note near onListEvents.
        msgbox(['There are no SpectralMeasure results to export yet. Run the ' ...
            'SpectralMeasure transformation on an epoched dataset first.'], 'Nothing to export');
        return;
    end

    exportsDir = this.Workspace.ExportsDirectory;
    if isempty(exportsDir) || ~isfolder(exportsDir)
        exportsDir = pwd;
    end
    [fileName, pathName] = uiputfile('*.csv', 'Export Spectral Measures', ...
        fullfile(exportsDir, 'spectral.csv'));
    if isequal(fileName, 0)
        return; % cancelled
    end
    targetFile = fullfile(pathName, fileName);

    [restoreBusy, setBusy] = beginBusy(this.MainFigure, 'Exporting spectral measures...');
    try
        exportSpectralCSV(entries, targetFile);
    catch err
        % LEGACY-JAVA-GUI: warndlg, see the note near onListEvents. Plain
        % warndlg(err.message, ...), not showTransformationError -- that
        % helper is built for a single-dataset transformation failure (its
        % text talks about "the selected dataset"), which doesn't fit a
        % bulk, workspace-wide export with no one dataset involved; matches
        % onExportMeasurements.m/onExportGrandAverages.m/onExportErpset.m's
        % own error handling for the same kind of export.
        warndlg(err.message, 'Could not export Spectral Measures');
        return;
    end

    % Companion Quarto report, exactly like onExportMeasurements' own --
    % generateQuartoReport auto-detects a Spectral (EEG.spectralMeasures)
    % export from an ERP one, so this is the same call, same fallback
    % behaviour if quarto/R are not on this machine or the render itself
    % fails (see that function's own comments for the full reasoning).
    reportNote = '';
    try
        [~, stem] = fileparts(fileName);
        reportsDir = this.Workspace.reportsDirectory();
        if ~exist(reportsDir, 'dir')
            mkdir(reportsDir);
        end
        % See onExportMeasurements.m's own comment on this same pattern:
        % reports live in ReportsDirectory now, not next to the CSV, so
        % the timestamp keeps repeated exports of the same-named CSV from
        % overwriting each other's report.
        stamp = datetime('now');
        stampTxt = char(string(stamp, 'yyyyMMdd_HHmmss'));

        % The report's own read_csv() call resolves CSVFILENAME relative
        % to the .qmd's own folder (ReportsDirectory), not TARGETFILE's --
        % copy the CSV in alongside it (under the same timestamped stem,
        % so it can never collide with a different export's own copy)
        % rather than pointing the report at a relative "../" back to
        % wherever the analyst happened to save the CSV: that path would
        % break the moment the report is shared/moved on its own, and
        % would silently start reading a DIFFERENT file's contents if a
        % later export overwrote the same CSV name in place. This keeps
        % each report a fully self-contained snapshot of the data it was
        % actually built from.
        reportCsvName = [stem '_' stampTxt '.csv'];
        [copyOk, copyMsg] = copyfile(targetFile, fullfile(reportsDir, reportCsvName));
        if ~copyOk
            throw(MException('Alakazam:onExportSpectral', ...
                'Unfortunately, I wasn''t able to copy the CSV into the Reports folder: %s', copyMsg));
        end

        qmdText = generateQuartoReport(entries, reportCsvName);
        qmdFile = fullfile(reportsDir, [stem '_' stampTxt '.qmd']);
        writeQmdFile(qmdFile, qmdText, 'Alakazam:onExportSpectral');

        % See onExportMeasurements' own note: the render, not the CSV
        % export the opening message names, is the slow phase here.
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
        reportNote = sprintf('\n\n(Could not generate the companion Quarto report: %s)', ME.message);
    end

    msgbox(sprintf('Exported %d dataset(s) to %s%s', numel(entries), targetFile, reportNote), ...
        'Export complete');
end
