function mask = IsComboBin(bins)
%ISCOMBOBIN  Which bins are combination bins.
%   MASK = TransTools.IsComboBin(BINS) is a 1 x numel(BINS) logical row,
%   true for each combination bin ("bin 3 = bin 1 - bin 2") and false for
%   each ordinary bin, whose trials come from matching events.
%
%   BINS is either an EEG.bindesc or the .bins of a DefineBins spec
%   (DefineBinsEngine.parseSpec): both carry the combination as .combo, a
%   struct array of .bin and .coeff that is empty for an ordinary bin. A
%   single bin, EEG.bindesc(b), gives a scalar.
%
%   ROBUST TO WHAT A DATASET MAY CARRY. A struct without a .combo field (a
%   dataset made by hand, a bindesc from before combination bins existed) has no
%   combination bins, so its mask is all false, one per bin; anything that
%   is not a struct (a dataset with no bins, bindesc = []) gives an empty
%   mask. Neither is an error, so every caller can index with it directly:
%
%       ordinary = find(~TransTools.IsComboBin(EEG.bindesc));
%
%   ONE DEFINITION FOR EVERY CALLER. What makes a bin a combination used to
%   be spelled out at each place that asked, in four different idioms, some
%   guarding for a missing field and some not. It is a definition, not a
%   convenience, so it lives here once; the Deconvolve plugin uses it too.
%
%   See also TRANSTOOLS.COMBOORDER, DEFINEBINS, AVERAGE.
    if ~isstruct(bins)
        mask = false(1, 0);
        return;
    end
    mask = false(1, numel(bins));
    if ~isempty(bins) && isfield(bins, 'combo')
        mask = ~cellfun(@isempty, reshape({bins.combo}, 1, []));
    end
end
