function label = csvBinLabel(EEG, b)
%CSVBINLABEL  EEG.bindesc(b)'s own label, or the bare bin number as a
%   fallback (EEG.bindesc absent/short/blank at b -- an older or
%   non-binned dataset).
%
%   Previously reimplemented, identically, as exportMeasurementsCSV.m's
%   and exportSpectralCSV.m's own binLabel, and inline (not even factored
%   into a function) in exportGrandAveragesCSV.m; consolidated here. Not
%   the same helper as SpectralMeasureView's own binLabel, which
%   additionally normalises the result through char(string(...)) for use
%   in a plot title -- a real behavioural difference, not just a rename,
%   so left as its own separate, single-use local function there.
    if isfield(EEG, 'bindesc') && numel(EEG.bindesc) >= b && ~isempty(EEG.bindesc(b).label)
        label = EEG.bindesc(b).label;
    else
        label = num2str(b);
    end
end
