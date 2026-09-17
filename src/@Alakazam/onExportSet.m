function onExportSet(this)
%ONEXPORTSET  Context-menu callback: export the selected dataset as a plain
%   EEGLAB .set file (pop_saveset), so it can be opened in vanilla EEGLAB or
%   handed to a colleague without Alakazam installed. Unlike Export as
%   ERPset (Averaged data only), this works on any real dataset node --
%   continuous, epoched or averaged -- since a .set file is EEGLAB's own
%   native format for all three; the menu item is disabled only for a report
%   node (see WorkSpaceTree's own canApplyTemplate gating, reused here for
%   the same reason: a rendered report's EEG has none of the real fields a
%   normal dataset carries). A dataset carrying Alakazam's own bin tagging
%   (EEG.bindesc, from DefineBins) is converted to ERPLAB's own EVENTLIST
%   first -- see alakazamBinsToEventList -- so the exported file is usable
%   by ERPLAB's own bin-aware tools directly, not merely loadable by them.
    node = this.Workspace.ActiveTree.SelectedNodes;
    if isempty(node)
        return; % nothing selected
    end

    EEG = this.loadNodeEEG(node.UserData, 'export this dataset as a .set file');
    if isempty(EEG)
        return;
    end

    exportsDir = this.Workspace.ExportsDirectory;
    if isempty(exportsDir) || ~isfolder(exportsDir)
        exportsDir = pwd;
    end
    [fileName, pathName] = uiputfile('*.set', 'Export as EEGLAB .set', ...
        fullfile(exportsDir, [char(node.Name) '.set']));
    if isequal(fileName, 0)
        return; % cancelled
    end

    restoreBusy = beginBusy(this.MainFigure, 'Exporting .set...');
    try
        % Order matters: bin conversion first (reads EEG.event(i).bini as
        % Alakazam left it), then the epoched-data event-latency rewrite
        % (an anchor's .latency must already be EEGLAB-correct before
        % ensureEventEpochField's own eeg_checkset call, which otherwise
        % prunes it as "out of bounds" -- see rewriteEpochedEventLatencies'
        % own header comment).
        EEG = alakazamBinsToEventList(EEG);
        EEG = rewriteEpochedEventLatencies(EEG);
        EEG = ensureEventEpochField(EEG);
        pop_saveset(EEG, 'filename', fileName, 'filepath', pathName);
    catch err
        uialert(this.MainFigure, err.message, 'Could not export .set');
        return;
    end

    uialert(this.MainFigure, sprintf('All done: "%s" has been exported to:\n%s', ...
        char(node.Name), fullfile(pathName, fileName)), 'Export complete', 'Icon', 'success');
end
