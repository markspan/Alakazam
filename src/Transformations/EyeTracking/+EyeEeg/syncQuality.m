function q = syncQuality(syncTable, srate, nTriggers)
%SYNCQUALITY  How well the eye track lines up with the EEG, from EYE-EEG's
%   own record of it.
%   Q = EyeEeg.syncQuality(SYNCTABLE, SRATE, NTRIGGERS) summarises the table
%   pop_importeyetracker leaves in EEG.etc.eyetracker_syncquality: one row
%   per offset, in samples, between an EEG trigger and the eye tracker's copy
%   of it after synchronisation (column 1, from -searchRadius to
%   +searchRadius), and how many shared events fell at that offset (column 2).
%   NTRIGGERS is how many numbered triggers the EEG had to match against.
%
%   Q fields:
%     nShared         shared events found in both recordings
%     nTriggers       numbered EEG triggers, so the share matched is visible
%     pctMatched      nShared as a percentage of nTriggers
%     nWithinOne      shared events at most one sample out
%     pctWithinOne    the same, as a percentage of nShared
%     meanAbsMs       the mean absolute offset, in milliseconds
%     maxAbsSamples   the worst offset found
%
%   WHY THESE: a good synchronisation puts nearly every shared event at an
%   offset of zero, with a few at one sample either side because two clocks
%   at different rates are rounded to one. Anything further out is a drift
%   the linear fit did not absorb, or a trigger matched to the wrong partner.
%   A bad synchronisation also shows up as FEW shared events rather than as
%   large offsets, because events further apart than searchRadius are not
%   counted as shared at all, which is why nShared is reported beside
%   nTriggers instead of on its own.
%
%   See also EYETRACKING.
    q = struct('nShared', 0, 'nTriggers', nTriggers, 'pctMatched', 0, ...
        'nWithinOne', 0, 'pctWithinOne', NaN, 'meanAbsMs', NaN, 'maxAbsSamples', NaN);
    if isempty(syncTable) || size(syncTable, 2) < 2
        return;
    end
    offsets = double(syncTable(:, 1));
    counts = double(syncTable(:, 2));
    q.nShared = sum(counts);
    if nTriggers > 0
        q.pctMatched = 100 * q.nShared / nTriggers;
    end
    if q.nShared == 0
        return;
    end
    q.nWithinOne = sum(counts(abs(offsets) <= 1));
    q.pctWithinOne = 100 * q.nWithinOne / q.nShared;
    q.meanAbsMs = sum(abs(offsets) .* counts) / q.nShared * 1000 / srate;
    q.maxAbsSamples = max(abs(offsets(counts > 0)));
end
