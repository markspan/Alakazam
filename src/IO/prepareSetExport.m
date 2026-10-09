function EEG = prepareSetExport(EEG)
%PREPARESETEXPORT  A dataset as EEGLAB expects one, ready for pop_saveset.
%   EEG = prepareSetExport(EEG) is what Export as .set (onExportSet) does to
%   a node's dataset before saving it, so the file opens in EEGLAB, and in
%   ERPLAB's bin-aware tools, as one of their own:
%     1. Alakazam's bins become ERPLAB's EVENTLIST (alakazamBinsToEventList),
%        read before anything else touches the events;
%     2. an epoched dataset's event latencies move onto EEGLAB's
%        concatenated timeline (rewriteEpochedEventLatencies), before
%        eeg_checkset would prune them as out of bounds;
%     3. every event gets its .epoch field (ensureEventEpochField);
%     4. a continuous recording's time axis goes back to EEGLAB's
%        milliseconds (eeglabTimes). Alakazam keeps it in seconds (see
%        loadSETFile), and eeg_checkset only rebuilds EEG.times when its
%        length is wrong, so a seconds axis was saved as it was and read in
%        EEGLAB as milliseconds a thousand times too short. Epoched and
%        averaged data are in milliseconds in both and are left as they are.
%
%   See also ONEXPORTSET, ALAKAZAMBINSTOEVENTLIST,
%   REWRITEEPOCHEDEVENTLATENCIES, ENSUREEVENTEPOCHFIELD.
    EEG = alakazamBinsToEventList(EEG);
    EEG = rewriteEpochedEventLatencies(EEG);
    EEG = ensureEventEpochField(EEG);
    EEG = eeglabTimes(EEG);
end

% ======================================================================= %
function EEG = eeglabTimes(EEG)
%EEGLABTIMES  A continuous recording's EEG.times in EEGLAB's milliseconds,
%   by eeg_checkset's own formula, linspace(xmin*1000, xmax*1000, pnts)
%   (xmin and xmax are in seconds in both conventions). Its DataFormat says
%   whether it is continuous; only a dataset without one is judged by its
%   shape, since a one-bin average has the shape of a continuous recording.
    format = TransTools.FieldOr(EEG, 'DataFormat', '');
    if isempty(format)
        format = inferDataFormat(EEG);
    end
    if ~strcmpi(char(string(format)), 'CONTINUOUS')
        return;
    end
    EEG.times = linspace(EEG.xmin * 1000, EEG.xmax * 1000, EEG.pnts);
end
