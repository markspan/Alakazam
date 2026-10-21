function text = describeTest(x)
%DESCRIBETEST  A value test written out as the script would write it, for
%   messages and the summary: 'rank(rt) within [0, 50]', 'rt within (0,
%   median] ms', 'field ibi within (p75 + 1.5 iqr, inf)'. Given one bound
%   of a window instead (a struct with .kind), that bound alone: 'mean +
%   2.5 sd'.
%
%   See also DEFINEBINSENGINE.SCANVALUETEST.
    if isfield(x, 'kind')
        text = boundText(x);
        return;
    end
    if strcmp(x.source, 'rt')
        value = 'rt';
    else
        value = ['field ' x.name];
    end
    if ~strcmp(x.transform, 'none')
        value = sprintf('%s(%s)', x.transform, value);
    end
    brackets = '[(';
    closers = '])';
    text = sprintf('%s within %c%s, %s%c', value, brackets(x.window.loOpen + 1), ...
        boundText(x.window.lo), boundText(x.window.hi), closers(x.window.hiOpen + 1));
    if strcmp(x.source, 'rt') && strcmp(x.transform, 'none')
        text = [text ' ms'];
    end
end

% ======================================================================= %
function text = boundText(b)
    switch b.kind
        case 'num'
            text = sprintf('%g', b.value);
        case 'inf'
            text = 'inf';
            if b.value < 0
                text = '-inf';
            end
        otherwise
            if strcmp(b.stat, 'p')
                text = sprintf('p%g', b.pct);
            else
                text = b.stat;
            end
            if b.k ~= 0
                signs = '+-';
                text = sprintf('%s %c %g %s', text, signs((b.k < 0) + 1), abs(b.k), b.spread);
            end
    end
end
