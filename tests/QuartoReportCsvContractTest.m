classdef QuartoReportCsvContractTest < matlab.unittest.TestCase
%QUARTOREPORTCSVCONTRACTTEST  Ties the exported CSV's column contract to
%   the generated Quarto report that reads it, by EXECUTING both sides.
%
%   The contract exists twice, independently. src/IO/exportMeasurementsCSV.m
%   and src/IO/exportSpectralCSV.m each state it as a literal fprintf
%   format string; src/IO/generateQuartoReport.m and its +ReportSections
%   package state it again as column names hardcoded into the R they emit.
%   Nothing ties the two together -- they agree today by coincidence, not
%   by construction.
%
%   The failure mode that drift produces is unusually nasty. read_csv()
%   still succeeds (a CSV has no schema to violate), every dplyr filter
%   then matches nothing, and the report renders cleanly with every single
%   section reporting "Skipped: fewer than two subjects ...". That reads
%   to an analyst as a DATA problem -- a bad export, a mis-assigned group,
%   too few subjects -- rather than as a code defect, so the real cause
%   can sit unnoticed for a long time.
%
%   Every test here therefore runs the REAL exporter into a temporary
%   folder, reads the header back off disk, and censuses the REAL
%   generated .qmd against it. Neither side's column list is restated as
%   a MATLAB literal, so a rename on either side fails here with no
%   test-side edit needed. What IS stated literally is the PARTITION --
%   which columns the report consumes and which it ignores -- because
%   pinning the unconsumed half is what turns finding F2 (person_id and
%   session are written but never analysed, so two sessions of one person
%   are counted as two independent subjects) into a standing tripwire:
%   the day person_id is consumed, erpExporterHeaderPartition fails and
%   points the reader at its own KnownGap sibling
%   (QuartoReportKnownGapTest/generatedRReferencesPersonIdentifier) rather
%   than at a mystery.
%
%   This file is deliberately tool-free: it needs neither R nor Quarto, so
%   it runs in the fast inner loop. The stronger form of the same tie --
%   executing the generated setup chunk under Rscript and reading back
%   names(dat) -- lives in QuartoReportRSyntaxTest instead.
%
%   Shared fixtures come from tests/ReportFixtures.m (bin descriptors,
%   entry builders, the named census fixtures, and the real-CSV-plus-real-
%   .qmd writer), which is a static-method class and is never collected as
%   a test itself.
%
%   Nothing is ever written into the repository: every file goes into a
%   matlab.unittest.fixtures.TemporaryFolderFixture.
%
%   Run with: runtests('tests/QuartoReportCsvContractTest.m').

    properties (TestParameter)
        % One fixture per distinct measure_type expansion the two
        % exporters can produce: a single-type window, a two-type window,
        % a band-scoped Area window (three types), and the spectral pair
        % whose type list differs by the reference-channel branch.
        measureFixture = {'meanAmplitude', 'peak', 'bandPeakArea', ...
            'spectralNoRef', 'spectralWithRef'};
    end

    methods (TestClassSetup)
        function addSourceToPath(testCase)
        %ADDSOURCETOPATH  Put the exporters, the report generator, the
        %   src/Support helpers they share and the tests folder itself
        %   (so ReportFixtures resolves) on the path for this class.
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
        function erpExporterHeaderPartition(testCase)
        %ERPEXPORTERHEADERPARTITION  Every column exportMeasurementsCSV
        %   actually writes is partitioned by whether the generated ERP
        %   report references it as a standalone R identifier.
        %
        %   The eight consumed columns are the report's whole input; the
        %   four unconsumed ones are its blind spot. person_id and session
        %   being on the unconsumed side IS finding F2 (pseudoreplication:
        %   two sessions of one person are treated as two subjects),
        %   pinned here so that fixing it cannot pass unnoticed.
        %
        %   The standalone-identifier regex needs BOTH lookarounds: a bare
        %   'window' otherwise false-matches inside 'window_start_ms', and
        %   the whole partition collapses into "everything is consumed".
            folder = testCase.temporaryFolder();
            expectedHit  = {'bin', 'channel', 'dataset', 'dataset_type', ...
                'group', 'measure_type', 'value', 'window'};
            expectedMiss = {'person_id', 'session', 'window_start_ms', 'window_stop_ms'};

            for id = erpCensusIds()
                [columns, hit] = testCase.columnCensus(folder, id{1});
                testCase.verifyEqual(sort(columns(hit)), expectedHit, ...
                    sprintf('%s: the ERP report consumes a different set of CSV columns than expected.', id{1}));
                testCase.verifyEqual(sort(columns(~hit)), expectedMiss, ...
                    sprintf(['%s: the set of CSV columns the ERP report IGNORES has changed. ' ...
                    'If person_id or session just left this list, finding F2 has been addressed -- ' ...
                    'see QuartoReportKnownGapTest/generatedRReferencesPersonIdentifier.'], id{1}));
            end
        end

        function spectralExporterHeaderPartition(testCase)
        %SPECTRALEXPORTERHEADERPARTITION  The same census against
        %   exportSpectralCSV's own, different twelve-column header and a
        %   Spectral report.
        %
        %   frequency_label is the consumed one here (preambleText renames
        %   it to 'window' immediately after read_csv, so every section
        %   builder can go on hardcoding 'window =='), while frequency_hz
        %   and reference are written for a researcher's own use and never
        %   analysed -- alongside the same person_id/session blind spot the
        %   ERP side has.
            folder = testCase.temporaryFolder();
            expectedHit  = {'bin', 'channel', 'dataset', 'dataset_type', ...
                'frequency_label', 'group', 'measure_type', 'value'};
            expectedMiss = {'frequency_hz', 'person_id', 'reference', 'session'};

            for id = spectralCensusIds()
                [columns, hit] = testCase.columnCensus(folder, id{1});
                testCase.verifyEqual(sort(columns(hit)), expectedHit, ...
                    sprintf('%s: the Spectral report consumes a different set of CSV columns than expected.', id{1}));
                testCase.verifyEqual(sort(columns(~hit)), expectedMiss, ...
                    sprintf('%s: the set of CSV columns the Spectral report IGNORES has changed.', id{1}));
            end
        end

        function noPhantomColumnReferencedByGeneratedR(testCase)
        %NOPHANTOMCOLUMNREFERENCEDBYGENERATEDR  The reverse direction: the
        %   generated R must never ask `dat` for a column the exporter does
        %   not write.
        %
        %   Harvesting is anchored on the `dat` data frame itself -- the
        %   left-hand side of == / != / %in% and the argument of is.na()
        %   inside a filter() applied to a dat pipeline, the right-hand
        %   side of rename(window = X), and every dat$X / d$X / grp$X
        %   accessor. That anchoring is what removes any need for an
        %   allowlist of R-local variable names: anything piped out of dat
        %   is definitionally a CSV column, whereas an unanchored sweep
        %   would trip over R locals such as the `n` in
        %   filter(n == 2) (a count() result, not a column).
        %
        %   grp and d are included with dat because both are only ever
        %   built as `dat %>% filter(...) %>% droplevels()` and
        %   `grp %>% filter(...) %>% droplevels()` -- never mutated -- so
        %   their columns are dat's columns.
        %
        %   'window' is allowed on top of the exporter's own header
        %   because preambleText renames frequency_label to it for a
        %   Spectral report.
            folder = testCase.temporaryFolder();
            for id = [erpCensusIds(), spectralCensusIds()]
                entries = ReportFixtures.censusEntries(id{1});
                [qmdFile, csvFile] = ReportFixtures.writeReport(entries, folder, ['phantom-' id{1}]);
                columns = ReportFixtures.csvHeader(csvFile);
                referenced = datColumnReferences(fileread(qmdFile));

                testCase.verifyNotEmpty(referenced, ...
                    sprintf('%s: harvested no dat-anchored column references at all -- the harvester itself is broken.', id{1}));
                testCase.verifyEmpty(setdiff(referenced, [columns, {'window'}]), ...
                    sprintf(['%s: the generated R asks `dat` for a column the exporter never writes. ' ...
                    'Every filter/accessor above reads a CSV column, so a phantom name here means ' ...
                    'that filter silently matches nothing and its section reports "Skipped".'], id{1}));
            end
        end

        function measureTypeSetsAgreeBetweenCsvAndReport(testCase, measureFixture)
        %MEASURETYPESETSAGREEBETWEENCSVANDREPORT  Set equality, in both
        %   directions, between the measure_type values the exporter
        %   actually writes and the measure_type literals the report
        %   filters on.
        %
        %   Membership in one direction would not be enough. A report
        %   claiming a measure_type the exporter never writes produces a
        %   whole section that silently analyses nothing; an exporter
        %   writing one the report never mentions produces data nobody
        %   ever looks at. Both are drift, and both are caught only by
        %   asserting the two sets are EQUAL.
        %
        %   The spectral reference-channel branch is the live case where
        %   the two lists are conditionally different: coherence and
        %   phaselag exist on both sides only when the frequency was
        %   measured against a reference channel, and spectralBlocks
        %   (report) and exportSpectralCSV's own writeEntry (CSV) decide
        %   that independently of each other.
            folder = testCase.temporaryFolder();
            entries = fixtureEntries(measureFixture);
            [qmdFile, csvFile] = ReportFixtures.writeReport(entries, folder, ['types-' measureFixture]);

            fromCsv = unique(ReportFixtures.csvColumn(csvFile, 'measure_type'));
            fromReport = unique(regexpTokens(fileread(qmdFile), 'measure_type == "([a-z_]+)"'));

            testCase.verifyNotEmpty(fromCsv, 'The exporter wrote no measure_type rows at all.');
            testCase.verifyEqual(sort(fromReport), sort(fromCsv), ...
                sprintf(['%s: the measure_type values the CSV carries and the ones the report ' ...
                'filters on have drifted apart.'], measureFixture));
        end

        function datasetTypeLiteralAgrees(testCase)
        %DATASETTYPELITERALAGREES  The report's very first filter,
        %   filter(dataset_type == "subject"), must name the literal the
        %   exporter actually writes into the dataset_type column.
        %
        %   This one filter gates the entire document: a one-word change
        %   on either side ("subject" -> "subjects", or the exporter
        %   writing a differently-spelled datasetType) empties `dat`
        %   completely, and the report still renders -- as page after page
        %   of "Skipped".
        %
        %   The expected literal is read out of the CSV the exporter just
        %   wrote, never restated here.
            folder = testCase.temporaryFolder();
            for kind = {'meanAmplitude', 'spectralNoRef'}
                entries = fixtureEntries(kind{1});
                [qmdFile, csvFile] = ReportFixtures.writeReport(entries, folder, ['dstype-' kind{1}]);

                fromReport = regexpTokens(fileread(qmdFile), 'filter\(dataset_type == "([^"]*)"\)');
                testCase.verifyNumElements(fromReport, 1, ...
                    sprintf('%s: expected exactly one dataset_type filter in the generated R.', kind{1}));

                written = unique(ReportFixtures.csvColumn(csvFile, 'dataset_type'));
                testCase.verifyEqual(written, fromReport, ...
                    sprintf(['%s: the dataset_type literal the report filters on does not match what ' ...
                    'the exporter writes, so `dat` would be empty and every section would report "Skipped".'], kind{1}));
            end
        end
    end

    methods (Access = private)
        function folder = temporaryFolder(testCase)
        %TEMPORARYFOLDER  A scratch folder for this test's CSV/.qmd pair,
        %   removed automatically afterwards. Nothing is ever written into
        %   the repository.
            fixture = testCase.applyFixture( ...
                matlab.unittest.fixtures.TemporaryFolderFixture());
            folder = fixture.Folder;
        end

        function [columns, hit] = columnCensus(testCase, folder, id)
        %COLUMNCENSUS  ID's real CSV header, plus a logical mask of which
        %   of those columns the matching real .qmd references as a
        %   standalone R identifier.
            entries = ReportFixtures.censusEntries(id);
            [qmdFile, csvFile] = ReportFixtures.writeReport(entries, folder, ['census-' id]);
            columns = ReportFixtures.csvHeader(csvFile);
            testCase.verifyNumElements(columns, 12, ...
                sprintf('%s: the exporter header no longer has twelve columns.', id));
            hit = referencesColumns(fileread(qmdFile), columns);
        end
    end
