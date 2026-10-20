function tf = fieldInWindow(node, p, ctx)
%FIELDINWINDOW  Evaluate a 'field' node: whether candidate event P's own
%   field NODE.name holds a number inside NODE.interval.
%
%   A value that is not one real number (missing, empty, NaN, text, a
%   vector) is not inside any window, so the test is false for it. That is
%   what keeps the last beat before a cut, whose interbeat interval the
%   Heartbeats plugin leaves NaN, out of every interval-based bin; written
%   under 'not', the same beat is in.
%
%   A field that no event in the recording has at all is a different
%   matter: the bin could match nothing, and the likely cause is a typing
%   slip or a step not run (Heartbeats, say), so it is refused with the
%   fields the events do have, rather than left as an empty bin.
    name = node.name;
    if ~isfield(ctx.ev, name)
        throw(MException('Alakazam:DefineBins', '%s', missingFieldMessage(name, ctx.ev)));
    end
    v = ctx.ev(p).(name);
    tf = (isnumeric(v) || islogical(v)) && isscalar(v) && isreal(v) && ~isnan(v) ...
        && DefineBinsEngine.inInterval(double(v), node.interval);
end

function msg = missingFieldMessage(name, ev)
%MISSINGFIELDMESSAGE  Why a 'field' test cannot be evaluated here, with the
%   fields that are there and, when one differs only in case, that one.
    have = fieldnames(ev);
    msg = sprintf(['The bin script tests field %s, but the events of this recording ' ...
        'have no field of that name, I''m afraid.'], name);
    sameButCase = have(strcmpi(have, name));
    if ~isempty(sameButCase)
        msg = sprintf(['%s Field names are case-sensitive: did you mean field %s?'], ...
            msg, sameButCase{1});
    elseif any(strcmpi(name, {'ibi', 'hr'}))
        msg = sprintf(['%s The Heartbeats plugin gives every beat its ibi and hr: ' ...
            'has it been run on this recording, before DefineBins?'], msg);
    end
    msg = sprintf('%s The events have: %s.', msg, strjoin(have, ', '));
end
