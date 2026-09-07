% Text assembly (this whole package): strrep-based token substitution, NOT
% sprintf -- R's own pipe operator (%>%) is full of literal '%' characters
% that sprintf would misread as format specifiers, so every section is
% built by substituting __TOKEN__ placeholders into a literal template
% instead. Every label needs TWO escaped forms, since it can appear in two
% different contexts: __X_MD__ (mdLit-escaped) for Quarto markdown
% prose/headings, __X_R__ (rLit-escaped) for inside an R string literal in
% a code chunk, and __X_MDR__ for the third case that used to be missing --
% markdown prose EMITTED FROM a chunk, by cat() or sprintf().
%
% That third form is not a nicety. An ordinary condition name like
% 'targ_left' mdLit-escapes to 'targ\_left', and splicing that into an R
% string literal gives "targ\_left", where \_ is not a recognised R escape
% and the chunk fails to parse. It has to be escaped for BOTH layers, in
% that order: markdown first, then R.
%
% Escaping alone is still not enough where the text lands in a sprintf
% FORMAT string, because a label containing '%' (say '50% load') then
% parses cleanly and dies at run time. Labels belong in the ARGUMENT list.
function text = fillToken(text, token, value)
%FILLTOKEN  Substitute __TOKEN_MD__ (mdLit-escaped), __TOKEN_R__
%   (rLit-escaped) and __TOKEN_MDR__ (both, markdown then R) occurrences
%   of TOKEN with VALUE in TEXT. A no-op for
%   either placeholder VALUE does not contain (empty VALUE is passed
%   through as an empty string on both sides, matching a section that
%   does not use one of the two bin slots, e.g. descriptiveSection's
%   unused BIN2).
    % _MDR__ first: '__X_MD__' is a prefix of nothing here, but '__X_R__'
    % would otherwise never match inside '__X_MDR__'. Longest first is the
    % rule that keeps the three forms independent.
    text = strrep(text, ['__' token '_MDR__'], ...
        ReportSections.rLit(ReportSections.mdLit(value)));
    text = strrep(text, ['__' token '_MD__'], ReportSections.mdLit(value));
    text = strrep(text, ['__' token '_R__'], ReportSections.rLit(value));
end

