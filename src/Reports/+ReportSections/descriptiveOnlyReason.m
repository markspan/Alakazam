function s = descriptiveOnlyReason(measureType)
%DESCRIPTIVEONLYREASON  The sentence explaining WHY a descriptive-only
%   combo section (see isDescriptiveOnlyType) skipped its one-sample test
%   -- the specific reason differs between the two categories that
%   function covers, so this is not just a single fixed string.
    if any(strcmp(measureType, {'phase', 'phaselag'}))
        s = ['This is a circular quantity (an angle that wraps at +/-pi radians); the ordinary ' ...
             '(linear) one-sample test used elsewhere in this report is not valid for circular ' ...
             'data, so only descriptive statistics are shown here.'];
    else
        s = ['A latency has no natural "zero" to test against the way an amplitude/area ' ...
             'difference does (zero would mean "no difference"; a latency near 0 ms means ' ...
             'nothing of the kind), so only descriptive statistics are reported here.'];
    end
end

