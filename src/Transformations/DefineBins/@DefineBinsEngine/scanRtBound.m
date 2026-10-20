function [bound, k] = scanRtBound(T, k, binIndex)
%SCANRTBOUND  One bound of an 'rt within' window: a number of milliseconds,
%   or a bound relative to the bin's own reaction times.
%
%       <num>                      a fixed bound, in ms
%       mean                       the mean reaction time
%       mean (+|-) <num> sd        the mean plus or minus NUM standard deviations
%
%   BOUND is struct('value', v, 'sd', s). A fixed bound has its value in v
%   and NaN in s; a relative bound has NaN in v and the signed multiplier of
%   the standard deviation in s (0 for a bare 'mean').
%
%   'mean' and 'sd' are read here as plain words, not as keywords of the
%   language, so a let alias may still be called mean or sd: they mean
%   something only inside a reaction-time window, where no alias can stand.
    t = DefineBinsEngine.tokAt(T, k);

    if t.kind == "num"
        % A number directly followed by 'sd' is a relative bound with its
        % 'mean' left out; saying so beats a puzzling "expected a comma".
        if isWord(DefineBinsEngine.tokAt(T, k + 1), "sd")
            DefineBinsEngine.throwParseError(t.pos, sprintf([ ...
                'bin %g: a bound in standard deviations is measured from the mean, so ' ...
                'it needs the word mean in front of it, I''m afraid: mean + %g sd ' ...
                'rather than %g sd.'], binIndex, abs(t.val), t.val));
        end
        bound = struct('value', t.val, 'sd', NaN);
        k = k + 1;
        return;
    end

    if ~isWord(t, "mean")
        DefineBinsEngine.throwParseError(t.pos, sprintf([ ...
            'bin %g: each bound of a reaction-time window is either a number of ' ...
            'milliseconds or relative to the mean reaction time, for example ' ...
            'rt within (150, mean + 2.5 sd] ms -- I''m afraid I could not read ' ...
            'this one as either.'], binIndex));
    end
    k = k + 1;

    % 'mean' on its own: nothing more to read.
    s = DefineBinsEngine.tokAt(T, k);
    if s.kind == "punc" && (s.val == "," || s.val == ")" || s.val == "]")
        bound = struct('value', NaN, 'sd', 0);
        return;
    end

    % The sign: an explicit + or -, or (since the tokenizer reads "-2.5" as
    % one negative number) a number that carries its own minus.
    if s.kind == "punc" && (s.val == "+" || s.val == "-")
        direction = 1 - 2 * (s.val == "-");
        k = k + 1;
        n = DefineBinsEngine.tokAt(T, k);
        if n.kind ~= "num"
            DefineBinsEngine.throwParseError(n.pos, sprintf([ ...
                'bin %g: after mean %s I was hoping to find how many standard ' ...
                'deviations, for example mean %s 2.5 sd, but did not, I''m afraid.'], ...
                binIndex, s.val, s.val));
        end
        multiplier = direction * n.val;
    elseif s.kind == "num" && s.val < 0
        n = s;
        multiplier = s.val;
    else
        DefineBinsEngine.throwParseError(s.pos, sprintf([ ...
            'bin %g: after mean I expected + or - and a number of standard ' ...
            'deviations, for example mean + 2.5 sd, or the end of the bound, ' ...
            'I''m afraid.'], binIndex));
    end
    k = k + 1;

    if ~isWord(DefineBinsEngine.tokAt(T, k), "sd")
        DefineBinsEngine.throwParseError(n.pos + n.len, sprintf([ ...
            'bin %g: I''m afraid a number added to the mean needs the word sd after ' ...
            'it, so it is clear that it counts standard deviations: mean + %g sd. A ' ...
            'fixed number of milliseconds belongs in a bound of its own.'], ...
            binIndex, abs(multiplier)));
    end
    bound = struct('value', NaN, 'sd', multiplier);
    k = k + 1;
end

function tf = isWord(t, word)
%ISWORD  Whether token T is the plain word WORD, in any case.
    tf = t.kind == "ident" && strcmpi(t.val, word);
end
