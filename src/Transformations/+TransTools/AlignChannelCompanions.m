function EEG = AlignChannelCompanions(EEG, inputChanlocs)
%ALIGNCHANNELCOMPANIONS  Keep the per-channel arrays a dataset carries
%   beside EEG.data in step with its channel list.
%
%   EEG = TransTools.AlignChannelCompanions(EEG, INPUTCHANLOCS) takes a
%   transformation's result EEG and the channel list of the dataset it was
%   given, and makes every companion array have one row per channel of EEG,
%   in EEG's order. A companion is an array indexed by channel that is not
%   EEG.data itself:
%
%     EEG.stErr                   channels x samples x bins   (Average)
%     EEG.aSME                    channels x bins             (Average)
%     EEG.etc.alz.interpolated    channels x trials, logical  (see
%                                 TransTools.RecordInterpolated)
%
%   The mask's columns are the trials it was recorded on, which an average
%   carries on without having them as its own third dimension, so only its
%   rows are aligned.
%
%   A companion whose rows already match EEG's channels is left alone, so a
%   transformation that maintains its own (CollapseHemispheres, Average) is
%   never second-guessed. One that does not match is rebuilt by label: a
%   channel of EEG that was a channel of the input keeps its row, and a
%   channel that was not (a derived channel, say) gets "not known": NaN for
%   an error estimate, false for the interpolation mask. A companion whose
%   other dimensions no longer match the data (samples after a resample,
%   bins after a bin edit) cannot be aligned row by row, so it becomes
%   wholly unknown rather than wrong.
%
%   WHY THIS IS AT THE CONTRACT SEAM. Steps that change the channel list
%   (DeriveChannels, SelectData, ChannelEditor) were written for EEG.data
%   and EEG.chanlocs, which is all EEGLAB's own functions know about. On an
%   average they left EEG.stErr one row short or long, and nothing failed
%   until the result was drawn: AverageView subtracted a 33-row error from a
%   34-row waveform and reported "Arrays have incompatible sizes" against
%   the plot, not the step. TransTools.invoke runs this after every call, so
%   the invariant "companions match the channels" holds for every plugin,
%   including ones not written yet, without each having to know the list.
%
%   NaN, NOT A GUESS, for a channel with no row to take. The standard error
%   of a difference between two electrodes depends on how the two covary
%   over trials, which an average no longer contains; assuming independence
%   would overstate it for neighbouring electrodes, which covary strongly.
%   Derive the channel before averaging and Average computes the real one.
%
%   See also TRANSTOOLS.INVOKE, TRANSTOOLS.APPLYDERIVATIONS,
%   TRANSTOOLS.RECORDINTERPOLATED.
    if ~isstruct(EEG) || ~isfield(EEG, 'data') || ~isfield(EEG, 'chanlocs') || isempty(EEG.data)
        return;
    end
    nChan = size(EEG.data, 1);
    if numel(EEG.chanlocs) ~= nChan
        return;   % no channel list to align to; eeg_checkset's concern, not this one's
    end
    rows = sourceRows({EEG.chanlocs.labels}, inputChanlocs);

    if isfield(EEG, 'stErr') && ~isempty(EEG.stErr)
        EEG.stErr = align(EEG.stErr, rows, nChan, [size(EEG.data, 2), size(EEG.data, 3)], NaN);
    end
    if isfield(EEG, 'aSME') && ~isempty(EEG.aSME)
        EEG.aSME = align(EEG.aSME, rows, nChan, size(EEG.data, 3), NaN);
    end
    if isfield(EEG, 'etc') && isstruct(EEG.etc) && isfield(EEG.etc, 'alz') ...
            && isstruct(EEG.etc.alz) && isfield(EEG.etc.alz, 'interpolated') ...
            && islogical(EEG.etc.alz.interpolated) && ~isempty(EEG.etc.alz.interpolated)
        mask = EEG.etc.alz.interpolated;
        EEG.etc.alz.interpolated = align(mask, rows, nChan, ...
            trailingSize(mask, ndims(mask) - 1), false);
    end
end

% ======================================================================= %
function rows = sourceRows(labels, inputChanlocs)
%SOURCEROWS  For each of LABELS, its row in the input (0 when it had none).
%   Matched case-insensitively, as channel labels are everywhere else, and
%   to the first of any duplicated label.
    rows = zeros(1, numel(labels));
    if isempty(inputChanlocs) || ~isfield(inputChanlocs, 'labels')
        return;
    end
    inputLabels = lower(cellfun(@(l) char(string(l)), {inputChanlocs.labels}, 'UniformOutput', false));
    for k = 1:numel(labels)
        hit = find(strcmp(inputLabels, lower(char(string(labels{k})))), 1);
        if ~isempty(hit)
            rows(k) = hit;
        end
    end
end

function out = align(companion, rows, nChan, trailing, unknown)
%ALIGN  COMPANION with one row per output channel. TRAILING is the size
%   its other dimensions must have; UNKNOWN fills what cannot be known.
    shape = size(companion);
    if shape(1) == nChan && isequal(trailingSize(companion, numel(trailing)), trailing)
        out = companion;   % already in step: this step kept it itself
        return;
    end
    out = repmat(cast(unknown, 'like', companion), [nChan, trailing]);
    if ~isequal(trailingSize(companion, numel(trailing)), trailing)
        return;            % samples or bins changed too: nothing can be carried over
    end
    kept = rows > 0 & rows <= shape(1);
    out(kept, :) = companion(rows(kept), :);
end

function s = trailingSize(x, n)
%TRAILINGSIZE  The sizes of X's dimensions 2 to N+1, trailing singletons
%   included, so a channels x samples average compares equal to
%   [samples, 1] bins.
    s = arrayfun(@(d) size(x, d), 2:n + 1);
end
