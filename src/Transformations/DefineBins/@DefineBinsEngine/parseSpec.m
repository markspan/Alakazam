function spec = parseSpec(script)
%PARSESPEC  Parse a DefineBins script into spec.bins, wrapping any parse
%   error into a warm, in-context, example-rich one (see wrapParseError).
    script = char(script);
    try
        spec = DefineBinsEngine.parseSpecInner(script);
    catch err
        throw(DefineBinsEngine.wrapParseError(script, err));
    end
end
