% Text assembly (this whole package): strrep-based token substitution, NOT
% sprintf -- R's own pipe operator (%>%) is full of literal '%' characters
% that sprintf would misread as format specifiers, so every section is
% built by substituting __TOKEN__ placeholders into a literal template
% instead. Every label needs TWO escaped forms, since it can appear in two
% different contexts: __X_MD__ (mdLit-escaped) for Quarto markdown
% prose/headings, __X_R__ (rLit-escaped) for inside an R string literal in
% a code chunk -- see this file.
function text = fillToken(text, token, value)
%FILLTOKEN  Substitute __TOKEN_MD__ (mdLit-escaped) and __TOKEN_R__
%   (rLit-escaped) occurrences of TOKEN with VALUE in TEXT. A no-op for
%   either placeholder VALUE does not contain (empty VALUE is passed
%   through as an empty string on both sides, matching a section that
%   does not use one of the two bin slots, e.g. descriptiveSection's
%   unused BIN2).
    text = strrep(text, ['__' token '_MD__'], ReportSections.mdLit(value));
    text = strrep(text, ['__' token '_R__'], ReportSections.rLit(value));
end

