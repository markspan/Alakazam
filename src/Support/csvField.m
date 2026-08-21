function field = csvField(value)
%CSVFIELD  A CSV-quoted field if VALUE needs it (contains a comma, quote,
%   or newline), otherwise VALUE unchanged. Values are inserted as %s
%   arguments into sprintf/fprintf format strings elsewhere, never as
%   literal format text, so a stray '%' in VALUE (e.g. a percent-labelled
%   bin name) needs no escaping here.
%
%   Previously reimplemented, identically, in exportMeasurementsCSV.m,
%   exportSpectralCSV.m and exportGrandAveragesCSV.m; consolidated here.
    field = char(string(value));
    if any(field == ',' | field == '"' | field == newline)
        field = ['"' strrep(field, '"', '""') '"'];
    end
end
