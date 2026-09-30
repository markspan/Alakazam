function [EEG, scalpIdx, otherIdx] = ScalpChannels(EEG, errorId)
%SCALPCHANNELS  The channels an automated cleaning method should work on:
%   scalp EEG with a position, after filling in the positions that a
%   standard 10-5 label implies.
%
%   [EEG, SCALPIDX, OTHERIDX] = TransTools.ScalpChannels(EEG, ERRORID)
%   returns EEG with missing positions looked up in the 10-5 template
%   (Template1005File) and blank channel types guessed from the labels, and
%   the indices of the scalp channels (SCALPIDX) and of the rest (OTHERIDX,
%   the peripherals: EOG, ECG, a photodiode, a trigger channel, and any
%   channel the template does not know).
%
%   WHY THIS SPLIT, AND WHY IN ONE PLACE. PREP, ASR and AutoReject all
%   estimate what a clean scalp looks like from the channels themselves:
%   PREP's robust reference and RANSAC, ASR's calibration covariance,
%   AutoReject's interpolation. An EOG channel in that set is wrong for all
%   three (its blinks are the signal it exists to record), and a photodiode
%   or trigger channel is not EEG at all. Interpolation also needs a
%   position, so a channel without one cannot take part. AutoEyeICA and
%   AutoGEDAI made the same split inline; this is that rule, stated once,
%   for the methods that came after them.
%
%   Throws ERRORID when no channel qualifies, naming what to do about it.
%
%   See also TRANSTOOLS.FILLCHANLOCS, TRANSTOOLS.TEMPLATE1005FILE,
%   EEGCHANNELMASK, GUESSCHANNELTYPES.
    EEG = TransTools.FillChanlocs(EEG, errorId, TransTools.Template1005File(errorId));
    EEG.chanlocs = guessChannelTypes(EEG.chanlocs);

    positioned = arrayfun(@(c) isfield(c, 'X') && ~isempty(c.X) && all(isfinite(c.X)), EEG.chanlocs);
    scalp = reshape(positioned, 1, []) & reshape(eegChannelMask(EEG.chanlocs), 1, []);
    scalpIdx = find(scalp);
    otherIdx = find(~scalp);

    if isempty(scalpIdx)
        throw(MException(errorId, ['I''m afraid none of this dataset''s channels is scalp EEG ' ...
            'with a standard 10-5 position, so there is nothing to clean. Would you rename the ' ...
            'channels to 10-5 labels, or set their positions in the Channel Editor, first?']));
    end
end
