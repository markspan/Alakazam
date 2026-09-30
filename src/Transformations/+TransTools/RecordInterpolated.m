function EEG = RecordInterpolated(EEG, flags)
%RECORDINTERPOLATED  Merge FLAGS into EEG.etc.alz.interpolated, the record
%   of which channel of which trial was reconstructed rather than recorded.
%
%   EEG = TransTools.RecordInterpolated(EEG, FLAGS) ORs the logical
%   nChan x nTrials FLAGS into the stored mask, so a dataset that has been
%   through interpolation twice keeps both rounds. dataQualityMetrics reads
%   this mask to report the share of channel-epochs interpolated beside the
%   share rejected; an interpolated cell is otherwise indistinguishable from
%   one that was never flagged. Every step that reconstructs data writes it
%   (InterpolateFlaggedCells, and AutoReject, which interpolates a subset of
%   the channels and records against the whole montage).
%
%   Written defensively because EEG.etc is EEGLAB's own free-form field: it
%   may be absent, empty, or (on data that has been through some toolboxes)
%   not a struct at all, and none of those may be allowed to error here.
%
%   See also TRANSTOOLS.INTERPOLATEFLAGGEDCELLS, DATAQUALITYMETRICS.
    [nChan, ~, nTrials] = size(EEG.data);

    if ~isfield(EEG, 'etc') || ~isstruct(EEG.etc) || isempty(EEG.etc)
        EEG.etc = struct();
    end
    if ~isfield(EEG.etc, 'alz') || ~isstruct(EEG.etc.alz) || isempty(EEG.etc.alz)
        EEG.etc.alz = struct();
    end

    previous = false(nChan, nTrials);
    if isfield(EEG.etc.alz, 'interpolated')
        stored = EEG.etc.alz.interpolated;
        if islogical(stored) && isequal(size(stored), [nChan, nTrials])
            previous = stored;
        end
        % A stored mask of the wrong shape belongs to a differently shaped
        % dataset (a resample or a channel edit since it was written), so it
        % cannot be merged: it is dropped rather than misaligned.
    end

    EEG.etc.alz.interpolated = previous | logical(flags);
end
