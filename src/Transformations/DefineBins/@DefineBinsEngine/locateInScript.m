function [lineTxt, lineNo, colInLine] = locateInScript(script, col)
%LOCATEINSCRIPT  The 1-based line number and in-line column for a character
%   offset into SCRIPT, plus that line's own text (so the caller can print a
%   caret directly under the mistake).
    col = min(max(round(col), 1), numel(script));
    upToHere  = script(1:col);
    lineNo    = 1 + numel(strfind(upToHere, newline));
    lastNL    = find(upToHere == newline, 1, 'last');
    if isempty(lastNL); lineStart = 1; else; lineStart = lastNL + 1; end
    afterHere = script(col:end);
    nextNL    = find(afterHere == newline, 1, 'first');
    if isempty(nextNL); lineEnd = numel(script); else; lineEnd = col + nextNL - 2; end
    lineTxt   = script(lineStart:lineEnd);
    colInLine = col - lineStart + 1;
end
