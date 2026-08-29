classdef (TestTags = {'KnownGap'}) QuartoReportKnownGapTest < matlab.unittest.TestCase
%QUARTOREPORTKNOWNGAPTEST  The expected-red file: a defect register that
%   cannot go stale, because it runs against the code.
%
%   Every case here asserts the CORRECT contract for a defect that
%   src/IO/generateQuartoReport.m and src/IO/+ReportSections still have,
%   so every case FAILS today, deliberately. The whole class carries
%   TestTags = {'KnownGap'} so a default run can exclude it with
%   HasTag('KnownGap') and stay green, while a report-only continuous-
%   integration leg runs the tag on purpose -- which is what makes an
%   accidental fix visible rather than silently un-noted.
%
%   Why not simply assert the current behaviour instead? MATLAB's unittest
%   framework has no xfail. Pinning the WRONG answer would cement each bug
%   into the suite and make the eventual fix look like a regression;
%   pinning the RIGHT answer un-quarantined would leave the suite
%   permanently red and train everyone to ignore it. The tag lane is the
%   third option: the assertions state what the code SHOULD do, they are
%   readable as a specification, and the day one is fixed its case simply
%   turns green.
%
%   The gaps, and the fix each case is waiting for:
%
%     F1  CIRCULAR MEASURE TYPES ROUTE INTO LINEAR TESTS.
%         generateQuartoReport's ordinary-bin dispatch (the 1/2/3+
%         if-chain) never consults ReportSections.isCircularType or
%         ReportSections.isDescriptiveOnlyType -- only the COMBINATION-bin
%         branch below it does. A Spectral export's 'phase' and 'phaselag'
%         are angles that wrap at +/-pi, yet they route into
%         lmmSection/pairedSection/descriptiveSection and
%         are handed lmerTest::lmer and mean(value)/sd(value). Expected
%         fix: consult isCircularType in the ordinary-bin branch too and
%         emit a descriptive (or genuinely circular) section instead.
%         Cases: circularTypeNeverRoutesToLinearOmnibus,
%         sameDocumentNeverContradictsItselfOnCircularType,
%         circularTypeNeverRoutesToMixedModel,
%         phaselagWithReferenceChannelNeverRoutesToLinearOmnibus.
%
%     F2  CLOSED. The person identifier was exported and then ignored, so
%         two sessions of one person were analysed as two independent
%         subjects. The random effect is now grouped by person_id rather
%         than by the recording, and the preamble falls back to the
%         recording where no person was set -- which is what personFor
%         itself does, so single-session studies are unaffected. Its case
%         has left this register; the contract is pinned properly in
%         tests/QuartoReportPersonGroupingTest.m, and the model choice it
%         belongs to is decided in src/IO/reportDesignPlan.m.
%
%     SIGN  THE PAIRED EFFECT SIZE DISAGREES WITH ITS OWN t.
%         pairedSection computes t.test(wide[[BIN2]], wide[[BIN1]]) --
%         bin2 minus bin1, in EEG.bindesc order -- but takes Cohen's dz
%         from rstatix::cohens_d(value ~ bin, paired = TRUE), which is
%         level1 minus level2 in ALPHABETICAL order, because preambleText
%         does mutate(bin = factor(bin)). Whenever bindesc order happens to
%         be alphabetical (the overwhelmingly common case) the reported t
%         and the reported dz carry opposite signs in the same sentence.
%         Expected fix: give cohens_d an explicitly ordered factor, or
%         compute dz from the same difference vector t.test uses.
%         Case: pairedEffectSizeSignMatchesTestStatistic.
%
%     ZERO  A DESIGN WITH NO ORDINARY BINS FAILS SILENTLY.
%         When every EEG.bindesc entry carries a .combo, classifyBins
%         returns zero ordinary labels and the 1/2/3+ if-chain has no
%         else, so no omnibus section is emitted at all and nothing says
%         so. The report still has headings, still renders, and still ends
%         with its summary -- a complete-looking document whose main
%         comparison is simply missing. Expected fix: either refuse the
%         export, or state in the report that there are no ordinary
%         condition bins to compare.
%         Case: zeroOrdinaryBinsIsNotSilent.
%
%     LABEL  CHUNK LABELS ARE NOT UNIQUE.
%         ReportSections.labelPiece is lossy (it lowercases and collapses
%         every non-alphanumeric run to a hyphen), so two different window
%         labels can sanitise to the same chunk label. knitr rejects a
%         duplicate label at render time, and R's own parse() cannot see
%         it, because parse() never looks at '#|' option lines. Expected
%         fix: de-duplicate labels within a document.
%         Case: chunkLabelsAreUniqueWithinADocument.
%
%     ESCAPE  THE MARKDOWN ESCAPING LEAKS INTO R STRING LITERALS.
%         A label bound for an R double-quoted string must go through
%         ReportSections.rLit; one bound for markdown prose through
%         ReportSections.mdLit. pairedSection splices an mdLit-escaped
%         token INSIDE an R string literal, so a routine EEG condition
%         name such as 'targ_left' emits "targ\_left" into R, where '\_'
%         is an unrecognised escape, and 'say "hi"' terminates the literal
%         outright. A bin label also lands inside a sprintf FORMAT string,
%         so '50% load' parses cleanly and then dies at run time, swallowed
%         by the per-channel tryCatch into a bland italic note. Expected
%         fix: rLit for anything inside R source; pass labels as sprintf
%         ARGUMENTS, never as part of the format.
%         Cases: mdLitFormNeverLeaksIntoRChunks,
%         underscoreBinLabelStillParsesAsR,
%         doubleQuoteBinLabelStillParsesAsR, percentBinLabelSurvivesSprintf.
%
%   Most cases are pure MATLAB string work and run in about a second, so
%   they can guard a fix in a fast inner loop. The three R-parse cases
%   guard themselves on ReportFixtures.rscriptExe; the sign-invariant and
%   the percent-label render leg additionally on ReportFixtures.quartoExe.
%   Each method guards ITSELF, so on a machine with no R the file degrades
%   case by case rather than skipping wholesale.
%
%   Every fixture comes from tests/ReportFixtures.m -- deliberately, so a
%   fix can be checked against the very same fixtures the green dispatch,
%   text-contract, CSV-contract, syntax and render files use.
%
%   Run with: runtests('tests/QuartoReportKnownGapTest.m').

    methods (TestClassSetup)

        function addSourceToPath(testCase)
        %ADDSOURCETOPATH  Put the code under test (src/IO, which carries
        %   the +ReportSections package, and src/Support) and the tests
        %   folder itself (for ReportFixtures) on the path for this class.
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

        % ================================================================ %
        %  F1 -- circular measure types routed into linear tests
        % ================================================================ %

        function circularTypeNeverRoutesToLinearOmnibus(testCase)
        %CIRCULARTYPENEVERROUTESTOLINEAROMNIBUS  EXPECTED RED (gap F1).
        %   A Spectral export's 'phase' is a circular quantity, so the
        %   ungrouped 3+-bin path must not build it a linear omnibus
        %   section at all.
        %
        %   Sliced by CHUNK LABEL rather than searched document-wide,
        %   because lmerTest::lmer is perfectly legitimate elsewhere in
        %   this same document (for 'power', 'amplitude', 'snr', 'itc') --
        %   a document-wide search would therefore be unable to state this
        %   at all.
        %
        %   Fails today: the 'anova-10hz-phase' chunk exists, and contains
        %   both a mixed model and a linear mean/SD summary of angles.
            txt = generateQuartoReport(ReportFixtures.censusEntries('F-SPEC3C'), 'x.csv');
            slice = ReportFixtures.chunkFor(txt, 'anova-10hz-phase');

            testCase.verifyEmpty(slice, ...
                'A circular measure type (phase) must not be given a linear omnibus section.');
            testCase.verifyFalse(contains(slice, 'lmerTest::lmer'), ...
                'A linear mixed model was fitted to angles that wrap at +/-pi.');
            testCase.verifyFalse(contains(slice, 'summarise(M = mean(value), SD = sd(value)'), ...
                'A linear mean/SD was computed over angles that wrap at +/-pi.');
        end

        function sameDocumentNeverContradictsItselfOnCircularType(testCase)
        %SAMEDOCUMENTNEVERCONTRADICTSITSELFONCIRCULARTYPE  EXPECTED RED
        %   (gap F1), and the sharpest available statement of it: it needs
        %   no knowledge of circular scales from the reader at all.
        %
        %   The combination-bin branch consults isDescriptiveOnlyType and
        %   therefore refuses 'phase' a linear test (emitting the
        %   'combo-desc-' section); the ordinary-bin branch does not
        %   consult it and grants 'phase' a linear omnibus in the very same
        %   document. Whichever way the gap is eventually fixed, both
        %   cannot be right at once -- so this assertion stays valid under
        %   ANY fix and prejudges none of them.
        %
        %   Fails today: both labels are present.
            txt = generateQuartoReport(ReportFixtures.censusEntries('F-SPEC3C'), 'x.csv');

            linearOmnibus = contains(txt, '#| label: anova-10hz-phase');
            refusedAsCombo = contains(txt, '#| label: combo-desc-10hz-phase-a-b');

            testCase.verifyFalse(linearOmnibus && refusedAsCombo, ...
                ['The same report refuses "phase" a linear test as a combination bin ' ...
                 'and grants it one as an ordinary bin.']);
        end

        function circularTypeNeverRoutesToMixedModel(testCase)
        %CIRCULARTYPENEVERROUTESTOMIXEDMODEL  EXPECTED RED (gap F1), on
        %   the GROUPED destination, which is a different line of the
        %   dispatch from the ungrouped one and so needs its own case: a
        %   fix applied to the ungrouped branch alone would leave this one
        %   red.
        %
        %   Fails today: the grouped Spectral report contains a
        %   'mixed-10hz-phase' chunk.
            entries = ReportFixtures.spectralEntries( ...
                'Bindesc', ReportFixtures.bindesc3WithCombo(), ...
                'Measures', {ReportFixtures.frequencySpec('10Hz')}, ...
                'Groups', {'ctrl', 'patient'});
            txt = generateQuartoReport(entries, 'x.csv');

            testCase.verifyEmpty(ReportFixtures.chunkFor(txt, 'mixed-10hz-phase'), ...
                'A circular measure type (phase) must not be given a linear mixed model.');
        end

        function phaselagWithReferenceChannelNeverRoutesToLinearOmnibus(testCase)
        %PHASELAGWITHREFERENCECHANNELNEVERROUTESTOLINEAROMNIBUS  EXPECTED
        %   RED (gap F1), on the SECOND circular measure type. 'phaselag'
        %   exists only when a frequency was measured against a reference
        %   channel (see spectralBlocks), so it is reachable only through
        %   that branch and cannot be covered by the 'phase' cases above.
        %
        %   Fails today: the reference-channel report adds an
        %   'anova-10hz-phaselag' chunk.
            txt = generateQuartoReport(ReportFixtures.censusEntries('F-SPEC3CR'), 'x.csv');

            testCase.verifyEmpty(ReportFixtures.chunkFor(txt, 'anova-10hz-phaselag'), ...
                'A circular measure type (phaselag) must not be given a linear omnibus section.');
        end


        % ================================================================ %
        %  The paired effect size's sign
        % ================================================================ %

        function pairedEffectSizeSignMatchesTestStatistic(testCase)
        %PAIREDEFFECTSIZESIGNMATCHESTESTSTATISTIC  EXPECTED RED (gap
        %   SIGN), and the costliest to see: it needs a real render,
        %   because the disagreement is between two R calls, not between
        %   two pieces of MATLAB text.
        %
        %   The invariant is asserted, never the literal signs, so the case
        %   survives any change of fixture: whatever direction the report
        %   chooses to describe, its t and its Cohen's dz must agree about
        %   it, since they appear in the same APA sentence.
        %
        %   Fails today: the ground-truth fixture renders
        %   t(24) = 10.00 alongside Cohen's dz = -2.00.
            testCase.assumeTrue(~isempty(ReportFixtures.rscriptExe()) ...
                && ~isempty(ReportFixtures.quartoExe()), ...
                'R and/or Quarto not found; skipping the render-based sign check.');

            folder = temporaryFolder(testCase);
            entries = ReportFixtures.pairedGroundTruthEntries();
            qmdFile = ReportFixtures.writeReport(entries, folder, 'signgap');

            [htmlFile, errorMessage] = renderQuartoReport(qmdFile);
            testCase.assertNotEmpty(htmlFile, ...
                ['The ground-truth report could not be rendered: ' errorMessage]);

            stats = apaPairedStatistics(htmlFile);
            testCase.assertNotEmpty(stats, ...
                'The rendered report carried no APA paired-samples sentence to read.');

            testCase.verifyEqual(sign(stats.t), sign(stats.dz), ...
                sprintf(['The reported t = %.2f and Cohen''s dz = %.2f disagree in sign ' ...
                         'within one sentence: t.test runs in bindesc order, cohens_d in ' ...
                         'alphabetical factor-level order.'], stats.t, stats.dz));
        end

        % ================================================================ %
        %  A design with no ordinary bins
        % ================================================================ %

        function zeroOrdinaryBinsIsNotSilent(testCase)
        %ZEROORDINARYBINSISNOTSILENT  EXPECTED RED (gap ZERO). When every
        %   bin is a combination bin, classifyBins yields no ordinary
        %   labels and the orchestrator's 1/2/3+ if-chain -- which has no
        %   else -- emits no omnibus section whatsoever.
        %
        %   The assertion constrains the OUTCOME without dictating the fix:
        %   either the report says out loud that there are no ordinary
        %   condition bins to compare, or generateQuartoReport refuses the
        %   export with its own error identifier. Anything else is a
        %   complete-looking report with its main comparison quietly
        %   missing.
        %
        %   Fails today: neither happens -- the document is built, carries
        %   only the combination sections, and still ends with its summary.
            entries = ReportFixtures.erpEntries( ...
                'Bindesc', ReportFixtures.comboOnlyBindesc(), ...
                'Windows', {ReportFixtures.windowSpec('N400', 'Mean Amplitude')}, ...
                'Groups', {'', ''});

            refused = false;
            identifier = '';
            txt = '';
            try
                txt = generateQuartoReport(entries, 'x.csv');
            catch err
                refused = true;
                identifier = err.identifier;
            end

            explained = ~refused && ~isempty(regexpi(txt, 'no ordinary (condition )?bins', 'once'));
            declined = refused && strcmp(identifier, 'Alakazam:generateQuartoReport');

            testCase.verifyTrue(explained || declined, ...
                ['A design whose bins are all combination bins produced a report with no ' ...
                 'omnibus section and no explanation of its absence.']);
        end

        % ================================================================ %
        %  Chunk-label uniqueness
        % ================================================================ %

        function chunkLabelsAreUniqueWithinADocument(testCase)
        %CHUNKLABELSAREUNIQUEWITHINADOCUMENT  EXPECTED RED (gap LABEL).
        %   labelPiece lowercases and collapses every non-alphanumeric run,
        %   so two distinct window labels ('N400' and 'n400!') sanitise to
        %   one chunk label. knitr rejects duplicate labels outright, and
        %   no R parse check can see this, since parse() ignores '#|'
        %   option lines entirely.
        %
        %   Fails today: four labels, three of them distinct.
            entries = ReportFixtures.erpEntries( ...
                'Bindesc', ReportFixtures.bindesc({'A'}), ...
                'Windows', {ReportFixtures.windowSpec('N400', 'Mean Amplitude'), ...
                            ReportFixtures.windowSpec('n400!', 'Mean Amplitude')}, ...
                'Groups', {'', ''});
            txt = generateQuartoReport(entries, 'x.csv');
            labels = ReportFixtures.chunkLabels(txt);

            testCase.verifyEqual(numel(unique(labels)), numel(labels), ...
                sprintf('Duplicate chunk labels emitted: %s.', strjoin(labels, ', ')));
        end

        % ================================================================ %
        %  Markdown escaping leaking into R source
        % ================================================================ %

        function mdLitFormNeverLeaksIntoRChunks(testCase)
        %MDLITFORMNEVERLEAKSINTORCHUNKS  EXPECTED RED (gap ESCAPE), and
        %   the generalised statement of the two R-parse failures below:
        %   a label bound for an R string literal must go through rLit,
        %   never mdLit. Needs no R at all, which is its whole advantage
        %   over a parse oracle -- it names the offending label directly
        %   instead of an R line number.
        %
        %   Only labels for which mdLit's output differs BOTH from the
        %   label itself and from rLit's output can be judged this way:
        %   for a label such as 'A\B' the two escapings coincide, so an
        %   rLit-escaped occurrence is indistinguishable from a leaked
        %   mdLit one and the label is skipped rather than reported as a
        %   false positive.
        %
        %   Fails today for every judgeable label in the corpus, because
        %   pairedSection splices an mdLit-escaped bin label inside an R
        %   double-quoted string.
            offenders = {};
            candidates = ReportFixtures.hostileLabels();
            for k = 1:numel(candidates)
                label = candidates{k};
                markdownForm = ReportSections.mdLit(label);
                if strcmp(markdownForm, label) || strcmp(markdownForm, ReportSections.rLit(label))
                    continue;
                end

                entries = ReportFixtures.erpEntries( ...
                    'Bindesc', ReportFixtures.bindesc({label, 'B'}), ...
                    'Groups', {'', ''});
                chunks = ReportFixtures.rChunks(generateQuartoReport(entries, 'x.csv'));
                if any(cellfun(@(c) contains(c, markdownForm), chunks))
                    offenders{end + 1} = sprintf('"%s" (as "%s")', label, markdownForm); %#ok<AGROW>
                end
            end

            testCase.verifyEmpty(offenders, ...
                sprintf(['Markdown-escaped labels reached R source: %s. Anything inside R ' ...
                         'source must go through rLit, not mdLit.'], strjoin(offenders, '; ')));
        end

        function underscoreBinLabelStillParsesAsR(testCase)
        %UNDERSCOREBINLABELSTILLPARSESASR  EXPECTED RED (gap ESCAPE),
        %   confirmed by R's own parser. Underscores in EEG condition names
        %   are entirely routine, so this is not an exotic input.
        %
        %   Fails today: R reports that '\_' is an unrecognised escape in a
        %   character string.
            testCase.assumeTrue(~isempty(ReportFixtures.rscriptExe()), ...
                'Rscript not found; skipping the generated-R parse check.');

            entries = ReportFixtures.erpEntries( ...
                'Bindesc', ReportFixtures.bindesc({'targ_left', 'targ_right'}), ...
                'Groups', {'', ''});
            outcome = parseOutcomeOfGeneratedR(generateQuartoReport(entries, 'x.csv'));

            testCase.verifyEqual(outcome, 'PARSE-OK', ...
                'A bin label containing an underscore broke the generated R.');
        end

        function doubleQuoteBinLabelStillParsesAsR(testCase)
        %DOUBLEQUOTEBINLABELSTILLPARSESASR  EXPECTED RED (gap ESCAPE), the
        %   sharper half of the same defect: mdLit does not escape the
        %   double quote at all, so the label terminates the R string
        %   literal it was spliced into.
        %
        %   Fails today: R reports an unexpected symbol at the sprintf
        %   carrying the bin labels.
            testCase.assumeTrue(~isempty(ReportFixtures.rscriptExe()), ...
                'Rscript not found; skipping the generated-R parse check.');

            entries = ReportFixtures.erpEntries( ...
                'Bindesc', ReportFixtures.bindesc({'say "hi"', 'B'}), ...
                'Groups', {'', ''});
            outcome = parseOutcomeOfGeneratedR(generateQuartoReport(entries, 'x.csv'));

            testCase.verifyEqual(outcome, 'PARSE-OK', ...
                'A bin label containing a double quote broke the generated R.');
        end

        function percentBinLabelSurvivesSprintf(testCase)
        %PERCENTBINLABELSURVIVESSPRINTF  EXPECTED RED (gap ESCAPE), and the
        %   case that shows why a parse oracle is not enough: a bin label
        %   is spliced into a sprintf FORMAT string, so '50% load'
        %   introduces a spurious ' l' conversion. The document parses
        %   perfectly, then dies at run time, and the section builder's own
        %   per-channel tryCatch turns that into a bland italic note --
        %   a report that looks finished and analysed nothing.
        %
        %   The static leg needs no tools: no bin label may appear inside a
        %   sprintf format string at all. (The mdLit-leak invariant above
        %   cannot cover this one -- mdLit leaves '%' untouched.) The
        %   render leg, when Quarto is available, shows the consequence.
        %
        %   Fails today: the format string reads
        %   "...between A and 50% load,\n", and the render prints
        %   "Could not be analysed: too few arguments".
            binLabel = '50% load';
            entries = ReportFixtures.erpEntries( ...
                'Bindesc', ReportFixtures.bindesc({'A', binLabel}), ...
                'Groups', {'', ''});
            txt = generateQuartoReport(entries, 'x.csv');

            formats = sprintfFormatStrings(ReportFixtures.rChunks(txt));
            offending = formats(cellfun(@(f) contains(f, binLabel), formats));
            testCase.verifyEmpty(offending, ...
                sprintf(['A bin label was spliced into a sprintf format string: %s. ' ...
                         'Labels must be passed as sprintf ARGUMENTS.'], ...
                        strjoin(offending, ' | ')));

            if isempty(ReportFixtures.rscriptExe()) || isempty(ReportFixtures.quartoExe())
                return;
            end

            folder = temporaryFolder(testCase);
            renderable = ReportFixtures.erpEntries( ...
                'Bindesc', ReportFixtures.bindesc({'A', binLabel}), ...
                'Groups', repmat({''}, 1, 25));
            qmdFile = ReportFixtures.writeReport(renderable, folder, 'pctgap');

            [htmlFile, errorMessage] = renderQuartoReport(qmdFile);
            testCase.assertNotEmpty(htmlFile, ...
                ['The percent-label report could not be rendered: ' errorMessage]);

            plain = plainTextOf(htmlFile);
            testCase.verifyTrue(contains(plain, 'paired-samples'), ...
                'The percent-label report ran no paired-samples test at all.');
            testCase.verifyFalse(contains(plain, 'Could not be analysed'), ...
                'The percent-label report swallowed an R error into a bland italic note.');
        end

    end