end

% ======================================================================= %
%  Local helpers (house convention: after the classdef end)
% ======================================================================= %

function ids = erpCensusIds()
%ERPCENSUSIDS  The ReportFixtures census ids whose export is an ERP one --
%   grouped and ungrouped, one/two/three ordinary bins, with and without a
%   combination bin. All share exportMeasurementsCSV's header, so the
%   column partition must be identical across every one of them.
    ids = {'F-ERP1', 'F-ERP1G', 'F-ERP2', 'F-ERP2G', 'F-ERP3C', 'F-ERP3CG'};
end

function ids = spectralCensusIds()
%SPECTRALCENSUSIDS  The census ids whose export is a Spectral one, without
%   and with a reference channel.
    ids = {'F-SPEC3C', 'F-SPEC3CR'};
end

function entries = fixtureEntries(name)
%FIXTUREENTRIES  One named measure_type fixture, built from
%   ReportFixtures' own builders. A switch, never eval: the house standard
%   forbids eval anywhere, and a switch also keeps every fixture name
%   greppable.
    twoBins = ReportFixtures.bindesc({'A', 'B'});
    switch name
        case 'meanAmplitude'
            entries = ReportFixtures.erpEntries('Bindesc', twoBins, ...
                'Windows', {ReportFixtures.windowSpec('N400', 'Mean Amplitude')});
        case 'peak'
            entries = ReportFixtures.erpEntries('Bindesc', twoBins, ...
                'Windows', {ReportFixtures.windowSpec('N400', 'Peak')});
        case 'bandPeakArea'
            % A band-scoped Area window expands into THREE measure types
            % (area_signed + peak_amplitude + peak_latency), so this is
            % the fixture that exercises measureRowTypes' own branchiest
            % case on both sides at once.
            entries = ReportFixtures.erpEntries('Bindesc', twoBins, ...
                'Windows', {ReportFixtures.windowSpec('P300', 'Peak Area', ...
                    'Scope', 'band', 'Width', 50)});
        case 'spectralNoRef'
            entries = ReportFixtures.spectralEntries('Bindesc', twoBins, ...
                'Measures', {ReportFixtures.frequencySpec('10Hz')});
        case 'spectralWithRef'
            entries = ReportFixtures.spectralEntries('Bindesc', twoBins, ...
                'Measures', {ReportFixtures.frequencySpec('10Hz', 'RefChannel', 'Cz')});
        otherwise
            throw(MException('Alakazam:QuartoReportCsvContractTest:unknownFixture', ...
                'I am afraid "%s" is not one of this test class'' own fixtures.', name));
    end
