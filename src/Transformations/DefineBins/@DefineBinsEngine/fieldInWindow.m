function tf = fieldInWindow(node, p, ctx)
%FIELDINWINDOW  Evaluate a 'field' node: whether candidate event P's own
%   field NODE.name holds a number inside NODE.interval.
%
%   A value that is not one real number (missing, empty, NaN, text, a
%   vector) is not inside any window, so the test is false for it. That is
%   what keeps the last beat before a cut, whose interbeat interval the
%   Heartbeats plugin leaves NaN, out of every interval-based bin; written
%   under 'not', the same beat is in. A field no event has at all is
%   refused (fieldValue).
    v = DefineBinsEngine.fieldValue(node.name, p, ctx);
    tf = ~isnan(v) && DefineBinsEngine.inInterval(v, node.interval);
end
