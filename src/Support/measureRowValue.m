function v = measureRowValue(win, measureType, c, b)
%MEASUREROWVALUE  The value one CSV row (channel C, bin B, MEASURETYPE --
%   one of measureRowTypes(win)'s own return values) should carry: every
%   measure_type falls into exactly one of WIN's three result matrices
%   (.amplitude, .latency, .area).
%
%   See also MEASUREROWTYPES.
    if strcmp(measureType, 'peak_amplitude') || strcmp(measureType, 'mean_amplitude')
        v = win.amplitude(c, b);
    elseif startsWith(measureType, 'area_')
        v = win.area(c, b);
    else % peak_latency, fractional_peak_latency, fractional_area_latency
        v = win.latency(c, b);
    end
end
