classdef QuartoReportTextContractTest < matlab.unittest.TestCase
%QUARTOREPORTTEXTCONTRACTTEST  Everything a chunk label cannot see, for
%   src/IO/generateQuartoReport.m and the src/IO/+ReportSections package.
%
%   TESTING PHILOSOPHY.  Its sibling QuartoReportDispatchTest pins WHICH
%   section builder each design routes to, by censusing chunk labels. That
%   census is deliberately blind to what a section builder actually WROTE:
%   a one-token edit inside a template -- a swapped subtraction order, a
%   dropped escape, a renamed design literal, a mis-indexed combination-bin
%   recipe -- changes the statistic the rendered report claims while
%   leaving every heading, every prose line and every chunk label
%   byte-identical. Nothing upstream of an actual R render can notice that,
%   and a render is far too slow (and far too tool-dependent) to be the
%   only thing standing between an analyst and a wrong number.
%
%   So this file asserts the LITERALS, in four groups:
%
%     - The two escaping boundaries. Every label reaches the document
%       twice, in two different languages: mdLit-escaped for Quarto
%       markdown prose, rLit-escaped for the inside of an R double-quoted
%       string (see fillToken's own header comment). They escape different
%       character sets, on purpose, and getting one of them wrong is
%       invisible until a label happens to contain the offending
%       character. rLit in particular had no end-to-end coverage at all
%       before this file.
%
%     - The combination-bin recipe algebra (comboRecipeText). A combo
%       bin's .combo(t).bin values are the referenced bins' .index, an
%       Average.m convention, NOT their array positions -- indistinguish-
%       able in every fixture whose .index happens to run 1:n, which until
%       now was every fixture there was.
%
%     - Chunk-label well-formedness. labelPiece must turn anything an
%       analyst could plausibly type into something knitr accepts, over a
%       FIXED hostile corpus (ReportFixtures.hostileLabels), never a
%       randomised one: a reproducible failure naming the exact offending
%       label beats broader coverage nobody can reproduce. (Label
%       UNIQUENESS is the other half of that contract, and currently
%       fails -- it lives in QuartoReportKnownGapTest, not here.)
%
%     - The statistical-template literals that encode the actual science:
%       the paired test's subtraction direction stated three times over,
%       the LMM formulae and their singular-fit fallback, the design
%       vocabulary shared between the section builders and the closing
%       summary's own facet mapping, and the multiple-comparison method
%       stated once in code and once in prose.
%
%   Pure MATLAB string work throughout: no R, no Quarto, nothing written
%   to disk, so the whole file runs in about a second and can guard an
%   edit in a fast inner loop.
%
%   Run with: runtests('tests/QuartoReportTextContractTest.m').

    properties (Constant, Access = private)
        % The report's own bare CSV name, used wherever the name itself is
        % not what is under test.
        CsvName = 'x.csv'
    end

    properties (TestParameter)
        % ---- comboRecipeText's sign/magnitude branches ----------------- %
        % Each case combines bins A/B/C (indices 1/2/3) with the given
        % COEFFS over the given REFS, and expects EXPECTED verbatim in the
        % combination section's own "(recipe)" parenthetical. The
        % backslash before every '*' is mdLit's own escaping and is part
        % of the expected text, not a MATLAB escape. FORBIDDEN, when
        % non-empty, is text the emitted recipe must NOT contain.
        comboRecipe = struct( ...
            'unitPlus',       struct('coeffs', [1, 1],            'refs', [1, 2], ...
                                     'expected', '(A + B)',                'forbidden', ''), ...
            'unitMinus',      struct('coeffs', [1, -1],           'refs', [1, 2], ...
                                     'expected', '(A - B)',                'forbidden', '1\*B'), ...
            'leadingMinus',   struct('coeffs', [-1, 1],           'refs', [1, 2], ...
                                     'expected', '(-A + B)',               'forbidden', ''), ...
            'halfHalf',       struct('coeffs', [0.5, 0.5],        'refs', [1, 2], ...
                                     'expected', '(0.5\*A + 0.5\*B)',      'forbidden', ''), ...
            'thirds',         struct('coeffs', [1/3, -2/3],       'refs', [1, 2], ...
                                     'expected', '(0.333\*A - 0.667\*B)',  'forbidden', ''), ...
            'largeMagnitude', struct('coeffs', [1234.5678, 1],    'refs', [1, 2], ...
                                     'expected', '(1.23e+03\*A + B)',      'forbidden', ''), ...
            'smallMagnitude', struct('coeffs', [0.000123456, 1],  'refs', [1, 2], ...
                                     'expected', '(0.000123\*A + B)',      'forbidden', ''), ...
            'zeroCoefficient', struct('coeffs', [0, 1],           'refs', [1, 2], ...
                                     'expected', '(0\*A + B)',             'forbidden', ''), ...
            'singleTerm',     struct('coeffs', 2,                 'refs', 3, ...
                                     'expected', '(2\*C)',                 'forbidden', ''))

        % ---- The fixed hostile-label corpus ---------------------------- %
        % Named rather than generated from the corpus itself, so a failure
        % is reported as e.g. "hostileLabel=backtick" instead of a mangled
        % value name -- and tied back to ReportFixtures.hostileLabels
        % inside the test, so the two cannot drift apart.
        hostileLabel = struct( ...
            'underscore',     'targ_left', ...
            'asterisk',       'targ*right', ...
            'doubleQuote',    'say "hi"', ...
            'percent',        '50% load', ...
            'backslash',      'A\B', ...
            'angleBrackets',  '<tag>', ...
            'hash',           '#hash', ...
            'squareBrackets', '[br]', ...
            'backtick',       'back`tick', ...
            'emptyLabel',     '', ...
            'blankLabel',     ' ', ...
            'embeddedSpace',  '20 Hz', ...
            'nonAscii',       char([99, 97, 102, 233]), ...
            'wellBehaved',    'a-b')
    end

    methods (TestClassSetup)
        function addSourceToPath(testCase)
        %ADDSOURCETOPATH  src/IO (generateQuartoReport + the
        %   +ReportSections package), src/Support, and the tests folder
        %   itself so ReportFixtures resolves.
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
        %  Combination-bin recipe algebra (comboRecipeText)
        % ================================================================ %

        function comboRecipeMapsIndexNotArrayPosition(testCase)
        %COMBORECIPEMAPSINDEXNOTARRAYPOSITION  A combination bin's
        %   .combo(t).bin values are the referenced bins' .index values
        %   (Average.m's own convention), not their positions in the
        %   bindesc array. No existing fixture can tell the two apart,
        %   because every one of them has .index running 1:n -- so this
        %   uses a bindesc whose .index deliberately does not.
        %
        %   The negative assertion is the load-bearing half: "(Third -
        %   Second)" is precisely what a position-indexing implementation
        %   emits for this design, so its absence is what actually
        %   discriminates.
            bins = ReportFixtures.bindescIndexed([3, 1, 2], {'Third', 'First', 'Second'});
            bins = ReportFixtures.withCombo(bins, 'D', [1, -1], [1, 3]);
            txt = generateQuartoReport(ReportFixtures.erpEntries('Bindesc', bins), ...
                QuartoReportTextContractTest.CsvName);

            testCase.verifySubstring(txt, '(First - Third)', ...
                'The combination recipe did not resolve its .bin values through bindesc''s own .index.');
            testCase.verifyFalse(contains(txt, '(Third - Second)'), ...
                'The combination recipe indexed bindesc by ARRAY POSITION instead of by .index.');

            % Second leg: .index values that are not even contiguous, so a
            % position lookup would error or wrap rather than silently
            % naming the wrong bin.
            wide = ReportFixtures.bindescIndexed([10, 20, 30, 40], ...
                {'Ten', 'Twenty', 'Thirty', 'Forty'});
            wide = ReportFixtures.withCombo(wide, 'E', [1, -1], [30, 10]);
            wideTxt = generateQuartoReport(ReportFixtures.erpEntries('Bindesc', wide), ...
                QuartoReportTextContractTest.CsvName);

            testCase.verifySubstring(wideTxt, '(Thirty - Ten)', ...
                'A non-contiguous .index set was not resolved to the right bin labels.');
        end

        function comboRecipeCoefficientFormatting(testCase, comboRecipe)
        %COMBORECIPECOEFFICIENTFORMATTING  Every sign/magnitude branch of
        %   comboRecipeText, each pinned to the exact parenthetical the
        %   combination section prints: a leading term carries no " + ",
        %   a unit coefficient is elided entirely rather than printed as
        %   "1*", a leading negative gets a bare "-" with no space, and a
        %   non-unit coefficient is formatted %.3g (which switches to
        %   exponent notation at both ends of the range).
            bins = ReportFixtures.withCombo(ReportFixtures.bindesc({'A', 'B', 'C'}), ...
                'D', comboRecipe.coeffs, comboRecipe.refs);
            txt = generateQuartoReport(ReportFixtures.erpEntries('Bindesc', bins), ...
                QuartoReportTextContractTest.CsvName);

            testCase.verifySubstring(txt, comboRecipe.expected, ...
                sprintf('The combination recipe for coefficients [%s] did not read "%s".', ...
                    strjoin(compose('%g', comboRecipe.coeffs), ', '), comboRecipe.expected));
            if ~isempty(comboRecipe.forbidden)
                testCase.verifyFalse(contains(txt, comboRecipe.forbidden), ...
                    sprintf('The combination recipe printed "%s", which comboRecipeText elides.', ...
                        comboRecipe.forbidden));
            end
        end

        % ================================================================ %
        %  The two escaping boundaries (rLit / mdLit)
        % ================================================================ %

        function rLitEscapesInsideRStringLiterals(testCase)
        %RLITESCAPESINSIDERSTRINGLITERALS  A bin label reaching the inside
        %   of an R double-quoted string must be rLit-escaped: a backslash
        %   doubled, a double quote backslash-escaped, and NOTHING else
        %   touched (an asterisk and an underscore are perfectly ordinary
        %   characters inside an R string, and escaping them there is what
        %   the KnownGap file's mdLit-leak case is about).
        %
        %   The only assertion in the whole suite that looks inside an R
        %   string literal. Written as a MATLAB single-quoted literal, so
        %   every backslash below is a literal backslash.
            txt = generateQuartoReport(ReportFixtures.erpEntries( ...
                'Bindesc', ReportFixtures.bindesc({'A*B_c', 'D"E\F'})), ...
                QuartoReportTextContractTest.CsvName);

            testCase.verifySubstring(txt, 'bin %in% c("A*B_c", "D\"E\\F")', ...
                'A bin label was not rLit-escaped for the inside of an R string literal.');
        end

        function mdLitEscapesInMarkdownProse(testCase)
        %MDLITESCAPESINMARKDOWNPROSE  The same two labels on the PROSE
        %   side, where a different character set is special: '*' and '_'
        %   (which would otherwise open markdown emphasis) are escaped,
        %   and so is the backslash.
        %
        %   Deliberately a characterisation, not an endorsement: mdLit
        %   does NOT escape the double quote, so the label 'D"E\F' reaches
        %   the prose with its quote bare. That asymmetry is real today
        %   and is asserted here as the baseline a fix would move -- the
        %   damage it does inside an R string is QuartoReportKnownGapTest's
        %   business, not this file's.
            txt = generateQuartoReport(ReportFixtures.erpEntries( ...
                'Bindesc', ReportFixtures.bindesc({'A*B_c', 'D"E\F'})), ...
                QuartoReportTextContractTest.CsvName);

            testCase.verifySubstring(txt, 'Two conditions: "A\*B\_c" vs. "D"E\\F".', ...
                'A bin label was not mdLit-escaped for markdown prose.');

            % Second leg: the heading side, where '<' and '>' would
            % otherwise be swallowed as a raw HTML tag.
            headingTxt = generateQuartoReport(ReportFixtures.erpEntries( ...
                'Windows', {ReportFixtures.windowSpec('<W 1>', 'Mean Amplitude')}), ...
                QuartoReportTextContractTest.CsvName);

            testCase.verifySubstring(headingTxt, '## \<W 1\> -- mean\_amplitude', ...
                'A window label was not mdLit-escaped for its own section heading.');
        end

        function csvFileNameIsREscaped(testCase)
        %CSVFILENAMEISRESCAPED  The CSV file name is the one piece of
        %   caller-supplied text in the preamble rather than in a section
        %   builder, and it lands inside an R string literal, so it needs
        %   rLit exactly as a bin label does. A Windows path fragment is
        %   full of backslashes, which makes this the likeliest of all of
        %   them to actually carry one.
            txt = generateQuartoReport(ReportFixtures.erpEntries(), 'a"b\c.csv');

            testCase.verifySubstring(txt, 'csv_file <- "a\"b\\c.csv"', ...
                'The CSV file name was not rLit-escaped into the setup chunk''s R string literal.');
        end

        % ================================================================ %
        %  Chunk-label well-formedness (labelPiece / chunkLabel)
        % ================================================================ %

        function chunkLabelsAreValidKnitrLabels(testCase, hostileLabel)
        %CHUNKLABELSAREVALIDKNITRLABELS  Whatever an analyst types as a
        %   window or combination-bin label, every chunk label the
        %   document ends up with is lowercase alphanumerics separated by
        %   single hyphens, with no leading or trailing hyphen -- which is
        %   what knitr will accept without complaint.
        %
        %   Each label is used BOTH as the window label and as the
        %   combination bin's label, so labelPiece is exercised in both
        %   of the two positions chunkLabel actually feeds it from.
        %   (Whether the resulting labels are UNIQUE is the separate,
        %   currently-failing half of this contract -- see
        %   QuartoReportKnownGapTest/chunkLabelsAreUniqueWithinADocument.)
            testCase.verifyTrue(ismember({hostileLabel}, ReportFixtures.hostileLabels()), ...
                'This corpus has drifted from ReportFixtures.hostileLabels().');

            bins = ReportFixtures.withCombo(ReportFixtures.bindesc({'A', 'B'}), ...
                hostileLabel, [1, -1], [1, 2]);
            txt = generateQuartoReport(ReportFixtures.erpEntries('Bindesc', bins, ...
                'Windows', {ReportFixtures.windowSpec(hostileLabel, 'Mean Amplitude')}), ...
                QuartoReportTextContractTest.CsvName);

            labels = ReportFixtures.chunkLabels(txt);
            testCase.verifyNotEmpty(labels, 'The document carried no chunk labels at all.');
            for i = 1:numel(labels)
                testCase.verifyMatches(labels{i}, '^[a-z0-9]+(-[a-z0-9]+)*$', ...
                    sprintf('Chunk label "%s" is not a valid knitr label.', labels{i}));
            end
        end

        function blankLabelsFallBackToX(testCase)
        %BLANKLABELSFALLBACKTOX  labelPiece's "x" fallback, stated as an
        %   invariant rather than left implicit: a blank window label
        %   still yields a well-formed chunk label (with "x" standing in
        %   for the empty piece, so two different sections cannot collapse
        %   onto the same "--" run), while the HEADING keeps the blank as
        %   the analyst typed it -- the sanitisation is for knitr, not for
        %   the reader. A blank BIN label likewise survives into the R
        %   filter as an ordinary empty string.
            windowTxt = generateQuartoReport(ReportFixtures.erpEntries( ...
                'Windows', {ReportFixtures.windowSpec('', 'Mean Amplitude')}), ...
                QuartoReportTextContractTest.CsvName);

            testCase.verifySubstring(windowTxt, '#| label: desc-x-mean-amplitude', ...
                'A blank window label did not fall back to labelPiece''s own "x".');
            testCase.verifySubstring(windowTxt, '##  -- mean\_amplitude', ...
                'The heading did not keep the blank window label verbatim.');

            binTxt = generateQuartoReport(ReportFixtures.erpEntries( ...
                'Bindesc', ReportFixtures.bindesc({'', 'B'})), ...
                QuartoReportTextContractTest.CsvName);

            testCase.verifySubstring(binTxt, 'bin %in% c("", "B")', ...
                'A blank bin label did not survive into the R filter as an empty string.');
        end

        % ================================================================ %
        %  The statistical-template literals
        % ================================================================ %

        function pairedDirectionLiteralsAgree(testCase)
        %PAIREDDIRECTIONLITERALSAGREE  pairedSection states its
        %   subtraction direction THREE separate times -- once for the
        %   difference scores it describes and plots, once for the t-test,
        %   once for the Wilcoxon robustness check -- and all three must
        %   say bin2 minus bin1. Asserting them together is the point: a
        %   swap of any single one leaves the report internally
        %   contradictory (a plotted difference pointing one way, a
        %   reported t pointing the other) while every heading, prose line
        %   and chunk label stays byte-identical.
        %
        %   (That the Cohen's dz computed on the next line disagrees with
        %   all three -- rstatix orders the factor levels alphabetically,
        %   not in bindesc order -- is a live defect, and belongs to
        %   QuartoReportKnownGapTest/pairedEffectSizeSignMatchesTestStatistic.)
            txt = generateQuartoReport(ReportFixtures.censusEntries('F-ERP2'), ...
                QuartoReportTextContractTest.CsvName);

            testCase.verifySubstring(txt, 'diffs <- wide[["B"]] - wide[["A"]]', ...
                'The difference scores are not bin2 - bin1.');
            testCase.verifySubstring(txt, 't.test(wide[["B"]], wide[["A"]], paired = TRUE)', ...
                'The paired t-test does not test bin2 against bin1.');
            testCase.verifySubstring(txt, 'wilcox.test(wide[["B"]], wide[["A"]], paired = TRUE)', ...
                'The Wilcoxon check does not test bin2 against bin1.');
        end

        function lmmFormulaeAndFallbackPresent(testCase)
        %LMMFORMULAEANDFALLBACKPRESENT  The 3+-bin within-subjects design
        %   is an LMM, not a repeated-measures ANOVA, specifically so a
        %   subject missing one bin still contributes their other bins
        %   (see anovaSection's own header comment). That choice lives
        %   entirely in these literals: the MAXIMAL model (random
        %   intercept AND random slope for bin), the DISTINCT
        %   intercept-only fallback it drops to on a singular fit, the
        %   singularity test that decides between them, the model-based
        %   Holm-corrected contrasts, and the Friedman robustness check.
        %   Silently losing the random slope, or losing the fallback and
        %   keeping a singular fit, changes every degree of freedom the
        %   report prints without changing one word of its prose.
            anovaTxt = generateQuartoReport(ReportFixtures.censusEntries('F-ERP3C'), ...
                QuartoReportTextContractTest.CsvName);

            testCase.verifySubstring(anovaTxt, ...
                'lmerTest::lmer(value ~ bin + (1 + bin | dataset), data = d,', ...
                'The maximal (random intercept AND slope) LMM formula is missing.');
            testCase.verifySubstring(anovaTxt, ...
                'lmerTest::lmer(value ~ bin + (1 | dataset), data = d,', ...
                'The intercept-only singular-fit fallback model is missing.');
            testCase.verifySubstring(anovaTxt, ...
                'used_maximal <- !is.null(m) && !lme4::isSingular(m)', ...
                'The singular-fit test that chooses between the two models is missing.');
            testCase.verifySubstring(anovaTxt, ...
                'emmeans::emmeans(m, pairwise ~ bin, adjust = "holm")', ...
                'The Holm-corrected model-based pairwise contrasts are missing.');
            testCase.verifySubstring(anovaTxt, ...
                'friedman_test(data = d_complete, value ~ bin | dataset)', ...
                'The Friedman robustness check is missing.');

            % The two subject guards, which decide whose data reaches any
            % of the above: one document-wide (in the setup chunk), one
            % per channel in the paired design (complete cases only).
            testCase.verifySubstring(anovaTxt, 'if (n_distinct(dat$dataset) < 2) {', ...
                'The document-wide two-subject guard is missing from the setup chunk.');

            pairedTxt = generateQuartoReport(ReportFixtures.censusEntries('F-ERP2'), ...
                QuartoReportTextContractTest.CsvName);
            testCase.verifySubstring(pairedTxt, 'keep <- counts %>% filter(n == 2) %>% pull(dataset)', ...
                'The paired design''s complete-cases-only subject guard is missing.');
        end

        function designVocabularyMatchesSummaryFacets(testCase)
        %DESIGNVOCABULARYMATCHESSUMMARYFACETS  Cross-file coherence. Every
        %   section builder logs one row into `omnibus` carrying a design
        %   literal, and closingText's own case_when reads those literals
        %   back to decide which effect-size facet each test belongs to.
        %   Rename a design in one +ReportSections file and the summary
        %   still renders -- the test just quietly falls through to the
        %   generic "effect size" facet, which is wrong but not loud.
        %
        %   So the vocabulary is pinned in both directions: no section may
        %   invent a design outside the agreed set, and every design in
        %   that set must still be emitted by some section (a design that
        %   has vanished entirely is the other way this drifts). The
        %   census fixtures reach all seven between them, because
        %   betweenSection and betweenGroupsLines each emit BOTH of their
        %   own two designs as static text, whichever branch runs at R
        %   runtime.
            allowed = {'between_group_combo', 'indep_t', 'lmm_mixed', 'lmm_within', ...
                'one_sample_vs_0', 'paired_t', 'welch_anova'};

            ids = ReportFixtures.censusIds();
            seen = {};
            for i = 1:numel(ids)
                txt = generateQuartoReport(ReportFixtures.censusEntries(ids{i}), ...
                    QuartoReportTextContractTest.CsvName);
                found = regexp(txt, 'design = "([a-z0-9_]+)"', 'tokens');
                for f = 1:numel(found)
                    seen{end + 1} = found{f}{1}; %#ok<AGROW>
                end
            end
            seen = unique(seen);

            testCase.verifyEmpty(setdiff(seen, allowed), ...
                'A section builder logged a design literal outside the agreed vocabulary.');
            testCase.verifyEmpty(setdiff(allowed, seen), ...
                'A design literal in the agreed vocabulary is no longer emitted by any section.');

            % The other side of the same contract: the summary's own facet
            % mapping, which names two of those literals verbatim.
            testCase.verifySubstring(txt, ...
                'design %in% c("lmm_within", "lmm_mixed") ~ "Partial eta-sq. (LMM)"', ...
                'The closing summary''s LMM effect-size facet mapping is missing or renamed.');
        end

        function closingTextProseMatchesItsMethod(testCase)
        %CLOSINGTEXTPROSEMATCHESITSMETHOD  The cross-report summary
        %   corrects across every test the export produced, and then names
        %   the correction it used in a sentence the reader will quote.
        %   The code and the sentence are two independent literals a few
        %   lines apart, so they are asserted together: switching the
        %   method to "holm" or "bonferroni" without rewriting the
        %   sentence leaves a report that states, in prose, a correction
        %   it did not actually apply.
            txt = generateQuartoReport(ReportFixtures.erpEntries(), ...
                QuartoReportTextContractTest.CsvName);

            testCase.verifySubstring(txt, 'mutate(p_bh = p.adjust(p, method = "BH"))', ...
                'The summary no longer applies a Benjamini-Hochberg correction.');
            testCase.verifySubstring(txt, ...
                'significant after Benjamini-Hochberg (BH/FDR) correction across all of them.', ...
                'The summary prose no longer names the Benjamini-Hochberg correction it applies.');
        end

    end
end
