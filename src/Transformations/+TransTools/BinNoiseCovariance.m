function C = BinNoiseCovariance(EEG, bin, labels)
%BINNOISECOVARIANCE  One bin's noise covariance, in the channel order LABELS.
%   C = TransTools.BinNoiseCovariance(EEG, BIN, LABELS) returns the noise
%   covariance Average stored for bin BIN (EEG.noiseCov(:, :, BIN): the
%   baseline covariance of a single trial, pooled over every trial, divided
%   by the number of trials the bin's average holds, so the noise of that
%   average itself), with its rows and columns in the
%   order of LABELS, matched by label without regard to case.
%
%   Returns [] when there is none to use: a dataset averaged before the
%   noise covariance was stored, a grand average, a step that mixed the
%   channels after averaging (which drops it), a channel in LABELS the
%   average did not have (a derived channel, whose rows are NaN), or a bin
%   with too few clean trials. The caller then falls back to the identity,
%   and says so; it never inverts with a covariance that belongs to other
%   channels or other data.
%
%   REORDERED BY LABEL, NOT BY POSITION, for the same reason the data is
%   (see TransTools.BuildSourceForwardModel): the forward model's channel
%   order is the template's, not the dataset's, and a covariance applied in
%   the wrong order would whiten the wrong channels without any error.
%
%   See also AVERAGE, TRANSTOOLS.INVERSESOLUTION, TRANSTOOLS.ALIGNCHANNELCOMPANIONS.
    C = [];
    if ~isfield(EEG, 'noiseCov') || isempty(EEG.noiseCov) || ~isfield(EEG, 'chanlocs')
        return;
    end
    nChan = numel(EEG.chanlocs);
    if size(EEG.noiseCov, 1) ~= nChan || size(EEG.noiseCov, 2) ~= nChan ...
            || bin < 1 || bin > size(EEG.noiseCov, 3)
        return;
    end
    have = lower(cellfun(@(l) char(string(l)), {EEG.chanlocs.labels}, 'UniformOutput', false));
    want = lower(cellfun(@(l) char(string(l)), cellstr(labels), 'UniformOutput', false));
    [found, rows] = ismember(want, have);
    if ~all(found)
        return;
    end
    C = double(EEG.noiseCov(rows, rows, bin));
    if any(~isfinite(C(:))) || ~any(C(:))
        C = [];
    end
end
