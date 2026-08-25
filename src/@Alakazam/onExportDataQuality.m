function onExportDataQuality(this)
%ONEXPORTDATAQUALITY  Ribbon action (Export/Report tab): assess per-subject
%   data quality across the whole workspace and write a Quarto report on it,
%   alongside the ERP/Spectral/Cluster reports.
%
%   Same "CSV export + generateXReport + renderQuartoReport +
%   persistReportNode" flow onExportMeasurements/onExportSpectral/
%   onClusterStats already use, with one difference: there is no
%   user-facing CSV to save. The two CSVs this writes are intermediate
%   inputs to the report rather than something an analyst would open
%   themselves (they are per-trial and per-channel diagnostics, not
%   measurements), so they go straight into the Reports folder next to the
%   .qmd, and there is no uiputfile step at all.
%
%   See also COLLECTDATAQUALITYENTRIES, DATAQUALITYMETRICS,
%   EXPORTDATAQUALITYCSVS, GENERATEDATAQUALITYREPORT.
    % Held for the WHOLE operation, not just the gathering step: rendering
    % the .qmd shells out to quarto and R, which is by far the slowest
    % phase here (and on a first run installs R packages, taking a minute
    % or more). Dropping the indicator before it left that entire stretch
    % with no feedback at all, which reads as the app having hung.
    [restoreBusy, setBusy] = beginBusy(this.MainFigure, 'Assessing data quality...');
    entries = this.collectDataQualityEntries();

    if isempty(entries)
        clear restoreBusy;   % dismiss the spinner BEFORE the dialog, not behind it
        % LEGACY-JAVA-GUI: msgbox, see the note near onListEvents.
        msgbox(['There is nothing to assess yet. A data-quality report is built from each ' ...
            'subject''s Average and the segmented data behind it, so run Average on at ' ...
            'least one segmented dataset first.'], 'Nothing to assess');
        return;
    end

    restoreDir = this.enterRepoRoot(); %#ok<NASGU>
    try
        setBusy(sprintf('Writing quality data for %d subject(s)...', numel(entries)));
        reportsDir = this.Workspace.reportsDirectory();
        if ~exist(reportsDir, 'dir')
            mkdir(reportsDir);
        end
        stamp = datetime('now');
        stampTxt = char(string(stamp, 'yyyyMMdd_HHmmss'));
        stem = fullfile(reportsDir, ['data_quality_' stampTxt]);

        [summaryCsv, trialCsv, smeCsv] = exportDataQualityCSVs(entries, stem);
        [~, summaryName] = fileparts(summaryCsv);
        [~, trialName]   = fileparts(trialCsv);
        [~, smeName]     = fileparts(smeCsv);

        % Generated before the .qmd is opened, for the same reason
        % onExportMeasurements does it in that order: opening (and so
        % truncating) the file first would leave an empty, unexplained
        % .qmd behind if generation throws.
        qmdText = generateDataQualityReport(entries, [summaryName '.csv'], ...
            [trialName '.csv'], [smeName '.csv']);
        qmdFile = [stem '.qmd'];
        fid = fopen(qmdFile, 'w');
        if fid < 0
            throw(MException('Alakazam:onExportDataQuality', ...
                'I couldn''t open "%s" for writing.', qmdFile));
        end
        closeFile = onCleanup(@() fclose(fid));
        fwrite(fid, qmdText, 'char');
        clear closeFile;   % close now: renderQuartoReport reads this file back next

        % The long one: quarto shells out to R, and on a first run R
        % installs the report's own packages before it can render anything.
        setBusy('Rendering the report (quarto + R). The first run also installs R packages, which can take a minute.');
        [htmlFile, renderError] = renderQuartoReport(qmdFile);

        if ~isempty(htmlFile)
            setBusy('Adding the report to the workspace...');
            reportLabel = sprintf('Data Quality (%d subjects) - %s', ...
                numel(entries), string(stamp, 'dd-MMM-yyyy HH:mm'));
            this.persistReportNode(reportLabel, htmlFile, qmdFile);
            this.Plotter.plotCurrent();
        else
            clear restoreBusy;
            % LEGACY-JAVA-GUI: warndlg, see the note near onListEvents.
            warndlg(sprintf(['The data-quality report (.qmd) was written to the Reports folder but ' ...
                'could not be rendered automatically: %s\n\nRender it yourself with:\nquarto render "%s"'], ...
                renderError, qmdFile), 'Report not rendered');
        end
    catch ME
        clear restoreBusy;
        % LEGACY-JAVA-GUI: warndlg, see the note near onListEvents.
        warndlg(sprintf('I wasn''t able to build the data-quality report: %s', ME.message), ...
            'Could not generate report');
    end
end
