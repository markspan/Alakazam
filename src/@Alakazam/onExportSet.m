function onExportSet(this)
%ONEXPORTSET  Context-menu callback: export the selected dataset as a plain
%   EEGLAB .set file (pop_saveset), so it can be opened in vanilla EEGLAB or
%   handed to a colleague without Alakazam installed. Unlike Export as
%   ERPset (Averaged data only), this works on any real dataset node --
%   continuous, epoched or averaged -- since a .set file is EEGLAB's own
%   native format for all three; the menu item is disabled only for a report
%   node (see WorkSpaceTree's own canApplyTemplate gating, reused here for
%   the same reason: a rendered report's EEG has none of the real fields a
%   normal dataset carries).
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
        EEG = ensureEventEpochField(EEG);
        pop_saveset(EEG, 'filename', fileName, 'filepath', pathName);
    catch err
        uialert(this.MainFigure, err.message, 'Could not export .set');
        return;
    end

    uialert(this.MainFigure, sprintf('All done: "%s" has been exported to:\n%s', ...
        char(node.Name), fullfile(pathName, fileName)), 'Export complete', 'Icon', 'success');
end

function EEG = ensureEventEpochField(EEG)
%ENSUREEVENTEPOCHFIELD  EEGLAB requires every event to carry a valid
%   .epoch (which trial it belongs to) once EEG.trials > 1 -- eeg_checkset
%   errors "the event info structure does not contain an 'epoch' field"
%   otherwise, and pop_saveset calls eeg_checkset internally. Alakazam's
%   own epoching (DefineBins/cutEpochs) never needed that field for
%   anything it does itself, so it is derived here, at the one place that
%   actually requires it, rather than trusted to already be there --
%   correct for a dataset epoched before this was even discovered as a
%   gap, not just one epoched after (eeg_checkset's own 'eventconsistency'
%   step, called below, only ever cleans up an EXISTING .epoch field; it
%   does not create one from scratch, so it cannot fix this on its own).
%   EEG.epoch(k).event already names the one anchor event each trial k was
%   cut around (see cutEpochs.m); every other event -- one that matched no
%   bin, so belongs to no kept trial -- is left without a valid epoch
%   number, which 'eventconsistency' then prunes.
    if ~isfield(EEG, 'trials') || EEG.trials <= 1 ...
            || ~isfield(EEG, 'epoch') || isempty(EEG.epoch) || ~isfield(EEG.epoch, 'event')
        return;
    end
    for k = 1:numel(EEG.epoch)
        ei = EEG.epoch(k).event;
        if ~isempty(ei) && isscalar(ei) && ei >= 1 && ei <= numel(EEG.event)
            EEG.event(ei).epoch = k;
        end
    end
    EEG = eeg_checkset(EEG, 'eventconsistency');
end
