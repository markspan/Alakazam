function [vars, pairs] = formulaVariables(formula)
%FORMULAVARIABLES  The event fields a formula names, whether each is a
%   factor (inside cat()) and whether it is a spline's (inside spl(),
%   circspl() or 2dspl()). Everything that is a name and not one of Unfold's
%   term functions, or the response y, is a field. A name has to start the
%   word: Unfold spells its 2D spline 2dspl, which once read as a field
%   called "dspl". PAIRS lists each 2dspl's two fields, {x, z}, in order.
%
%   See also UNFOLD.BINMODEL, UNFOLD.POOLEDVALUES.
    rhs = regexprep(formula, '^[^~]*~', '');
    names = unique(regexp(rhs, '(?<![\w.])[A-Za-z_]\w*', 'match'), 'stable');
    % A row, even when empty: a 0x1 list would still take one turn of a for
    % loop over its columns.
    names = reshape(setdiff(names, {'y', 'cat', 'spl', 'circspl'}, 'stable'), 1, []);
    factors = cellfun(@(t) t{1}, regexp(rhs, '(?<!\w)cat\s*\(\s*([A-Za-z_]\w*)', 'tokens'), ...
        'UniformOutput', false);
    splines = cellfun(@(t) t{1}, regexp(rhs, '(?<!\w)(?:spl|circspl)\s*\(\s*([A-Za-z_]\w*)', 'tokens'), ...
        'UniformOutput', false);
    pairs = regexp(rhs, '(?<!\w)2dspl\s*\(\s*([A-Za-z_]\w*)\s*,\s*([A-Za-z_]\w*)', 'tokens');
    surfaces = [pairs{:}];
    vars = struct('name', names, 'categorical', num2cell(ismember(names, factors)), ...
        'spline', num2cell(ismember(names, [splines, surfaces])));
end
