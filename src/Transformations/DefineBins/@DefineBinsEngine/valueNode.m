function nd = valueNode(test)
%VALUENODE  The expression node for value test TEST (scanValueTest). A
%   plain field test with number bounds compiles to the 'field' node it
%   always has, so such a plan is what it was; anything else is a 'value'
%   node, which splitFilters takes out of the expression when it is about
%   the bin's trials as a whole (isFilterTest).
    if strcmp(test.source, 'field') && strcmp(test.transform, 'none') ...
            && strcmp(test.window.lo.kind, 'num') && strcmp(test.window.hi.kind, 'num')
        iv = struct('lo', test.window.lo.value, 'hi', test.window.hi.value, ...
            'loOpen', logical(test.window.loOpen), 'hiOpen', logical(test.window.hiOpen), ...
            'unit', '');
        nd.op = 'field'; nd.name = test.name; nd.interval = iv;
    else
        nd.op = 'value'; nd.test = test;
    end
end