end

function hit = referencesColumns(qmdText, columns)
%REFERENCESCOLUMNS  A logical mask over COLUMNS: true where QMDTEXT uses
%   that name as a STANDALONE identifier.
%
%   Both lookarounds are load-bearing. Without the trailing one, 'window'
%   matches inside 'window_start_ms' and the partition collapses; without
%   the leading one, a hypothetical 'id' column would match inside
%   'person_id'. The dot is in both character classes so that an R list
%   element such as '.groups' or a namespaced call cannot be mistaken for
%   a bare column reference either.
    hit = false(1, numel(columns));
    for c = 1:numel(columns)
        pattern = ['(?<![A-Za-z0-9_.])' regexptranslate('escape', columns{c}) '(?![A-Za-z0-9_.])'];
        hit(c) = ~isempty(regexp(qmdText, pattern, 'once'));
    end
end

function names = datColumnReferences(qmdText)
%DATCOLUMNREFERENCES  Every CSV column name the generated R actually asks
%   the `dat` data frame for, harvested from QMDTEXT.
%
%   Only R chunk bodies are searched (via ReportFixtures.rChunks), and
%   within each one string literals and comments are blanked first, so
%   markdown prose and a sprintf format string can never contribute a
%   spurious name or an unbalanced parenthesis to the scan.
    names = {};
    chunks = ReportFixtures.rChunks(qmdText);
    for k = 1:numel(chunks)
        code = blankStringsAndComments(chunks{k});

        for seg = datPipelines(code)
            names = [names, filterOperands(seg{1})]; %#ok<AGROW>
        end
        names = [names, regexpTokens(code, ...
            '(?<![A-Za-z0-9_.])(?:dat|grp|d)\$([A-Za-z_][A-Za-z0-9_.]*)')]; %#ok<AGROW>
        names = [names, regexpTokens(code, ...
            'rename\(\s*window\s*=\s*([A-Za-z_][A-Za-z0-9_.]*)\s*\)')]; %#ok<AGROW>
    end
    names = unique(names);
