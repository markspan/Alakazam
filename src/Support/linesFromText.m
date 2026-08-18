function lines = linesFromText(text)
%LINESFROMTEXT  A char block (possibly '') to a cellstr for a uitextarea's
%   Value (one entry per line; {''} for empty, never {} which a uitextarea
%   rejects).
%
%   Previously reimplemented, identically, in MeasureDialog.m and
%   SpectralMeasureDialog.m; consolidated here.
    if isempty(char(string(text)))
        lines = {''};
    else
        lines = cellstr(splitlines(string(text)));
    end
end
