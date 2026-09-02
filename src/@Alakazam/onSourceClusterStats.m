function onSourceClusterStats(this)
%ONSOURCECLUSTERSTATS  Ribbon action (Export/Report tab): cluster-based
%   permutation testing over the cortical sheet (see SourceClusterStats) --
%   gathers candidate subjects (the same ERP-kind Averaged datasets Grand
%   Average itself lists), opens ClusterStatsDialog in its 'source' mode for
%   the contrast and the inverse settings, runs the test, renders the
%   per-cluster figures, shows SourceClusterStatsResultDialog for an
%   immediate glance, then writes and renders the companion Quarto report.
%
%   THE SAME SHAPE AS onClusterStats, with two deliberate differences.
%   There is no CSV export: the scalp report hands its per-subject table to
%   an R chunk that redoes the test, and there is no equivalent table here
%   (see generateSourceClusterStatsReport's own header on why the source
%   report is markdown only). And the figures are rendered in MATLAB before
%   the report is assembled, because the report links to them rather than
%   drawing them itself.
    [candidateFiles, candidateLabels, candidateKinds] = this.findGrandAverageCandidates();
    erpMask = strcmp(candidateKinds, 'ERP');
    candidateFiles  = candidateFiles(erpMask);
    candidateLabels = candidateLabels(erpMask);

    if numel(candidateFiles) < 2
        % LEGACY-JAVA-GUI: msgbox, see the note near onListEvents.
        msgbox(['A source cluster test needs at least two Averaged ERP datasets, and ' ...
                'fewer than two were found in this workspace. Run Average on more ' ...
                'subjects first.' this.unrootedAveragesHint()], ...
                'Not enough subjects');
        return;
    end

    candidateBins   = this.candidateBinLabels(candidateFiles);
    candidateGroups = this.candidateGroupLabels(candidateFiles);

    % The epoch is read here, not in the dialog, so the time window can
    % default to the data rather than to a number someone once typed.
    spec = ClusterStatsDialog(candidateFiles, candidateLabels, candidateBins, ...
        candidateGroups, 'source', this.candidateEpochMs(candidateFiles));
    if isempty(spec)
        return; % cancelled
    end

    % Both are onCleanup handles whose whole job is to stay alive until this
    % function returns, so neither is "unused" and neither can become a ~:
    % dropping restoreBusy would tear the busy overlay down immediately.
    restoreDir = this.enterRepoRoot(); %#ok<NASGU>
    [restoreBusy, setBusy] = beginBusy(this.MainFigure, ...
        'Inverting each subject onto the cortical sheet...'); %#ok<ASGLU>
    try
        summary = SourceClusterStats(spec.sourceFiles, spec.contrast, spec.opts);
    catch err
        % LEGACY-JAVA-GUI: warndlg, see the note near onListEvents.
        warndlg(err.message, 'Source cluster test failed');
        return;
    end

    label = contrastLabel(spec.contrast);

    % Rendered before the glance dialog, not after: the dialog names each
    % cluster by the anatomy generateSourceClusterAssets works out, and
    % recomputing that here would repeat an atlas lookup per cluster.
    setBusy('Rendering the cluster figures...');
    reportsDir = this.Workspace.reportsDirectory();
    stamp = datetime('now');
    stem = fullfile(reportsDir, ['source_cluster_stats_' char(string(stamp, 'yyyyMMdd_HHmmss'))]);
    assets = [];
    try
        if ~exist(reportsDir, 'dir')
            mkdir(reportsDir);
        end
        assets = generateSourceClusterAssets(summary, [stem '_images']);
    catch ME
        % Surfaced, not swallowed: the test itself is valid and is about to
        % be shown, so a failure to draw must not read as a failed analysis.
        % LEGACY-JAVA-GUI: warndlg, see the note near onListEvents.
        warndlg(sprintf(['The test above is valid, but its figures could not be ' ...
            'rendered: %s'], ME.message), 'Could not render cluster figures');
    end

    SourceClusterStatsResultDialog(summary, assets, label);

    % Best effort from here, the same "must not lose what already succeeded"
    % spirit as onClusterStats' own companion-report step.
    try
        qmdFile = [stem '.qmd'];
        writeQmdFile(qmdFile, generateSourceClusterStatsReport(summary, assets), ...
            'Alakazam:onSourceClusterStats');

        setBusy('Rendering the report (quarto). The first run can take a minute.');
        [htmlFile, renderError] = renderQuartoReport(qmdFile);
        if ~isempty(htmlFile)
            reportLabel = sprintf('Source Cluster Stats (%s) - %s', label, ...
                string(stamp, 'dd-MMM-yyyy HH:mm'));
            this.persistReportNode(reportLabel, htmlFile, qmdFile);
            this.Plotter.plotCurrent();
        else
            % LEGACY-JAVA-GUI: warndlg, see the note near onListEvents.
            warndlg(sprintf(['The source cluster report (.qmd) was written to the Reports ' ...
                'folder but could not be rendered automatically: %s\n\nRender it yourself ' ...
                'with:\nquarto render "%s"'], renderError, qmdFile), 'Report not rendered');
        end
    catch ME
        % LEGACY-JAVA-GUI: warndlg, see the note near onListEvents.
        warndlg(sprintf(['The source cluster result above is valid, but the companion ' ...
            'report could not be generated: %s'], ME.message), 'Could not generate report');
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
