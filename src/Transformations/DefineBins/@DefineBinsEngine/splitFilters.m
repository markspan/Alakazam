function [base, tests] = splitFilters(expr)
%SPLITFILTERS  A bin's expression parted into the condition its trials must
%   meet one event at a time (BASE) and the tests about its trials as a
%   whole (TESTS, see isFilterTest): reaction times, ranks, and bounds taken
%   from the trials' statistics.
%
%   Such a test needs the trials it is about, so it must be one of the
%   conditions every trial has to meet: joined to the rest by 'and' (or
%   written next to it), at the top of the expression. Its statistics and
%   ranks are then those of the trials the rest of the bin matches, BASE,
%   each test's over the same trials, not over what another test left. A
%   test inside 'or' or 'not', where no such set of trials is defined, is
%   refused with a word on what to write instead.
%
%   BASE is the expression without the tests ('all' when nothing is left:
%   every event), TESTS a struct array of them (empty when there are none).
%
%   See also DEFINEBINSENGINE.EVALUATEBINS, DEFINEBINSENGINE.SCANVALUETEST.
    kids = conjuncts(expr);
    tests = [];
    keep = {};
    for i = 1:numel(kids)
        kid = kids{i};
        if strcmp(kid.op, 'value') && DefineBinsEngine.isFilterTest(kid.test)
            if isempty(tests)
                tests = kid.test;
            else
                tests(end + 1) = kid.test; %#ok<AGROW>
            end
        else
            refuseNested(kid);
            keep{end + 1} = kid; %#ok<AGROW>
        end
    end
    if isempty(tests)
        base = expr;   % nothing taken out: the plan is what it always was
    elseif isempty(keep)
        base = struct('op', 'all');
    elseif isscalar(keep)
        base = keep{1};
    else
        base = struct('op', 'and');
        base.kids = keep;
    end
end

% ======================================================================= %
function kids = conjuncts(node)
%CONJUNCTS  The terms an expression's top level ands together, nested 'and'
%   (from parentheses) taken apart.
    if strcmp(node.op, 'and')
        kids = {};
        for i = 1:numel(node.kids)
            kids = [kids, conjuncts(node.kids{i})]; %#ok<AGROW>
        end
    else
        kids = {node};
    end
end

function refuseNested(node)
%REFUSENESTED  Refuse a test about the trials as a whole anywhere under NODE.
    switch node.op
        case 'value'
            if DefineBinsEngine.isFilterTest(node.test)
                refuse(node.test);
            end
        case 'not'
            refuseNested(node.kid);
        case {'and', 'or'}
            for i = 1:numel(node.kids)
                refuseNested(node.kids{i});
            end
    end
end

function refuse(test)
    if strcmp(test.source, 'rt') && strcmp(test.transform, 'none') ...
            && ~strcmp(test.window.lo.kind, 'stat') && ~strcmp(test.window.hi.kind, 'stat')
        why = 'a reaction time is the delay to the event the bin''s relation captured';
    else
        why = 'its ranks and statistics are those of the bin''s trials';
    end
    DefineBinsEngine.throwParseError(test.pos, sprintf([ ...
        '%s is about the bin''s trials as a whole (%s), so it has to be one of the ' ...
        'conditions every trial must meet: joined to the rest with and, not inside ' ...
        'or or not, I''m afraid. To keep the other trials, write the opposite window ' ...
        'instead, for example rank(rt) within (50, 100] rather than not rank(rt) ' ...
        'within [0, 50].'], test.text, why));
end
