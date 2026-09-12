function idx = BinTrials(EEG, b)
%BINTRIALS  Trial indices (into the epoch stack) belonging to bin B.
%   Prefers the explicit trial list DefineBins stores on each bin; falls
%   back to scanning the per-epoch .bini membership tags. Previously
%   reimplemented, identically, in Average.m and SpectralMeasure.m (the
%   latter's own copy said as much: "mirrors Average.binTrials");
%   consolidated here.
%
%   See also DEFINEBINS, AVERAGE, SPECTRALMEASURE.
    idx = [];
    if isfield(EEG.bindesc, 'trials') && ~isempty(EEG.bindesc(b).trials)
        idx = EEG.bindesc(b).trials;
    elseif isfield(EEG, 'epoch') && ~isempty(EEG.epoch) && isfield(EEG.epoch, 'bini')
        binIndex = EEG.bindesc(b).index;
        idx = find(arrayfun(@(e) any(e.bini == binIndex), EEG.epoch));
    end
end
