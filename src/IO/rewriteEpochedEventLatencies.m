function EEG = rewriteEpochedEventLatencies(EEG)
%REWRITEEPOCHEDEVENTLATENCIES  EEGLAB expects an epoched dataset's event
%   latencies on one CONCATENATED timeline, epoch k's own samples
%   occupying [(k-1)*EEG.pnts, k*EEG.pnts) -- not the original continuous
%   recording's own sample numbers DefineBins/cutEpochs leaves every
%   event's .latency holding unchanged (Alakazam itself never reads
%   EEG.event(i).latency again once epoched, so this was never a gap its
%   own code could hit). Left as-is, eeg_checkset sees a trial anchor's
%   latency as wildly out of bounds for the (much shorter) per-epoch
%   sample count and PRUNES it outright -- confirmed directly: exporting a
%   2-bin, 40-trial dataset lost 12 of its 40 trial-anchor events this
%   way before this fix, corrupting the very EEG.epoch(k).event index
%   alakazamBinsToEventList/ensureEventEpochField (called right after
%   this, in onExportSet.m) both rely on.
%
%   Only the ANCHOR event of each trial (EEG.epoch(k).event) is rewritten;
%   every other event is left alone -- 'eventconsistency' (inside
%   ensureEventEpochField, called right after this) is what actually
%   prunes a non-anchor event, which is correct: it belongs to no trial in
%   Alakazam's own one-anchor-per-trial epoch model (see cutEpochs.m).
%
%   A no-op (returns EEG unchanged) on continuous data (trials <= 1) or
%   when there is no per-epoch anchor info to work from.
%
%   See also ONEXPORTSET, ENSUREEVENTEPOCHFIELD, DEFINEBINSENGINE.CUTEPOCHS.
    if ~isfield(EEG, 'trials') || EEG.trials <= 1 ...
            || ~isfield(EEG, 'epoch') || isempty(EEG.epoch) || ~isfield(EEG.epoch, 'event') ...
            || ~isfield(EEG, 'times') || isempty(EEG.times) || ~isfield(EEG, 'pnts')
        return;
    end
    % The anchor's own within-epoch sample, 1-BASED (EEGLAB's own .event
    % latency convention -- confirmed directly: a 0-based offset here
    % reliably came back exactly one sample short after a real
    % pop_saveset/eeg_checkset round trip, e.g. epoch(k).eventlatency
    % -4 ms at 250 Hz instead of the expected 0, -4 ms being exactly
    % -1 sample). cutEpochs always gives every epoch an EXACT 0 at the
    % anchor (times = ((loS + (0:pnts-1)) / srate) * 1000, so sample
    % -loS+1 evaluates to exactly 0), so this is never a nearest-match
    % guess, just a 1-based/0-based unit fix.
    zeroSample = find(abs(EEG.times) < 1e-9, 1);
    if isempty(zeroSample)
        return;
    end
    for k = 1:numel(EEG.epoch)
        ei = EEG.epoch(k).event;
        if ~isempty(ei) && isscalar(ei) && ei >= 1 && ei <= numel(EEG.event)
            EEG.event(ei).latency = (k - 1) * EEG.pnts + zeroSample;
        end
    end
end
