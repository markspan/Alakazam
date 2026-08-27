classdef QuartoReportRSyntaxTest < matlab.unittest.TestCase
%QUARTOREPORTRSYNTAXTEST  Uses the installed R's OWN parser as the oracle
%   for the R that generateQuartoReport emits.
%
%   Every other test in this suite reasons about the generated document as
%   MATLAB text: it can pin which section builder ran, which literals it
%   spliced in and which columns it named, but it cannot tell whether the
%   result is valid R. That is not a hypothetical gap -- the escaping
%   helpers (rLit for the inside of an R string literal, mdLit for
%   markdown prose) are applied by hand, one call site at a time, and a
%   single mdLit-where-rLit-was-meant slip emits a document that is
%   perfectly well formed as markdown and a hard syntax error as R. No
%   MATLAB assertion can substitute for asking R itself.
%
%   So this file does exactly that, and nothing else: it extracts every
%   ```{r} chunk from each dispatch cell's report and hands the lot to
%   Rscript's parse(), and it executes the generated setup chunk against
%   the CSV the REAL exporter just wrote so the read/rename pipeline is
%   verified by running rather than by regex. The value of the second one
%   is that dplyr::rename ERRORS on a column that is not there -- a
%   substring check on a hand-written column list cannot fail that way,
%   and a renamed exporter column would sail past it.
%
%   Deliberately NOT here: anything about what the R computes. parse()
%   sees syntax only; it never looks at "#|" option lines (so a duplicate
%   chunk label is invisible to it) and it cannot know that a bin label
%   which parses cleanly today will still die inside a sprintf at render
%   time. Those belong to QuartoReportKnownGapTest and
%   QuartoReportRenderTest respectively.
%
%   Every method guards itself on ReportFixtures.rscriptExe() and skips
%   cleanly (assumeTrue, not a failure) when no R is installed; the setup
%   chunk case additionally guards on ReportFixtures.rPackagesPresent, so
%   that chunk's own install.packages() branch can never fire and reach
%   the network from inside a unit test.
%
%   Run with: runtests('tests/QuartoReportRSyntaxTest.m').

    properties (TestParameter)
        % One leg per report kind for setupChunkReadsTheExporterColumns.
        % The expected list is the post-rename one: the Spectral CSV's own
        % frequency_label column must appear here as "window", because the
        % setup chunk renames it once so no section builder has to care
        % which report kind it is filtering.
        reportKind = struct( ...
            'erp', struct('fixture', 'F-ERP2', 'stem', 'erp', 'columns', ...
                ['dataset,dataset_type,group,person_id,session,bin,channel,' ...
                 'window,measure_type,window_start_ms,window_stop_ms,value']), ...
            'spectral', struct('fixture', 'F-SPEC3C', 'stem', 'spectral', 'columns', ...
                ['dataset,dataset_type,group,person_id,session,bin,channel,' ...
                 'window,frequency_hz,reference,measure_type,value']));
    end

    methods (TestClassSetup)
        function addSourceToPath(testCase)
        %ADDSOURCETOPATH  src/IO (generateQuartoReport + the exporters),
        %   src/Support, and the tests folder itself so ReportFixtures
        %   resolves however runtests was invoked.
            here = fileparts(mfilename('fullpath'));
            root = fileparts(here);
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'IO')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'Support')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(here));
        end
    end

    methods (Test)
        function everyEmittedChunkParsesForEachDispatchCell(testCase)
        %EVERYEMITTEDCHUNKPARSESFOREACHDISPATCHCELL  Every ```{r} chunk of
        %   every one of the eight dispatch-cell fixtures is valid R.
        %
        %   One file per fixture, one Rscript call for all of them: R's
        %   ~0.4 s start-up dominates the actual parsing, so paying it
        %   once instead of eight times is the difference between a test
        %   that runs in a second and one nobody waits for.
        %
        %   The chunks of a fixture are joined by a BLANK line, which is
        %   load-bearing rather than cosmetic: joined by a single newline,
        %   one chunk's closing "}" splices onto the next chunk's first
        %   token and R reports an unexpected symbol in "}cat" -- a syntax
        %   error manufactured entirely by the concatenation. ReportFixtures.rCode
        %   already joins that way; this test depends on it doing so.
            testCase.assumeTrue(~isempty(ReportFixtures.rscriptExe()), ...
                'Rscript not found; skipping generated-R syntax checks.');

            folder = testCase.applyFixture( ...
                matlab.unittest.fixtures.TemporaryFolderFixture()).Folder;

            ids = ReportFixtures.censusIds();
            scriptFiles = cell(1, numel(ids));
            for k = 1:numel(ids)
                qmdText = generateQuartoReport(ReportFixtures.censusEntries(ids{k}), 'x.csv');
                scriptFiles{k} = fullfile(folder, [ids{k} '.R']);
                writeText(scriptFiles{k}, ReportFixtures.rCode(qmdText));
            end

            [status, output] = ReportFixtures.runRscript(parseDriver(scriptFiles));
            testCase.assertEqual(status, 0, ...
                sprintf('The parse driver itself failed to run.\nRscript said:\n%s', output));

            results = resultLines(output);
            testCase.verifyNumElements(results, numel(ids), ...
                sprintf(['The driver reported %d results for %d fixtures -- it did not ' ...
                         'examine every file.\nRscript said:\n%s'], ...
                        numel(results), numel(ids), output));

            failures = results(contains(results, 'FAIL'));
            testCase.verifyEmpty(failures, ...
                sprintf(['Generated R that R itself refuses to parse:\n%s'], ...
                        strjoin(failures, newline)));
        end

        function setupChunkReadsTheExporterColumns(testCase, reportKind)
        %SETUPCHUNKREADSTHEEXPORTERCOLUMNS  The generated setup chunk,
        %   EXECUTED against the CSV the real exporter just wrote, ends up
        %   with exactly the columns the rest of the report goes on to
        %   name -- the strongest available form of the CSV/report tie,
        %   with no MATLAB-side regex standing in for either side.
        %
        %   The Spectral leg is the interesting one: its CSV has no
        %   "window" column at all, only frequency_label, and the chunk's
        %   own dplyr::rename supplies it. Should the exporter ever rename
        %   that column, rename() raises an error here and the test fails
        %   on the R error, rather than a substring check quietly
        %   comparing two lists that no longer describe the same file.
            testCase.assumeTrue(~isempty(ReportFixtures.rscriptExe()), ...
                'Rscript not found; skipping generated-R syntax checks.');
            testCase.assumeTrue(ReportFixtures.rPackagesPresent(setupChunkPackages()), ...
                ['The setup chunk''s own R packages are not all installed; skipping ' ...
                 'rather than letting its install.packages() branch reach the network.']);

            folder = testCase.applyFixture( ...
                matlab.unittest.fixtures.TemporaryFolderFixture()).Folder;

            entries = ReportFixtures.censusEntries(reportKind.fixture);
            [qmdFile, csvFile] = ReportFixtures.writeReport(entries, folder, reportKind.stem);
            testCase.assertEqual(exist(csvFile, 'file'), 2, ...
                'The exporter wrote no CSV, so there is nothing to read back.');

            setupChunk = ReportFixtures.chunkFor(readText(qmdFile), 'setup');
            testCase.assertNotEmpty(setupChunk, ...
                'The generated report has no chunk labelled "setup".');

            [status, output] = ReportFixtures.runRscript( ...
                setupChunkDriver(folder, setupChunk));
            testCase.assertEqual(status, 0, ...
                sprintf('The generated setup chunk failed to run.\nRscript said:\n%s', output));
            testCase.verifySubstring(output, ['COLS|' reportKind.columns], ...
                sprintf(['The setup chunk did not end up with the columns the rest of the ' ...
                         'report names.\nRscript said:\n%s'], output));
        end
    end
