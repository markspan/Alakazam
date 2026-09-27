function win = parseEpochStatement(stmt)
%PARSEEPOCHSTATEMENT  'epoch [lo,hi] ms' -> the window to cut around each
%   matched event, struct(lo, hi, unit) as cutEpochs takes it.
%
%   The same interval notation as a relation's window, so a script reads the
%   same way throughout: epoch [-200,800] ms, or [-50,200] samples. An epoch
%   always keeps both of its ends, so round and square brackets mean the
%   same here; they are accepted for symmetry rather than meaning.
%
%   'events' is refused: it counts positions in the event stream, which is
%   no length of data to cut.
    [iv, k] = DefineBinsEngine.scanInterval(stmt, 2);
    if k <= numel(stmt)
        extra = stmt(k);
        DefineBinsEngine.throwParseError(extra.pos, [ ...
            'An epoch line holds one window and nothing after it, I''m afraid, for ' ...
            'example:' newline newline '    epoch [-200,800] ms' newline newline ...
            'Would you move whatever follows it onto a line of its own?']);
    end
    if strcmp(iv.unit, 'events')
        DefineBinsEngine.throwParseError(stmt(1).pos, [ ...
            'An epoch is a stretch of data, so it is measured in ms or samples, not ' ...
            'in events, I''m afraid. Would you write it as, for example, ' ...
            'epoch [-200,800] ms?']);
    end
    if iv.hi <= iv.lo
        DefineBinsEngine.throwParseError(stmt(1).pos, sprintf([ ...
            'This epoch ends (%g) where it starts or before (%g), I''m afraid, so there ' ...
            'is no data to cut. A window like epoch [-200,800] ms covers 200 ms before ' ...
            'each event to 800 ms after it.'], iv.hi, iv.lo));
    end
    win = struct('lo', iv.lo, 'hi', iv.hi, 'unit', iv.unit);
end
