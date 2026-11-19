function idx = BinTrials(EEG, b)
%BINTRIALS  Trial indices (into the epoch stack) belonging to bin B, a
%   position in EEG.bindesc. Read from the one store of bin membership,
%   EEG.epoch(t).bini (see TransTools.BinMembership, which also gives each
%   trial's reaction time); an old dataset whose bins still list their
%   trials is read as it always was.
%
%   Kept as the short form of TransTools.BinMembership.of because plugins
%   call it (Beamformer).
%
%   See also TRANSTOOLS.BINMEMBERSHIP, DEFINEBINS, AVERAGE.
    idx = TransTools.BinMembership.of(EEG, b);
end
