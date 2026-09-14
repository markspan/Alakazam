function s = labelPiece(matlabText)
%LABELPIECE  MATLABTEXT as a safe, lowercase, hyphenated fragment for a
%   Quarto/knitr chunk label (letters, digits, hyphens only -- unlike
%   R/MATLAB identifiers, a chunk label is not restricted to start with a
%   letter, but IS restricted to have no spaces and no characters knitr
%   would choke on, so this is deliberately more conservative than
%   strictly required). Never empty (falls back to "x"), so a blank
%   window/measure-type piece never collapses two different labels into
%   the same "--" run.
    s = lower(char(matlabText));
    s = regexprep(s, '[^a-z0-9]+', '-');
    s = regexprep(s, '^-+|-+$', '');
    if isempty(s)
        s = 'x';
    end
end

