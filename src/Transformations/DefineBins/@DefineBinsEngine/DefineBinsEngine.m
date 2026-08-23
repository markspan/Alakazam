classdef DefineBinsEngine
%DEFINEBINSENGINE  Bin-language lexer, parser, evaluator and epoch cutter
%   for DefineBins.m.
%
%   Holds no state -- every method is a pure function of its inputs -- so
%   this class exists only to give DefineBins' language implementation the
%   same one-method-per-file organisation @Alakazam/@WorkSpace use, instead
%   of packing lexer + parser + evaluator + epoch-cutter into one 1,500-line
%   file. DefineBins.m itself stays the callable transformation: the
%   Alakazam plugin contract dispatches transformations with
%   feval(transformId, EEG, ...) expecting a plain function returning
%   [EEG, options], which a same-named classdef cannot satisfy (a
%   constructor call returns exactly one object) -- so DefineBins.m remains
%   a plain function and delegates the language implementation to this
%   class's four public methods below.
%
%   Every other method here is Static and private: internal to the parser/
%   evaluator, reachable from sibling methods (but not from outside this
%   class) via DefineBinsEngine.methodName(...), the usual way MATLAB
%   resolves a call to a sibling static method.
%
%   See also DEFINEBINS, DEFINEBINSDIALOG.

    methods (Static)
        % Public surface: called by DefineBins.m. Implementations live in
        % @DefineBinsEngine/<name>.m.
        epochWin = parseEpochBounds(startStr, stopStr)
        spec = parseSpec(script)
        [EEG, bindesc, centerLat] = evaluateBins(EEG, bins)
        [EEG, bindesc] = cutEpochs(EEG, bindesc, win, centerLat)
    end

    methods (Static, Access = private)
        % Parser: script -> spec with .bins {index,label,text,expr}.
        % Implementations live in @DefineBinsEngine/<name>.m.
        spec = parseSpecInner(script)
        checkComboReferences(bins)
        bin = parseBinStatement(stmt, script, aliases)
        [name, node] = parseLetStatement(stmt, aliases)
        combo = parseCombo(T, binIndex, label)
        [iv, k] = scanRtWindow(T, k, binIndex)
        [rel, k] = parseTimelock(T, kStart, aliases, binIndex)
        [iv, k] = scanInterval(T, k)
        [v, k] = scanNum(T, k)
        t = tokAt(T, k)
        [tok, rest] = expectTok(toks, kind, varargin)
        c = tokCol(toks)
        txt = sliceSource(script, stmt)

        % Recursive-descent expression parser and its shared codeset/
        % tokenizer scanners.
        [node, k] = parseExprTokens(T, aliases)
        [node, k] = scanCodeset(T, k, aliases)
        node = combineOr(kids)
        node = anchorNode(codes)
        [node, k] = scanCodeElem(T, k, aliases)
        toks = tokenize(s)

        % Event context and predicate evaluation.
        [ctx, order] = buildContext(EEG)
        s = canonType(t)
        tf = matchCode(typStr, codes)
        rx = wildcardToRegex(c)
        [tf, cap] = evalNode(node, p, ctx)
        [tf, cap] = evalRel(node, p, ctx)
        [qLo, qHi] = windowRange(p, ctx, iv)
        idx = lowerBoundIdx(sortedLat, nValid, target)
        idx = upperBoundIdx(sortedLat, nValid, target)
        d = delta(q, p, ctx, iv)
        tf = inInterval(d, iv)

        % Friendly parse-error reporting.
        throwParseError(col, what)
        ME = wrapParseError(script, err)
        [lineTxt, lineNo, colInLine] = locateInScript(script, col)
    end
end
