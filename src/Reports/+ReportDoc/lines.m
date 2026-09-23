function flat = lines(parts)
%LINES  One flat list of report lines from a list that holds blocks.
%   FLAT = ReportDoc.lines(PARTS) walks the cell array PARTS and returns a
%   1 x N cell array of char rows: a char element is one line, and a cell
%   element is a block of lines spliced in where it sits, to any depth.
%
%   WHY IT EXISTS. A section builder writes its document as a cell array of
%   lines, and since ReportDoc.rscript returns a block of them, splicing
%   one in would otherwise mean breaking the literal into
%   [{...}, block, {...}] at every site. Wrapping the literal instead keeps
%   the builders shaped the way they already are, and everything downstream
%   still receives the same flat list of lines it always did.
%
%   A string is accepted and converted, so a builder that has moved to
%   string arrays does not have to convert at the call site. Anything else
%   is refused by name, because a numeric line silently becomes a character
%   in the report otherwise (sprintf is how a number belongs here).
%
%   See also REPORTDOC.RSCRIPT.
    if ~iscell(parts)
        parts = {parts};
    end
    flat = {};
    for i = 1:numel(parts)
        part = parts{i};
        if iscell(part)
            flat = [flat, ReportDoc.lines(part)]; %#ok<AGROW>
        elseif ischar(part) && (isrow(part) || isempty(part))
            flat{end + 1} = part; %#ok<AGROW>
        elseif isstring(part) && isscalar(part)
            flat{end + 1} = char(part); %#ok<AGROW>
        elseif isstring(part)
            flat = [flat, cellstr(reshape(part, 1, []))]; %#ok<AGROW>
        else
            throw(MException('Alakazam:ReportDoc:badLine', ...
                ['A report line has to be text, or a cell array of text to splice in; element %d ' ...
                 'of this one is a %s. A number belongs here through sprintf.'], i, class(part)));
        end
    end
end
