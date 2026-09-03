function idx = trialBins(EEG, t)
%TRIALBINS  Indices of the bins trial T belongs to ([] if none).
%
%   The inverse of the binTrials helper that Average.m and
%   SpectralMeasure.m each keep locally, and it reads membership the same
%   way they do: the explicit trial list DefineBins stores per bin, falling
%   back to the per-epoch .bini membership tags for datasets that only have
%   those.
%
%   ALL MATCHING BINS ARE RETURNED, not just the first. A trial can sit in
%   more than one bin -- a combination bin overlapping a base one -- and a
%   caller that names a single bin for such a trial is telling a confident
%   half-truth, which is the failure mode this pair of helpers exists to
%   stop.
%
%   See also THIRDDIMISBINS, CSVBINLABEL.
    idx = [];
    if ~isfield(EEG, 'bindesc') || isempty(EEG.bindesc)
        return;
    end
    for b = 1:numel(EEG.bindesc)
        members = [];
        if isfield(EEG.bindesc, 'trials') && ~isempty(EEG.bindesc(b).trials)
            members = EEG.bindesc(b).trials;
        elseif isfield(EEG, 'epoch') && ~isempty(EEG.epoch) && isfield(EEG.epoch, 'bini')
            members = find(arrayfun(@(e) any(e.bini == EEG.bindesc(b).index), EEG.epoch));
        end
        if any(members == t)
            idx(end+1) = b; %#ok<AGROW>
        end
    end
end
