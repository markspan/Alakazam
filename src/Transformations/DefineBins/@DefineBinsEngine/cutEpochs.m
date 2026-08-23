function [EEG, bindesc] = cutEpochs(EEG, bindesc, win, centerLat)
%CUTEPOCHS  Cut a chan x time x trials stack around every matched anchor.
%   The union of all bins' matched events becomes the trial set (an event in
%   several bins is one trial carrying several bin tags). Windows that run off
%   either end of the recording are padded with NaN. Produces an EPOCHED
%   dataset that plots with EpochView and can later be averaged per bin.
    if ~isfield(EEG, 'data') || isempty(EEG.data)
        throw(MException('Alakazam:DefineBins', ...
            ['You gave an Epoch start/stop, so DefineBins tried to cut the data into ' ...
             'trials, but I''m afraid this dataset has no continuous EEG.data to cut ' ...
             'from. This usually means it was already segmented (or is missing data ' ...
             'entirely) before it reached DefineBins.']));
    end
    if ~ismatrix(EEG.data) || (isfield(EEG, 'DataFormat') && ...
            strcmpi(EEG.DataFormat, 'EPOCHED'))
        throw(MException('Alakazam:DefineBins', ...
            ['You gave an Epoch start/stop, but I''m afraid this dataset is already ' ...
             'epoched (channels x time x trials), and DefineBins only knows how to cut ' ...
             'trials out of continuous data. If you would like to re-tag bins on data ' ...
             'you have already segmented, please leave both Epoch fields blank.']));
    end

    srate = EEG.srate;
    if strcmpi(win.unit, 'samples')
        loS = round(win.lo);  hiS = round(win.hi);
    else
        loS = round(win.lo / 1000 * srate);
        hiS = round(win.hi / 1000 * srate);
    end
    pnts = hiS - loS;
    if pnts <= 0
        throw(MException('Alakazam:DefineBins', ...
            ['The epoch window (%g to %g %s) rounds to zero or a negative number ' ...
             'of samples at this dataset''s sampling rate (%g Hz), I''m afraid, so ' ...
             'there is nothing to cut. Would you widen the window, or double-check ' ...
             'the sampling rate is what you expect?'], win.lo, win.hi, win.unit, srate));
    end

    allEvents = unique([bindesc.events]);
    if isempty(allEvents)
        throw(MException('Alakazam:DefineBins', ...
            ['None of your bins matched a single event in this dataset, I''m afraid, ' ...
             'so there is nothing to epoch. Would you double-check the marker codes in ' ...
             'your script against the ones actually present in this recording ' ...
             '(EEG.event(i).type), and that any next(...)/prev(...)/within windows ' ...
             'are wide enough to catch the responses you expect?']));
    end

    nchan = size(EEG.data, 1);
    total = size(EEG.data, 2);
    ntr   = numel(allEvents);
    lat   = centerLat;   % sample to centre each epoch on (timelock-aware)

    data = nan(nchan, pnts, ntr);
    for k = 1:ntr
        ei = allEvents(k);
        if isnan(lat(ei)); continue; end
        a = lat(ei) + loS;              % first sample of the epoch (1-based)
        b = a + pnts - 1;
        srcA = max(a, 1);  srcB = min(b, total);
        if srcB < srcA; continue; end   % epoch entirely outside the data
        dstA = srcA - a + 1;
        dstB = dstA + (srcB - srcA);
        data(:, dstA:dstB, k) = EEG.data(:, srcA:srcB);
    end

    times = ((loS + (0:pnts - 1)) / srate) * 1000;   % ms, t = 0 at the anchor

    EEG.data       = data;
    EEG.pnts       = pnts;
    EEG.trials     = ntr;
    EEG.times      = times;
    EEG.xmin       = times(1) / 1000;
    EEG.xmax       = times(end) / 1000;
    EEG.DataFormat = 'EPOCHED';

    % Per-trial epoch table and bin -> trial index mapping.
    trialOf = zeros(1, max(allEvents));
    trialOf(allEvents) = 1:ntr;
    EEG.epoch = struct('event', {}, 'eventtype', {}, ...
                       'eventlatency', {}, 'bini', {});
    for k = 1:ntr
        ei = allEvents(k);
        EEG.epoch(k).event        = ei;
        EEG.epoch(k).eventtype    = EEG.event(ei).type;
        EEG.epoch(k).eventlatency = 0;
        EEG.epoch(k).bini         = EEG.event(ei).bini;
        % EEGLAB expects every event to carry its own containing epoch
        % number once EEG.trials > 1 (eeg_checkset errors "the event info
        % structure does not contain an 'epoch' field" otherwise --
        % surfaced by pop_saveset on export, since nothing internal to
        % Alakazam itself ever reads this field). Set on each trial's own
        % anchor event only, matching this epoching model's one-anchor-
        % per-trial design (see EEG.epoch itself, above); every other
        % event -- one that was never matched to a bin, so belongs to no
        % kept trial -- is left with MATLAB's default [] for a struct
        % field none of its siblings set, which eeg_checkset's own
        % 'eventconsistency' cleanup already knows to prune as invalid.
        EEG.event(ei).epoch = k;
    end
    for b = 1:numel(bindesc)
        if isempty(bindesc(b).events)
            bindesc(b).trials = [];
        else
            bindesc(b).trials = trialOf(bindesc(b).events);
        end
    end
end
