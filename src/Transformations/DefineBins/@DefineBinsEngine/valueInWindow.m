function tf = valueInWindow(node, p, ctx)
%VALUEINWINDOW  Evaluate a 'value' node in an expression: a field of the
%   candidate event P, or its logarithm, in a window of numbers (inf
%   allowed). A test about the bin's trials as a whole never gets here:
%   splitFilters takes those out of the expression (isFilterTest), and
%   evaluateBins applies them to the trials.
    test = node.test;
    v = DefineBinsEngine.fieldValue(test.name, p, ctx);
    v = DefineBinsEngine.transformValues(v, test.transform);
    iv = DefineBinsEngine.resolveValueWindow(test, []);
    tf = ~isnan(v) && DefineBinsEngine.inInterval(v, iv);
end