end

% =========================================================================== %
%  Local helpers (callable only from the test methods above)
% =========================================================================== %

function folder = temporaryFolder(testCase)
%TEMPORARYFOLDER  A scratch folder for one test, torn down with it --
%   never anywhere inside the repository.
    fixture = testCase.applyFixture( ...
        matlab.unittest.fixtures.TemporaryFolderFixture);
    folder = fixture.Folder;
end

function outcome = parseOutcomeOfGeneratedR(qmdText)
%PARSEOUTCOMEOFGENERATEDR  'PARSE-OK', or 'PARSE-FAIL: <R's own message>',
%   for the R that QMDTEXT's ```{r} chunks amount to.
%
%   R's own parser is the oracle: no MATLAB assertion can stand in for it.
%   The chunks are concatenated by ReportFixtures.rCode, which separates
%   them with a BLANK line -- without it, one chunk's closing brace splices
%   onto the next chunk's first token and R reports a syntax error the
%   concatenation itself manufactured.
    scriptFile = [tempname() '.R'];
    removeScript = onCleanup(@() deleteFileIfPresent(scriptFile)); %#ok<NASGU>
    writeUtf8File(scriptFile, ReportFixtures.rCode(qmdText));

    driver = sprintf([ ...
        'res <- tryCatch({ parse("%s"); "PARSE-OK" },\n' ...
        '                error = function(e) paste0("PARSE-FAIL: ", conditionMessage(e)))\n' ...
        'cat(res)\n'], strrep(scriptFile, '\', '/'));
    [status, output] = ReportFixtures.runRscript(driver);

    if status ~= 0
        outcome = sprintf('PARSE-FAIL: Rscript exited with status %d: %s', ...
            status, strtrim(output));
        return;
    end
    outcome = strtrim(output);
end

function formats = sprintfFormatStrings(chunks)
%SPRINTFFORMATSTRINGS  Every sprintf("...") FORMAT literal across CHUNKS
%   (a cellstr of R chunk bodies), as a cellstr of the literals' inner
%   text -- so a test can ask whether an analyst's label ended up inside a
%   format string rather than being passed as an argument to it.
    formats = {};
    for c = 1:numel(chunks)
        tokens = regexp(chunks{c}, 'sprintf\("((?:\\.|[^"])*)"', 'tokens');
        for t = 1:numel(tokens)
            formats{end + 1} = tokens{t}{1}; %#ok<AGROW>
        end
    end
end

function stats = apaPairedStatistics(htmlFile)
%APAPAIREDSTATISTICS  The .df/.t/.dz/.ciLow/.ciHigh of the first APA
%   paired-samples sentence in HTMLFILE, or [] when there is none.
%
%   One regular expression captures all five in a single pass over the
%   tag-stripped text. It is deliberately loose about the apostrophe in
%   "Cohen's", which the rendered HTML writes as a typographic apostrophe
%   that may arrive as more than one char depending on the encoding.
    plain = plainTextOf(htmlFile);
    pattern = ['t\s*\(\s*(\d+)\s*\)\s*=\s*(-?[\d.]+)\s*,\s*' ...
               'p\s*[<=]\s*[\d.]+\s*,\s*Cohen.{1,3}s\s*d\s*z\s*=\s*(-?[\d.]+)\s*' ...
               '\([^)]*\)\s*,\s*95%\s*CI\s*\[\s*(-?[\d.]+)\s*,\s*(-?[\d.]+)\s*\]'];
    tokens = regexp(plain, pattern, 'tokens', 'once');

    if isempty(tokens)
        stats = [];
        return;
    end
    stats = struct('df', str2double(tokens{1}), 't', str2double(tokens{2}), ...
        'dz', str2double(tokens{3}), 'ciLow', str2double(tokens{4}), ...
        'ciHigh', str2double(tokens{5}));
end

function plain = plainTextOf(htmlFile)
%PLAINTEXTOF  HTMLFILE with its tags removed, its handful of relevant
%   entities unescaped and its whitespace collapsed -- the form an
%   assertion about the rendered prose can be written against.
    raw = fileread(htmlFile);
    plain = regexprep(raw, '<[^>]*>', ' ');
    plain = strrep(plain, '&lt;', '<');
    plain = strrep(plain, '&gt;', '>');
    plain = strrep(plain, '&amp;', '&');
    plain = regexprep(plain, '\s+', ' ');
end

function writeUtf8File(path, text)
%WRITEUTF8FILE  TEXT to PATH as UTF-8, with no byte-order mark, so R's own
%   parser reads exactly the bytes the generator produced.
    fid = fopen(path, 'w', 'n', 'UTF-8');
    if fid < 0
        throw(MException('Alakazam:QuartoReportKnownGapTest:cannotWrite', ...
            'I am afraid "%s" could not be opened for writing.', path));
    end
    closeFile = onCleanup(@() fclose(fid)); %#ok<NASGU>
    fwrite(fid, unicode2native(char(text), 'UTF-8'));
end

function deleteFileIfPresent(path)
%DELETEFILEIFPRESENT  Remove PATH when it exists, quietly otherwise.
    if exist(path, 'file') == 2
        delete(path);
    end
end
