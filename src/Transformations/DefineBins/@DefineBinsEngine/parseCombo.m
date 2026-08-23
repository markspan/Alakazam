function combo = parseCombo(T, binIndex, label)
%PARSECOMBO  <coeff>? bin <n> ( ('+'|'-') <coeff>? bin <n> )*  -> struct(coeff, bin, pos)
%#ok<*AGROW>
    combo = struct('coeff', {}, 'bin', {}, 'pos', {});
    k = 1; sgn = 1;
    while true
        coeff = sgn;
        t = DefineBinsEngine.tokAt(T, k);
        if t.kind == "num"; coeff = sgn * t.val; k = k + 1; t = DefineBinsEngine.tokAt(T, k); end
        if ~(t.kind == "kw" && t.val == "bin")
            DefineBinsEngine.throwParseError(t.pos, sprintf([ ...
                'bin %g "%s" is defined as a combination of other bins (it has an ' ...
                '''='' after its label), so I was hoping to find ''bin <number>'' here -- ' ...
                'e.g. bin 2 - bin 1 -- but found something else instead.'], binIndex, label));
        end
        termPos = t.pos;
        k = k + 1;
        [num, k] = DefineBinsEngine.scanNum(T, k);
        combo(end+1) = struct('coeff', coeff, 'bin', round(num), 'pos', termPos);
        op = DefineBinsEngine.tokAt(T, k);
        if op.kind == "eof"
            break;
        elseif op.kind == "punc" && op.val == "+"
            sgn = 1; k = k + 1;
        elseif op.kind == "punc" && op.val == "-"
            sgn = -1; k = k + 1;
        else
            DefineBinsEngine.throwParseError(op.pos, sprintf([ ...
                'bin %g "%s": after a ''bin <n>'' term in a combination, I need a ''+'' ' ...
                'or ''-'' to know how to combine the next one (or nothing at all, to end ' ...
                'the combination there) -- for example, bin 2 - bin 1 + bin 3.'], binIndex, label));
        end
    end
end
