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
%   and each recording's table of trials are written side by side.
%
%   See also COLLECTFIELDTRIPSUBJECTS, EXPORTFIELDTRIPSCRIPT, ONEXPORTANALYSISSCRIPT.
    [restoreBusy, setBusy] = beginBusy(this.MainFigure, 'Collecting the analysis...');

    try
        subjects = this.collectFieldTripSubjects(setBusy);
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
        [code, sidecars] = exportFieldTripScript(subjects, struct('title', 'This analysis'));
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
        'Export analysis as a FieldTrip script', fullfile(exportsDir, 'alakazam_fieldtrip.m'));
    if isequal(fileName, 0)
        return;
    end

    written = {fullfile(pathName, fileName)};
    contents = {code};
    for k = 1:numel(sidecars)
        written{end + 1} = fullfile(pathName, sidecars(k).name); %#ok<AGROW>
        contents{end + 1} = sidecars(k).content; %#ok<AGROW>
    end
    for k = 1:numel(written)
        fid = fopen(written{k}, 'w');
        if fid < 0
            warndlg(sprintf('I couldn''t open "%s" for writing.', written{k}), 'Could not save');
            return;
        end
        fwrite(fid, contents{k}, 'char');
        fclose(fid);
    end

    untranslated = numel(regexp(code, '% NOT TRANSLATED\.'));
    note = '';
    if untranslated > 0
        note = sprintf(['\n\n%d step(s) have no FieldTrip counterpart and are marked NOT ' ...
            'TRANSLATED in it: from those on, its results differ from Alakazam''s.'], untranslated);
    end
    % LEGACY-JAVA-GUI: msgbox, see the note near onListEvents.
    msgbox(sprintf(['Wrote the analysis of %d recording(s) as a FieldTrip script to:\n\n%s\n\n' ...
        'Its header says how faithful each step is. The tables of trials it reads (%d) are ' ...
        'beside it.%s'], numel(subjects), written{1}, numel(sidecars), note), 'Analysis exported');
end