end

function segments = datPipelines(code)
%DATPIPELINES  Every dplyr pipeline in CODE whose head is the `dat` data
%   frame -- either `dat <- read_csv(...)` (the one that creates it) or
%   any later `dat %>% ...` -- as a cell array of text spans.
    segments = {};
    starts = regexp(code, '(?<![A-Za-z0-9_.])dat(?![A-Za-z0-9_.])\s*(?:<-\s*read_csv|%>%)', 'start');
    for k = 1:numel(starts)
        segments{end + 1} = pipelineSpan(code, starts(k)); %#ok<AGROW>
    end
end

function span = pipelineSpan(code, from)
%PIPELINESPAN  CODE from FROM to the end of that statement: a newline at
%   parenthesis depth zero ends it, UNLESS the text so far ends with a
%   pipe or a comma, which is how the generated R wraps a long filter over
%   two lines.
    depth = 0;
    stop = numel(code);
    for i = from:numel(code)
        switch code(i)
            case '('
                depth = depth + 1;
            case ')'
                depth = depth - 1;
            case newline
                if depth <= 0
                    sofar = strtrim(code(from:i - 1));
                    if ~(endsWith(sofar, '%>%') || endsWith(sofar, ','))
                        stop = i - 1;
                        break;
                    end
                end
        end
    end
    span = code(from:max(stop, from));
