function onExportFieldTripScript(this)
%ONEXPORTFIELDTRIPSCRIPT  Ribbon action (Export/Report tab): write the
%   workspace's analysis out as a FieldTrip script.
%
%   Walks every root recording in the Data & Analyses tree, as
%   onExportAnalysisScript does, but reads each step's result as well as its
%   settings: a FieldTrip script repeats the steps FieldTrip can do and
%   reads back the decisions it cannot make (which trials DefineBins cut,
%   which trials were rejected), and those are in the results
%   (fieldtripStepContext, gathered by collectFieldTripSubjects). The script
%   and the files it reads are written side by side.
%
%   It first asks for the mode (see EXPORTFIELDTRIPSCRIPT): reproduce
%   Alakazam's results, every choice read back, or re-run in FieldTrip,
%   which makes the choices it has a method for itself.
%
%   See also COLLECTFIELDTRIPSUBJECTS, EXPORTFIELDTRIPSCRIPT, ONEXPORTANALYSISSCRIPT.
    choice = uiconfirm(this.MainFigure, sprintf(['Reproduce Alakazam''s results: every choice ' ...
        'FieldTrip cannot make (the trials, the rejections, the ICA components) is read back as ' ...
        'Alakazam made it, so the script gives Alakazam''s numbers.

Re-run in FieldTrip: ' ...
        'FieldTrip makes the choices it has a method for itself, with the settings closest to ' ...
        'Alakazam''s (an ICA step is its own decomposition, its components matched to Alakazam''s ' ...
        'by topography), so its results come close to Alakazam''s without being them.']), ...
        'Export as FieldTrip', 'Options', {'Reproduce Alakazam''s results', 'Re-run in FieldTrip', ...
        'Cancel'}, 'DefaultOption', 1, 'CancelOption', 3);
    switch choice
        case 'Re-run in FieldTrip'
            mode = 'rerun';
        case 'Reproduce Alakazam''s results'
            mode = 'reproduce';
        otherwise
            return;
    end
    [restoreBusy, setBusy] = beginBusy(this.MainFigure, 'Collecting the analysis...');

    try
        [subjects, grandAverages] = this.collectFieldTripSubjects(setBusy);
    catch ME
        clear restoreBusy;
        % LEGACY-JAVA-GUI: warndlg, see the note near onListEvents.
        warndlg(sprintf('I wasn''t able to read the analysis: %s', ME.message), ...
            'Could not export the analysis');
        return;
    end
    if isempty(subjects)
        clear restoreBusy;
        % LEGACY-JAVA-GUI: msgbox, see the note near onListEvents.
        msgbox(['There is no analysis to export yet: no recording in this workspace has ' ...
            'had a transformation run on it. Would you process at least one first?'], ...
            'Nothing to export');
        return;
    end

    setBusy('Writing the script...');
    try
        [code, sidecars] = exportFieldTripScript(subjects, struct('title', 'This analysis', ...
            'grandAverages', grandAverages, 'mode', mode));
    catch ME
        clear restoreBusy;
        % LEGACY-JAVA-GUI: warndlg, see the note near onListEvents.
        warndlg(sprintf('I wasn''t able to build the script: %s', ME.message), ...
            'Could not export the analysis');
        return;
    end

    exportsDir = this.Workspace.ExportsDirectory;
    if isempty(exportsDir) || ~isfolder(exportsDir)
        exportsDir = pwd;
    end
    clear restoreBusy;   % the save dialog must not open behind the indicator
    [fileName, pathName] = uiputfile({'*.m', 'MATLAB script (*.m)'}, ...
        'Export analysis as a FieldTrip script', fullfile(exportsDir, sprintf('alakazam_fieldtrip_%s.m', mode)));
    if isequal(fileName, 0)
        return;
    end

    target = fullfile(pathName, fileName);
    try
        writeExportSidecars(pathName, [struct('name', fileName, 'content', code), sidecars]);
    catch ME
        warndlg(ME.message, 'Could not save');
        return;
    end

    untranslated = numel(regexp(code, '% NOT TRANSLATED\.'));
    note = '';
    if untranslated > 0
        note = sprintf(['\n\n%d step(s) have no FieldTrip counterpart and are marked NOT ' ...
            'TRANSLATED in it: from those on, its results differ from Alakazam''s.'], untranslated);
    end
    % LEGACY-JAVA-GUI: msgbox, see the note near onListEvents.
    msgbox(sprintf(['Wrote the analysis of %d recording(s) as a FieldTrip script to:\n\n%s\n\n' ...
        'Its header says how faithful each step is. The files it reads (%d: tables of ' ...
        'trials, ICA decompositions) are beside it.%s'], numel(subjects), target, ...
        numel(sidecars), note), 'Analysis exported');
end
