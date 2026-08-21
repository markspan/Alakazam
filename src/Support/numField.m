function field = numField(value)
%NUMFIELD  A numeric value formatted for CSV, NA (R's own missing-value
%   token) if it is NaN.
%
%   Previously reimplemented, identically, in exportMeasurementsCSV.m,
%   exportSpectralCSV.m and exportGrandAveragesCSV.m; consolidated here.
    if isnan(value)
        field = 'NA';
    else
        field = sprintf('%.6g', value);
    end
end