end

% =========================================================================== %
%  Local helpers (callable only from the tests above)
% =========================================================================== %

function code = parseDriver(scriptFiles)
%PARSEDRIVER  R source that tryCatch(parse())es each of SCRIPTFILES and
%   cats one "<name>|OK" or "<name>|FAIL: <message>" line per file.
%
%   Every file is named explicitly rather than globbed, so a driver that
%   silently examines nothing (a mistyped pattern, an empty folder) shows
%   up as a result count the caller can assert on. The message has its own
%   newlines flattened to spaces: R's parse errors are multi-line, and one
%   result per line is what makes the output splittable at all.
    listing = strjoin(cellfun(@(f) ['"' forwardSlashes(f) '"'], ...
        scriptFiles(:)', 'UniformOutput', false), ', ');
    lines = { ...
        ['files <- c(' listing ')'] ...
        'for (f in files) {' ...
        '  msg <- tryCatch({ parse(file = f); "OK" },' ...
        '                  error = function(e) paste0("FAIL: ", conditionMessage(e)))' ...
        '  msg <- gsub("[[:space:]]+", " ", msg)' ...
        '  cat(basename(f), "|", msg, "\n", sep = "")' ...
        '}'};
    code = strjoin(lines, newline);
end

function code = setupChunkDriver(folder, setupChunk)
%SETUPCHUNKDRIVER  R source that runs SETUPCHUNK with FOLDER as the
%   working directory (the chunk references its CSV by bare name, exactly
%   as a render does) and then reports the resulting column names.
%
%   The chunk body is spliced in verbatim, "#|" option lines and all --
%   they are ordinary R comments, and leaving them in keeps this an
%   honest test of the text that actually ships.
    lines = { ...
        ['setwd("' forwardSlashes(folder) '")'] ...
        '' ...
        setupChunk ...
        '' ...
        'cat("COLS|", paste(names(dat), collapse = ","), "\n", sep = "")'};
    code = strjoin(lines, newline);
end

function lines = resultLines(output)
%RESULTLINES  The "<name>|<verdict>" lines of the parse driver's OUTPUT,
%   as a cellstr -- everything R prints on its own account (package
%   start-up notes and the like) carries no "|" and is dropped.
    lines = strsplit(char(output), {char(10), char(13)});
    lines = strtrim(lines);
    lines = lines(~cellfun(@isempty, lines));
    lines = lines(contains(lines, '|'));
end

function packages = setupChunkPackages()
%SETUPCHUNKPACKAGES  The package list the generated setup chunk itself
%   declares -- restated here only so this file can ASK whether they are
%   present before executing that chunk, never to assert anything about
%   it.
    packages = {'tidyverse', 'rstatix', 'ggpubr', 'gt', 'BayesFactor', ...
        'lme4', 'lmerTest', 'emmeans', 'performance', 'effectsize'};
end

function out = forwardSlashes(path)
%FORWARDSLASHES  PATH with Windows separators turned into forward slashes,
%   so it can be pasted into an R string literal without every separator
%   reading as an escape.
    out = strrep(char(path), '\', '/');
end

function writeText(path, text)
%WRITETEXT  Write TEXT to PATH verbatim -- fwrite, not fprintf, so a
%   stray '%' or '\' in the generated R survives intact.
    fid = fopen(path, 'w');
    if fid < 0
        throw(MException('Alakazam:QuartoReportRSyntaxTest:cannotWrite', ...
            'I am afraid I could not open "%s" for writing.', path));
    end
    closeFile = onCleanup(@() fclose(fid)); %#ok<NASGU>
    fwrite(fid, char(text), 'char');
end

function txt = readText(path)
%READTEXT  A whole text file as one char row vector.
    fid = fopen(path, 'r');
    if fid < 0
        throw(MException('Alakazam:QuartoReportRSyntaxTest:cannotRead', ...
            'I am afraid I could not open "%s" for reading.', path));
    end
    closeFile = onCleanup(@() fclose(fid)); %#ok<NASGU>
    txt = fread(fid, '*char')';
end