end

function names = filterOperands(span)
%FILTEROPERANDS  Every column name compared inside a filter() call in
%   SPAN: the left-hand side of ==, != or %in%, plus the argument of
%   is.na().
    names = {};
    opens = regexp(span, '(?<![A-Za-z0-9_.])filter\s*\(', 'end');
    for k = 1:numel(opens)
        body = balancedBody(span, opens(k));
        names = [names, regexpTokens(body, ...
            '(?<![A-Za-z0-9_.$])([A-Za-z_][A-Za-z0-9_.]*)\s*(?:==|!=|%in%)')]; %#ok<AGROW>
        names = [names, regexpTokens(body, ...
            'is\.na\(\s*([A-Za-z_][A-Za-z0-9_.]*)\s*\)')]; %#ok<AGROW>
    end
end

function body = balancedBody(span, openIdx)
%BALANCEDBODY  The text between the parenthesis at OPENIDX in SPAN and its
%   matching close.
    depth = 0;
    stop = numel(span);
    for i = openIdx:numel(span)
        if span(i) == '('
            depth = depth + 1;
        elseif span(i) == ')'
            depth = depth - 1;
            if depth == 0
                stop = i - 1;
                break;
            end
        end
    end
    body = span(min(openIdx + 1, numel(span)):max(stop, openIdx));
end

function code = blankStringsAndComments(code)
%BLANKSTRINGSANDCOMMENTS  CODE with every double-quoted R string literal
%   and every #-to-end-of-line comment replaced by spaces of the same
%   length, so that positions are preserved while their contents can no
%   longer unbalance a parenthesis scan or contribute a false identifier.
%
%   Only double quotes delimit a string here: the generated R uses them
%   throughout, whereas an apostrophe appears constantly inside prose and
%   comments ("Cohen's d", "subject's own"), so treating one as a
%   delimiter would corrupt the rest of the chunk.
    inString = false;
    escaped = false;
    inComment = false;
    for i = 1:numel(code)
        c = code(i);
        if inString
            if escaped
                escaped = false;
            elseif c == '\'
                escaped = true;
            elseif c == '"'
                inString = false;
            end
            code(i) = ' ';
        elseif inComment
            if c == newline
                inComment = false;
            else
                code(i) = ' ';
            end
        elseif c == '"'
            inString = true;
            code(i) = ' ';
        elseif c == '#'
            inComment = true;
            code(i) = ' ';
        end
    end
end

function tokens = regexpTokens(txt, pattern)
%REGEXPTOKENS  Every first capture group PATTERN matches in TXT, as a
%   1 x n cellstr (regexp's own nested-cell 'tokens' shape flattened).
    raw = regexp(txt, pattern, 'tokens');
    tokens = cell(1, numel(raw));
    for k = 1:numel(raw)
        tokens{k} = raw{k}{1};
    end
end
