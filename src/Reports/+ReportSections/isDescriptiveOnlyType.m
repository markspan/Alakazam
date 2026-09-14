function tf = isDescriptiveOnlyType(measureType)
%ISDESCRIPTIVEONLYTYPE  True when a combination/difference bin's
%   MEASURETYPE should be reported descriptively only (no one-sample-vs-
%   zero test), for either of two unrelated reasons -- see
%   descriptiveOnlyReason for the matching explanatory text:
%     - A LATENCY (peak_latency, fractional_peak_latency,
%       fractional_area_latency -- ERP measure types): zero has no
%       meaningful interpretation. A combination bin's amplitude/area
%       score has a natural "zero" to test against (no difference between
%       the conditions it combines) -- but its latency does not:
%       Measure.m computes a combination bin's own fractional/peak
%       latency on the DIFFERENCE WAVEFORM itself (bin4's average minus
%       bin3's, say), a genuine point in time, not an arithmetic
%       difference of two separately-measured latencies -- so "is this
%       latency significantly different from 0 ms" has no meaningful
%       null hypothesis behind it.
%     - A CIRCULAR quantity (phase, phaselag -- spectral measure types):
%       an angle that wraps at +/-pi radians, for which ordinary linear
%       statistics (a t-test's own mean/SD) are not valid -- this
%       generator has no circular-statistics machinery to fall back to,
%       so the honest thing is to show the values without a test that
%       would silently misinterpret them near the wrap-around boundary.
%   See comboSection's own header comment for how this changes what gets
%   reported.
    tf = any(strcmp(measureType, {'peak_latency', 'fractional_peak_latency', ...
        'fractional_area_latency', 'phase', 'phaselag'}));
end

