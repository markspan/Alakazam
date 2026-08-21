function types = measureRowTypes(win)
%MEASUREROWTYPES  The list of CSV measure_type strings one Measure window
%   produces, e.g. 'Peak' -> {'peak_amplitude', 'peak_latency'}, a plain
%   'Mean Amplitude' -> {'mean_amplitude'}.
%
%   The SAME mapping exportMeasurementsCSV.m's own writeEntry switch uses
%   to decide which rows to write -- extracted here (exportMeasurementsCSV
%   now calls this too, see measureRowValue.m for the matching value
%   lookup) so a caller that needs to know what will be IN the CSV without
%   actually writing it (generateQuartoReport.m, deciding what R code to
%   emit for each window before the CSV necessarily even exists yet) has
%   one place to ask, guaranteed to never drift from what the CSV writer
%   itself produces.
%
%   See also MEASUREROWVALUE, AREAMODESCOPE, EXPORTMEASUREMENTSCSV,
%   GENERATEQUARTOREPORT.
    measure = lower(strtrim(char(string(win.measure))));
    switch measure
        case 'peak'
            types = {'peak_amplitude', 'peak_latency'};
        case {'area', 'integral', 'peak area'}
            [mode, isBand] = areaModeScope(win, measure);
            types = {['area_' mode]};
            if isBand
                types = [types, {'peak_amplitude', 'peak_latency'}];
            end
        case 'fractional peak latency'
            types = {'fractional_peak_latency'};
        case 'fractional area latency'
            types = {'fractional_area_latency'};
        otherwise % Mean Amplitude
            types = {'mean_amplitude'};
    end
end
