function onExportSpectral(this)
%ONEXPORTSPECTRAL  Ribbon callback (Measurements tab): export every
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

    this.MainFigure.Pointer = 'watch';
    restorePointer = onCleanup(@() set(this.MainFigure, 'Pointer', 'arrow'));
    try
        exportSpectralCSV(entries, targetFile);
    catch ME
        this.showTransformationError('Export Spectral Measures', ME);
        return;
    end
    msgbox(sprintf('Exported %d dataset(s) to %s', numel(entries), targetFile), ...
        'Export complete');
end
