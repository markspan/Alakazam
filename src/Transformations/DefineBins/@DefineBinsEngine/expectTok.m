function [tok, rest] = expectTok(toks, kind, varargin)
%EXPECTTOK  expectTok(toks, kind, what) or expectTok(toks, kind, value, what)
    if numel(varargin) == 2
        wantVal = string(varargin{1}); what = varargin{2};
    else
        wantVal = ""; what = varargin{1};
    end
    if isempty(toks) || toks(1).kind ~= kind ...
            || (wantVal ~= "" && toks(1).val ~= wantVal)
        DefineBinsEngine.throwParseError(DefineBinsEngine.tokCol(toks), ...
            sprintf('I''m afraid I was expecting %s here.', what));
    end
    tok  = toks(1);
    rest = toks(2:end);
end
