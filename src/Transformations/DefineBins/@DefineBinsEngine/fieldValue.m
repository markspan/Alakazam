function v = fieldValue(name, p, ctx)
%FIELDVALUE  Candidate event P's own field NAME as one real number; NaN when
%   it holds anything else (missing, empty, NaN, text, a vector). With P
%   empty, only the check below.
%
%   A field that no event in the recording has at all is refused, with the
%   fields the events do have: the bin could match nothing, and the likely
%   cause is a typing slip or a step not run (Heartbeats, say).
    if ~isfield(ctx.ev, name)
        throw(MException('Alakazam:DefineBins', '%s', missingFieldMessage(name, ctx.ev)));
    end
    v = NaN;
    if isempty(p)
        return;
    end
    x = ctx.ev(p).(name);
    if (isnumeric(x) || islogical(x)) && isscalar(x) && isreal(x) && ~isnan(x)
        v = double(x);
    end
end

% ======================================================================= %
function msg = missingFieldMessage(name, ev)
%MISSINGFIELDMESSAGE  Why a field cannot be read here, with the fields that
%   are there and, when one differs only in case, that one.
    have = fieldnames(ev);
    msg = sprintf(['The bin script tests field %s, but the events of this recording ' ...
        'have no field of that name, I''m afraid.'], name);
    sameButCase = have(strcmpi(have, name));
    if ~isempty(sameButCase)
        msg = sprintf('%s Field names are case-sensitive: did you mean field %s?', ...
            msg, sameButCase{1});
    elseif any(strcmpi(name, {'ibi', 'hr'}))
        msg = sprintf(['%s The Heartbeats plugin gives every beat its ibi and hr: ' ...
            'has it been run on this recording, before DefineBins?'], msg);
    end
    msg = sprintf('%s The events have: %s.', msg, strjoin(have, ', '));
end
