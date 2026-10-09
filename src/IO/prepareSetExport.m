function EEG = prepareSetExport(EEG)
%PREPARESETEXPORT  A dataset as EEGLAB expects one, ready for pop_saveset.
%   EEG = prepareSetExport(EEG) is what Export as .set (onExportSet) does to
%   a node's dataset before saving it, so the file opens in EEGLAB, and in
%   ERPLAB's bin-aware tools, as one of their own. For a recording or its
%   trials:
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
%   AN AVERAGE IS SAVED WITH ITS BINS AS EPOCHS (binsAsEpochs). EEGLAB has
%   no averaged dataset: it reads channels x samples x bins as that many
%   epochs. Average keeps the trials' own epoch records and events, which
%   describe the trials averaged, not the data, and eeg_checkset refused
%   the file ("the number of epoch indices in the epoch array/struct (233)
%   is different from the number of epochs in the data (5)"). So each bin
%   becomes one epoch with one event at its time zero, named by the bin,
%   which is what EEGLAB shows for an epoch. No ERPLAB EVENTLIST is made for
%   an average: it would describe trials the file no longer holds, and
%   ERPLAB's own format for averages is the ERPset (Export as ERPset).
%
%   See also ONEXPORTSET, ALAKAZAMBINSTOEVENTLIST,
%   REWRITEEPOCHEDEVENTLATENCIES, ENSUREEVENTEPOCHFIELD, AVERAGEDTOERPSET.
    if strcmpi(dataFormatOf(EEG), 'AVERAGED')
        EEG = binsAsEpochs(EEG);
        return;
    end
    EEG = alakazamBinsToEventList(EEG);
    EEG = rewriteEpochedEventLatencies(EEG);
    EEG = ensureEventEpochField(EEG);
    EEG = eeglabTimes(EEG);
end

% ======================================================================= %
function EEG = binsAsEpochs(EEG)
%BINSASEPOCHS  An average as EEGLAB reads it: one epoch per bin, its one
%   event at time zero (the sample nearest 0 ms) named by the bin's label,
%   at EEGLAB's latency for it on the concatenated timeline. EEG.epoch is
%   left for eeg_checkset to build from those events, as EEGLAB builds it.
    nBins = size(EEG.data, 3);
    labels = arrayfun(@(k) sprintf('bin %d', k), 1:nBins, 'UniformOutput', false);
    if isfield(EEG, 'bindesc') && numel(EEG.bindesc) == nBins && isfield(EEG.bindesc, 'label')
        labels = arrayfun(@(b) char(string(b.label)), EEG.bindesc, 'UniformOutput', false);
    end
    [~, zero] = min(abs(EEG.times));
    EEG.trials = nBins;
    EEG.event = struct('type', labels, 'latency', num2cell((0:nBins - 1) * EEG.pnts + zero), ...
        'epoch', num2cell(1:nBins));
    EEG.urevent = [];
    EEG.epoch = [];
    if isfield(EEG, 'EVENTLIST')
        EEG = rmfield(EEG, 'EVENTLIST');
    end
    EEG = eeg_checkset(EEG, 'eventconsistency');
end

function EEG = eeglabTimes(EEG)
%EEGLABTIMES  A continuous recording's EEG.times in EEGLAB's milliseconds,
%   by eeg_checkset's own formula, linspace(xmin*1000, xmax*1000, pnts)
%   (xmin and xmax are in seconds in both conventions).
    if ~strcmpi(dataFormatOf(EEG), 'CONTINUOUS')
        return;
    end
    EEG.times = linspace(EEG.xmin * 1000, EEG.xmax * 1000, EEG.pnts);
end

function format = dataFormatOf(EEG)
%DATAFORMATOF  What the dataset says it is. Only one without a DataFormat
%   is judged by its shape, since a one-bin average has the shape of a
%   continuous recording.
    format = char(string(TransTools.FieldOr(EEG, 'DataFormat', '')));
    if isempty(format)
        format = inferDataFormat(EEG);
    end
end
