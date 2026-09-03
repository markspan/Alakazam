function tf = thirdDimIsBins(EEG)
%THIRDDIMISBINS  Does EEG.data's 3rd dimension index bins, or trials?
%
%   THE PRESENCE OF BINDESC DOES NOT ANSWER THIS, which is the entire
%   reason this is a named function rather than an inline isfield check.
%   Averaging collapses trials into one page per bin; before that, the 3rd
%   dimension is trials and bindesc merely records which trial sits in
%   which bin. Both carry bindesc, so only DataFormat separates them.
%
%   It is written down here because getting it wrong is silent. FourierView
%   asked "is bindesc present?", which is true of epoched data too, and so
%   titled single-trial spectra "Bin 37 of 197" -- a confident, wrong name
%   for what was on screen, with nothing to alert the reader. Anything else
%   that has to label a third dimension should ask this rather than
%   re-derive it.
%
%   The fallback exists for datasets predating DataFormat: a third
%   dimension whose length equals the bin count is the best guess
%   available, and is at least a test rather than an assumption.
%
%   See also TRIALBINS, CSVBINLABEL.
    tf = false;
    if ~isfield(EEG, 'bindesc') || isempty(EEG.bindesc)
        return;
    end
    if isfield(EEG, 'DataFormat') && ~isempty(EEG.DataFormat)
        tf = strcmpi(char(string(EEG.DataFormat)), 'Averaged');
        return;
    end
    tf = size(EEG.data, 3) == numel(EEG.bindesc);
end
