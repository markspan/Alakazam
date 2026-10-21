function tf = isFilterTest(test)
%ISFILTERTEST  Whether value test TEST is about the bin's trials as a whole
%   rather than one event: a reaction time (the delay to the event the
%   bin's relation captured), a rank among the trials, or a bound taken
%   from their statistics. Such a test filters the trials the rest of the
%   bin matched (splitFilters, evaluateBins); any other is a term evaluated
%   on each event like a code.
    tf = strcmp(test.source, 'rt') || strcmp(test.transform, 'rank') ...
        || strcmp(test.window.lo.kind, 'stat') || strcmp(test.window.hi.kind, 'stat');
end
