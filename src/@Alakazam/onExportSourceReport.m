function onExportSourceReport(this)
%ONEXPORTSOURCEREPORT  Ribbon action (Export/Report tab): export the Measure
%   results taken on PARCELLATED datasets and render a Quarto report on
%   them, alongside the ERP/Spectral/Cluster/Data-quality reports.
%
%   Same "CSV export + generateXReport + renderQuartoReport +
%   persistReportNode" flow the other report actions use. The CSV is the
%   ordinary measurements export: a parcellated dataset's channels ARE its
%   regions, so exportMeasurementsCSV already writes a region name in the
%   channel column with no special case anywhere.
%
%   ITS OWN BUTTON, deliberately. Source-region results and scalp-channel
%   results answer different questions with different caveats, and mixing
%   them into one document would put a "channel P7" row and a "left middle
%   temporal gyrus" row in the same table as though they were the same kind
%   of claim. They are not: one is measured, the other is modelled.
%
%   See also GENERATESOURCEREPORT, PARCELLATE, EXPORTMEASUREMENTSCSV,
%   ALAKAZAM.ONEXPORTDATAQUALITY.
    [restoreBusy, setBusy] = beginBusy(this.MainFigure, 'Gathering source measurements...');

    entries = this.collectEntriesWithField('measurements');
    entries = entries(arrayfun(@(e) isParcellated(e.EEG), entries));

    if isempty(entries)
        clear restoreBusy;   % dismiss the spinner BEFORE the dialog, not behind it
        % LEGACY-JAVA-GUI: msgbox, see the note near onListEvents.
        msgbox(['There are no source measurements to report on yet. A source report is ' ...
            'built from datasets that have been run through Parcellate (which turns an ' ...
            'averaged ERP into anatomical region time courses) and then measured with ' ...
            'ERP Measure. Run those two, in that order, on at least one subject first.'], ...
            'Nothing to report');
        return;
    end

    restoreDir = this.enterRepoRoot(); %#ok<NASGU>
    try
        setBusy(sprintf('Writing source measurements for %d dataset(s)...', numel(entries)));
        reportsDir = this.Workspace.reportsDirectory();
        if ~exist(reportsDir, 'dir')
            mkdir(reportsDir);
        end
        stamp = datetime('now');
        stem = fullfile(reportsDir, ['source_regions_' char(string(stamp, 'yyyyMMdd_HHmmss'))]);

        csvFile = [stem '.csv'];
        exportMeasurementsCSV(entries, csvFile);
        [~, csvName] = fileparts(csvFile);

        % Generated before the .qmd is opened, for the same reason the other
        % report actions do it in that order: opening (and so truncating)
        % the file first would leave an empty, unexplained .qmd behind if
        % generation throws.
        qmdText = generateSourceReport(entries, [csvName '.csv']);
        qmdFile = [stem '.qmd'];
        writeQmdFile(qmdFile, qmdText, 'Alakazam:onExportSourceReport');

        setBusy('Rendering the report (quarto + R). The first run also installs R packages, which can take a minute.');
        [htmlFile, renderError] = renderQuartoReport(qmdFile);

        if ~isempty(htmlFile)
            setBusy('Adding the report to the workspace...');
            reportLabel = sprintf('Source Regions (%d datasets) - %s', ...
                numel(entries), string(stamp, 'dd-MMM-yyyy HH:mm'));
            this.persistReportNode(reportLabel, htmlFile, qmdFile);
            this.Plotter.plotCurrent();
        else
            clear restoreBusy;
            % LEGACY-JAVA-GUI: warndlg, see the note near onListEvents.
            warndlg(sprintf(['The source report (.qmd) was written to the Reports folder but ' ...
                'could not be rendered automatically: %s\n\nRender it yourself with:\nquarto render "%s"'], ...
                renderError, qmdFile), 'Report not rendered');
        end
    catch ME
        clear restoreBusy;
        % LEGACY-JAVA-GUI: warndlg, see the note near onListEvents.
        warndlg(sprintf('I wasn''t able to build the source report: %s', ME.message), ...
            'Could not generate report');
    end
end

% ======================================================================= %
function tf = isParcellated(EEG)
%ISPARCELLATED  Whether this dataset's channels are regions rather than
%   electrodes. Flagged by Parcellate itself rather than guessed at from
%   the channel names: an analyst is perfectly entitled to name a real
%   electrode something that looks like a region, and a heuristic that got
%   it wrong would put modelled numbers in a measured report.
    tf = isstruct(EEG) && isfield(EEG, 'isParcellated') && ...
        ~isempty(EEG.isParcellated) && EEG.isParcellated;
end
