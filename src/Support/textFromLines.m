function text = textFromLines(value)
%TEXTFROMLINES  A uitextarea's Value (cellstr, one per line) back to a
%   single newline-joined char block -- the inverse of linesFromText.
%
%   Previously reimplemented, identically, in MeasureDialog.m and
%   SpectralMeasureDialog.m; consolidated here.
    text = char(strjoin(string(value), newline));
end
