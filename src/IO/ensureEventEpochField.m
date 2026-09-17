function EEG = ensureEventEpochField(EEG)
%ENSUREEVENTEPOCHFIELD  EEGLAB requires every event to carry a valid
%   .epoch (which trial it belongs to) once EEG.trials > 1 -- eeg_checkset
%   errors "the event info structure does not contain an 'epoch' field"
%   otherwise, and pop_saveset calls eeg_checkset internally. Alakazam's
%   own epoching (DefineBins/cutEpochs) never needed that field for
%   anything it does itself, so it is derived here, at the one place that
%   actually requires it, rather than trusted to already be there --
%   correct for a dataset epoched before this was even discovered as a
%   gap, not just one epoched after. Set explicitly rather than left to
%   eeg_checkset's own 'eventconsistency' step to derive from an anchor's
%   (by-then EEGLAB-correct) latency alone -- confirmed directly that it
%   CAN do that once rewriteEpochedEventLatencies has run first, so this
%   loop is defence in depth against a version/behaviour that cannot,
%   documented explicitly rather than left implicit.
%   EEG.epoch(k).event already names the one anchor event each trial k was
%   cut around (see cutEpochs.m); every other event -- one that matched no
%   bin, so belongs to no kept trial -- is left without a valid epoch
%   number, which 'eventconsistency' then prunes.
%
%   Call rewriteEpochedEventLatencies first (see onExportSet.m): this
%   function's own eeg_checkset call also prunes an anchor event whose
%   .latency has not yet been rewritten into EEGLAB's per-epoch-
%   concatenated numbering, for the same "out of bounds" reason.
%
%   A no-op (returns EEG unchanged) on continuous data (trials <= 1) or
%   when there is no per-epoch anchor info to work from.
%
%   See also ONEXPORTSET, REWRITEEPOCHEDEVENTLATENCIES.
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
