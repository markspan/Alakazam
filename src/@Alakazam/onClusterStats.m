function onClusterStats(this)
%ONCLUSTERSTATS  Ribbon action (Export/Report tab): cluster-based
%   permutation testing across the whole scalp and epoch at once (see
%   ClusterStats.m) -- gathers candidate subjects (the same ERP-kind
%   Averaged datasets Grand Average itself lists), opens
%   ClusterStatsDialog for the contrast/options, runs the test, shows
%   ClusterStatsResultDialog for an immediate on-screen glance, then
%   writes and renders a companion Quarto report (same "CSV export +
%   generateXReport + renderQuartoReport + persistReportNode" flow
%   onExportMeasurements/onExportSpectral already use) with plots of
%   where/when each cluster sits.
    [candidateFiles, candidateLabels, candidateKinds] = this.findGrandAverageCandidates();
    erpMask = strcmp(candidateKinds, 'ERP');
    candidateFiles  = candidateFiles(erpMask);
    candidateLabels = candidateLabels(erpMask);

    if numel(candidateFiles) < 2
        % LEGACY-JAVA-GUI: msgbox, see the note near onListEvents.
        msgbox(['A cluster test needs at least two Averaged ERP datasets, and fewer ' ...
                'than two were found in this workspace. Run Average on more subjects first.'], ...
                'Not enough subjects');
        return;
    end

    candidateBins   = this.candidateBinLabels(candidateFiles);
    candidateGroups = this.candidateGroupLabels(candidateFiles);

    spec = ClusterStatsDialog(candidateFiles, candidateLabels, candidateBins, candidateGroups);
    if isempty(spec)
        return; % cancelled
    end

    restoreDir = this.enterRepoRoot();
    [restoreBusy, setBusy] = beginBusy(this.MainFigure, 'Running cluster permutation test...');
    try
        summary = ClusterStats(spec.sourceFiles, spec.contrast, spec.opts);
    catch err
        % LEGACY-JAVA-GUI: warndlg, see the note near onListEvents.
        warndlg(err.message, 'Cluster test failed');
        return;
    end

    label = contrastLabel(spec.contrast);
    ClusterStatsResultDialog(summary, label);

    % Best effort, same "must not lose what already succeeded" spirit as
    % onExportMeasurements' own companion-report step: the test itself
    % already ran and is showing on screen above, so a report-generation
    % failure here is surfaced, not silently swallowed, but must not look
    % like the whole action failed.
    try
        reportsDir = this.Workspace.reportsDirectory();
        if ~exist(reportsDir, 'dir')
            mkdir(reportsDir);
        end
        stamp = datetime('now');
        stampTxt = char(string(stamp, 'yyyyMMdd_HHmmss'));
        stem = fullfile(reportsDir, ['cluster_stats_' stampTxt]);

        [statCsv, waveformCsv, outlineCsv] = exportClusterStatsCSVs(summary, stem);
        [~, statName]     = fileparts(statCsv);
        [~, waveformName] = fileparts(waveformCsv);
        [~, outlineName]  = fileparts(outlineCsv);

        qmdText = generateClusterStatsReport(summary, [statName '.csv'], ...
            [waveformName '.csv'], [outlineName '.csv']);
        qmdFile = [stem '.qmd'];
        fid = fopen(qmdFile, 'w');
        if fid < 0
            throw(MException('Alakazam:onClusterStats', 'I''m sorry, but I wasn''t able to open "%s" for writing.', qmdFile));
        end
        closeFile = onCleanup(@() fclose(fid));
        fwrite(fid, qmdText, 'char');
        clear closeFile;

        % See onExportMeasurements' own note: by this point the test itself
        % has long finished (its result is already on screen above), so the
        % opening message would otherwise sit there through the render.
        setBusy('Rendering the report (quarto + R). The first run also installs R packages, which can take a minute.');
        [htmlFile, renderError] = renderQuartoReport(qmdFile);
        if ~isempty(htmlFile)
            reportLabel = sprintf('Cluster Stats (%s) - %s', label, string(stamp, 'dd-MMM-yyyy HH:mm'));
            this.persistReportNode(reportLabel, htmlFile, qmdFile);
            this.Plotter.plotCurrent();
        else
            % LEGACY-JAVA-GUI: warndlg, see the note near onListEvents.
            warndlg(sprintf(['The cluster report (.qmd) was written to the Reports folder but could ' ...
                'not be rendered automatically: %s\n\nRender it yourself with:\nquarto render "%s"'], ...
                renderError, qmdFile), 'Report not rendered');
        end
    catch ME
        % LEGACY-JAVA-GUI: warndlg, see the note near onListEvents.
        warndlg(sprintf('The cluster test result above is valid, but the companion report could not be generated: %s', ...
            ME.message), 'Could not generate report');
    end
end

function label = contrastLabel(contrast)
    switch contrast.mode
        case 'vsZero'
            label = sprintf('"%s" tested against zero (within subjects)', contrast.bin);
        case 'paired'
            label = sprintf('"%s" vs. "%s" (within subjects, paired)', contrast.binA, contrast.binB);
        case 'independent'
            label = sprintf('"%s" between two groups (independent samples)', contrast.bin);
    end
end
