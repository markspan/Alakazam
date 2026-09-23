function lines = template(name)
%TEMPLATE  A report template from src/Reports/rscripts, as report lines.
%   LINES = ReportDoc.template(NAME) reads src/Reports/rscripts/NAME, where
%   NAME carries its own extension, and returns the file's lines as a
%   1 x N cell array of char rows, ready to splice into the cell array a
%   section builds (see ReportDoc.lines). Nothing is added and nothing is
%   substituted: what the file holds is exactly what the report gets.
%
%   TWO KINDS OF TEMPLATE, told apart by their extension:
%     *.R     pure R, a library or one chunk's body. Valid R on its own, so
%             an editor highlights it and R's own parser can check it.
%     *.qmd   a Quarto fragment: markdown prose, "```{r}" fences and R
%             together, which is the natural unit for a whole section.
%   Both may carry __TOKEN__ placeholders, which the section builder fills
%   afterwards exactly as it always did (see ReportSections.fillToken); the
%   tokens are the interface between what MATLAB decides and what the
%   template says.
%
%   WHY THE R LIVES IN FILES. It used to live in MATLAB string literals,
%   about 960 lines of it, and that cost three things. Every quote in R had
%   to be doubled for MATLAB, which is where the \" versus \\ confusion in
%   this generator's history came from. No editor knew it was R, so nothing
%   checked its syntax until a Quarto render, and only where R is
%   installed. And an R user could not read it, which matters for code
%   whose whole output is a statistical argument.
%
%   THE TEMPLATES ARE INLINED at generation, not sourced at render. The
%   report stays one .qmd that reads its own sibling CSVs and nothing else,
%   so a report exported last year still renders without the repository
%   that made it. Sourcing these files from the document would make every
%   exported report depend on the vintage of the tree it came from, which
%   is the opposite of what a record is for.
%
%   See also REPORTDOC.LINES, REPORTSECTIONS.FILLTOKEN, REPORTDOC.APAHELPERS.
    file = fullfile(templateDir(), char(name));
    if exist(file, 'file') ~= 2
        throw(MException('Alakazam:ReportDoc:missingTemplate', ...
            ['I am afraid the report template "%s" could not be found. It should be the file\n\n' ...
             '    %s\n\nand ReportTemplatesTest checks that every template a report asks for is ' ...
             'there, and that every template there is asked for.'], char(name), file));
    end

    text = fileread(file);
    if ~isempty(text) && double(text(1)) == 65279     % a UTF-8 BOM, if an editor left one
        text = text(2:end);
    end
    text = strrep(text, sprintf('\r\n'), newline);
    lines = strsplit(text, newline, 'CollapseDelimiters', false);
    if ~isempty(lines) && isempty(lines{end})
        lines = lines(1:end - 1);                     % the file's own final newline
    end
end

% ======================================================================= %
function d = templateDir()
%TEMPLATEDIR  src/Reports/rscripts, found from this file rather than from
%   the working directory, which a report generator does not control.
    d = fullfile(fileparts(fileparts(mfilename('fullpath'))), 'rscripts');
end
