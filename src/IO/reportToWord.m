function [docxFile, errorMessage] = reportToWord(htmlFile, opts)
%REPORTTOWORD  A Word copy of a rendered report, made from its HTML.
%   [DOCXFILE, ERRORMESSAGE] = reportToWord(HTMLFILE) converts HTMLFILE with
%   pandoc and returns the .docx written beside it. On failure DOCXFILE is
%   '' and ERRORMESSAGE says why, never thrown: the caller treats "no Word
%   copy" as a soft outcome, the same contract as renderQuartoReport.
%
%   Options: PandocExe to name the binary (tests use this), and Force to
%   convert even when an up-to-date .docx is already there.
%
%   CONVERTING THE HTML, NOT RE-RENDERING THE .qmd. Asking quarto for
%   `--to docx` is the obvious route and it destroys the results tables.
%   Three routes were rendered and the Word files opened up and inspected,
%   on the data quality report:
%
%       quarto --to docx                 data tables are NOT tables
%       quarto + gt::as_word raw block   data tables are NOT tables
%       pandoc on the finished HTML      data tables are real Word tables
%
%   "Not tables" is worse than missing: the cells arrive as one run of
%   text, so a column header row reads
%   "windowmeasurechannelbinpeopletrials_per_person...". Every figure
%   survives all three, sized to 5.83 inches, which is the text width of a
%   Word page. Pandoc is also the fastest by far, 1.2 s against 9, and is
%   the only one that needs no R.
%
%   WHY THE TABLES BREAK. Every data table in these reports is emitted as
%   cat(as_raw_html(apa_gt(...))) from inside a results:"asis" chunk, since
%   gt only auto-prints a table that is a chunk's sole top-level result and
%   these are built in loops (see ReportDoc.apaHelpers). Pandoc's Word
%   writer will not take raw HTML, so the markup is stripped and the text
%   inside it is kept.
%
%   The documented cure is to make that emission format-aware, with
%   knitr::knit_print or gt::as_word behind knitr::is_html_output. It was
%   tried, in the shared helper so that all six call sites would be covered
%   at once, and on gt 1.3.0 with knitr 1.50 it changed nothing: still not
%   tables. Rather than keep digging into gt's Word writer, note that
%   reading the finished HTML sidesteps the question entirely, since by
%   then the tables are ordinary HTML tables.
%
%   That also means this works on reports rendered before it existed, and
%   on a machine with no R at all.
%
%   THE .docx SITS BESIDE THE .html AND IS REUSED while it is newer, so a
%   second click opens the file that is already there.
%
%   See also RENDERQUARTOREPORT, PANDOCEXE, REPORTVIEW.
    arguments
        htmlFile (1, :) char
        opts.PandocExe (1, :) char = ''
        opts.Force (1, 1) logical = false
    end

    docxFile = '';
    errorMessage = '';

    if exist(htmlFile, 'file') ~= 2
        errorMessage = sprintf('There is no report file at %s.', htmlFile);
        return;
    end

    [folder, stem] = fileparts(htmlFile);
    wanted = fullfile(folder, [stem '.docx']);

    if ~opts.Force && isUpToDate(wanted, htmlFile)
        docxFile = wanted;
        return;
    end

    exe = opts.PandocExe;
    if isempty(exe)
        exe = pandocExe();
    end
    if isempty(exe)
        errorMessage = ['Pandoc could not be found, so there is nothing to make a ' ...
            'Word copy with. It ships with Quarto and with RStudio; installing ' ...
            'either one is enough.'];
        return;
    end

    % --standalone so the result is a document rather than a fragment.
    command = sprintf('"%s" "%s" --from html --to docx --standalone --output "%s"', ...
        exe, htmlFile, wanted);
    [status, output] = system(command);

    if status ~= 0 || exist(wanted, 'file') ~= 2
        errorMessage = strtrim(output);
        if isempty(errorMessage)
            errorMessage = sprintf('pandoc exited with status %d.', status);
        end
        return;
    end

    docxFile = wanted;
end

% ======================================================================= %
function tf = isUpToDate(docxFile, htmlFile)
%ISUPTODATE  Is there already a Word copy strictly newer than the report?
%
%   STRICTLY NEWER, AND THAT MATTERS MORE THAN IT LOOKS. The timestamps
%   this compares come from dir, which on this platform cannot tell apart
%   two files written 50 ms apart: measured, writing two files half a
%   tenth of a second apart gives them the same datenum. So "the same
%   second" and "stale by up to a second" are indistinguishable here.
%
%   Of the two ways to read that tie, only one is safe. Treating it as up
%   to date means a report re-rendered in the same second as its Word copy
%   opens the previous copy, showing numbers that are not in the report.
%   Treating it as stale costs one needless conversion of about a second.
    tf = false;
    if exist(docxFile, 'file') ~= 2
        return;
    end

    docxInfo = dir(docxFile);
    htmlInfo = dir(htmlFile);
    tf = docxInfo.datenum > htmlInfo.datenum;
end
