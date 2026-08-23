function throwParseError(col, what)
%THROWPARSEERROR  Every low-level parsing/tokenizing method raises its
%   errors this way: COL is the character offset into the script where the
%   trouble is (or -1 when nothing more specific than "somewhere in this
%   bin" applies), and WHAT is a short, plain-English description, e.g.
%   'a closing '')'' to finish this window'. throwParseError never formats
%   the final message itself -- it just stashes col in the exception
%   identifier (a plain, un-escaped integer is safe there, unlike in the
%   message text) and lets whichever call wrapped the parse in a try/catch
%   (parseSpec, or a standalone caller replaying a script) turn it into the
%   friendly, in-context report wrapParseError builds, once, in one place,
%   for every one of these sites at once. This is why the individual
%   throwParseError call sites can stay short: they describe the *specific*
%   mistake, and the shared wrapper supplies the warmth, the source
%   snippet, and the caret.
    if isempty(col) || isnan(col); col = -1; end
    id = sprintf('Alakazam:DefineBins:ParseAtCol%d', max(round(col), 0));
    throw(MException(id, '%s', what));
end
