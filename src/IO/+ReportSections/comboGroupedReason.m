function s = comboGroupedReason(includeVsZero, includeBetweenGroups)
%COMBOGROUPEDREASON  The sentence explaining what comboSectionGrouped
%   does and does not test, given which of its two optional parts are
%   included -- see its own header comment for the underlying reasoning.
    if includeVsZero && includeBetweenGroups
        s = ['Tested against zero within each group, and compared BETWEEN groups to see whether ' ...
             'the effect itself differs in size between them.'];
    elseif includeBetweenGroups
        s = ['A latency has no natural zero to test against (so no per-group one-sample test is run), ' ...
             'but is compared BETWEEN groups, to see whether it differs in size between them.'];
    else
        s = ['This is a circular quantity (an angle that wraps at +/-pi radians); the ordinary ' ...
             '(linear) tests used elsewhere in this report are not valid for circular data, so only ' ...
             'descriptive statistics per group are shown here.'];
    end
end

