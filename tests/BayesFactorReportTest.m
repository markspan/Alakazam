classdef BayesFactorReportTest < matlab.unittest.TestCase
%BAYESFACTORREPORTTEST  Bayes factors beside every t-test in the ERP and
%   spectral reports.
%
%   WHY THIS EXISTS. The reading guide at the top of both reports said, for
%   a long time, that Bayes factors "appear beside the t-tests". None did.
%   No section computed one, and the BayesFactor package had dropped out of
%   the setup chunk, so the promise could not have been kept even by
%   accident. It was noticed in the spectral report, but the two share one
%   generator and both were affected.
%
%   The first cases here are text-level and fast: that the helpers are
%   emitted, the package is loaded, and every t-test section uses them. The
%   last runs the emitted helpers in R, because the evidence scale and the
%   number formatting are what a reader acts on, and a typo in a cut-off
%   would parse perfectly well.
%
%   Run with: runtests('tests/BayesFactorReportTest.m').

    properties (Constant)
        % Every section that runs a t-test, and the form of the Bayes
        % factor it should compute.
        TTestSections = { ...
            'pairedSection',      'paired = TRUE'; ...
            'vsZeroLines',        'mu = 0'; ...
            'comboSection',       'mu = 0'; ...
            'betweenSection',     'formula = value ~ group'; ...
            'betweenGroupsLines', 'formula = value ~ group'}
    end

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            here = fileparts(mfilename('fullpath'));
            root = fileparts(here);
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'Reports')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'Support')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(here));
        end
    end

    methods (Test)
        function theReportLoadsBayesFactor(testCase)
            qmd = generateQuartoReport(ReportFixtures.erpEntries(), 'x.csv');
            block = regexp(qmd, 'pkgs <- c\((.*?)\)', 'tokens', 'once');

            testCase.assertNotEmpty(block, 'The setup chunk has no package list.');
            testCase.verifySubstring(block{1}, '"BayesFactor"', ...
                'The report computes Bayes factors, so the setup chunk must load BayesFactor.');
        end

        function theHelpersAreDefined(testCase)
            qmd = generateQuartoReport(ReportFixtures.erpEntries(), 'x.csv');

            for fn = {'bf10_ttest <- function', 'bf10_effect <- function', 'fmt_bf <- function', 'bf_word <- function'}
                testCase.verifySubstring(qmd, fn{1});
            end
        end

        function everyTTestSectionReportsABayesFactor(testCase)
        %EVERYTTESTSECTIONREPORTSABAYESFACTOR  The guide says "beside the
        %   t-tests", which means all of them, not only the paired one.
            root = fileparts(fileparts(mfilename('fullpath')));
            folder = fullfile(root, 'src', 'Reports', '+ReportSections');

            for k = 1:size(BayesFactorReportTest.TTestSections, 1)
                name = BayesFactorReportTest.TTestSections{k, 1};
                source = fileread(fullfile(folder, [name '.m']));

                testCase.verifySubstring(source, 'bf10_ttest(', ...
                    sprintf('%s runs a t-test but computes no Bayes factor.', name));
                testCase.verifySubstring(source, BayesFactorReportTest.TTestSections{k, 2}, ...
                    sprintf('%s computes its Bayes factor in the wrong form.', name));
                testCase.verifySubstring(source, 'BF10 = fmt_bf(bf), Evidence = bf_word(bf)', ...
                    sprintf('%s does not put the Bayes factor in its results table.', name));
            end
        end

        function theGuideSaysWhereThereIsNone(testCase)
        %THEGUIDESAYSWHERETHEREISNONE  A rank-based test replaces the t-test
        %   when the data depart from normality, and it carries no Bayes
        %   factor. A blank cell with no explanation reads as a bug, so the
        %   guide says so, and names the prior the numbers depend on.
            qmd = generateQuartoReport(ReportFixtures.censusEntries('F-ERP2'), 'x.csv');

            testCase.verifySubstring(qmd, 'rank-based test was reported instead, no Bayes factor');
            testCase.verifySubstring(qmd, 'JZS prior');
            testCase.verifySubstring(qmd, 'Welch');
        end

        function theMixedModelCarriesABayesFactor(testCase)
        %THEMIXEDMODELCARRIESABAYESFACTOR  A spectral report of four
        %   conditions is mixed models throughout, with no t-test anywhere,
        %   so it had no Bayes factor at all while its guide promised them.
        %   Each mixed-model section now has one for the effect it tests,
        %   taken from the fixed terms of the model it actually fitted.
            root = fileparts(fileparts(mfilename('fullpath')));
            source = fileread(fullfile(root, 'src', 'Reports', '+ReportSections', 'lmmSection.m'));
            within = generateQuartoReport(ReportFixtures.censusEntries('F-SPEC3C'), 'x.csv');
            mixed = generateQuartoReport(ReportFixtures.censusEntries('F-ERP3CG'), 'x.csv');

            testCase.verifySubstring(source, 'lme4::nobars(formula(m))', ...
                'The Bayes factor must follow the model that was fitted, fallback included.');
            testCase.verifySubstring(within, 'bf10_effect(d, fixed_terms, "bin")');
            testCase.verifySubstring(within, 'Bayes Factor for the Condition Effect, by Channel');
            testCase.verifySubstring(mixed, 'bf10_effect(d, fixed_terms, "bin:group")', ...
                'In a mixed design the section tests the interaction, and so does its Bayes factor.');
        end

        function theGuideNamesOnlyTheBayesFactorsTheReportHas(testCase)
        %THEGUIDENAMESONLYTHEBAYESFACTORSTHEREPORTHAS  Three conditions and
        %   nothing else is mixed models only, the RIFT report's shape; the
        %   census fixtures with three conditions all carry a difference bin,
        %   whose test against zero is a t-test.
            modelsOnly = generateQuartoReport(ReportFixtures.erpEntries( ...
                'Bindesc', ReportFixtures.bindesc({'A', 'B', 'C'})), 'x.csv');
            tTestsOnly = generateQuartoReport(ReportFixtures.censusEntries('F-ERP2'), 'x.csv');
            both = generateQuartoReport(ReportFixtures.censusEntries('F-ERP3C'), 'x.csv');
            neither = generateQuartoReport(ReportFixtures.censusEntries('F-ERP1'), 'x.csv');

            testCase.verifySubstring(modelsOnly, '**Bayes factors** appear in each mixed-model section,');
            testCase.verifyFalse(contains(modelsOnly, 'beside the *t*-tests'), ...
                'A report of mixed models only has no t-test to put a Bayes factor beside.');
            testCase.verifySubstring(modelsOnly, 'Rouder et al. (2012)');
            testCase.verifySubstring(tTestsOnly, '**Bayes factors** appear beside the *t*-tests,');
            testCase.verifyFalse(contains(tTestsOnly, 'Rouder et al. (2012)'), ...
                'The guide describes the mixed-model Bayes factor only where there is one.');
            testCase.verifySubstring(both, 'beside the *t*-tests and in each mixed-model section');
            testCase.verifyFalse(contains(neither, '**Bayes factors**'), ...
                'A report with no test carries no Bayes factor, and says nothing about them.');
        end
    end

    methods (Test, TestTags = {'External'})
        function theEvidenceScaleAndFormattingAreRight(testCase)
        %THEEVIDENCESCALEANDFORMATTINGARERIGHT  Runs the helpers exactly as
        %   the report emits them. The scale is Jeffreys (1961) in the wording
        %   of Lee and Wagenmakers (2013), the same cut-offs used in both
        %   directions as reciprocals.
            rscript = ReportFixtures.rscriptExe();
            testCase.assumeNotEmpty(rscript, 'R is not installed.');
            testCase.assumeTrue(ReportFixtures.rPackagesPresent({'BayesFactor'}), ...
                'BayesFactor is not installed.');

            qmd = generateQuartoReport(ReportFixtures.erpEntries(), 'x.csv');
            first = strfind(qmd, 'bf10_ttest <- function');
            stop = strfind(qmd(first:end), '```');
            helpers = qmd(first:first + stop(1) - 2);

            probe = [helpers newline ...
                'cat("FMT:", fmt_bf(c(NA, 2000, 0.0001, 3.158488, 0.04567)), sep = "|"); cat("\n")' newline ...
                'cat("WORD:", bf_word(c(NA, 1, 150, 50, 15, 5, 2, 0.5, 0.2, 0.05, 0.02, 0.005)), sep = "|"); cat("\n")' newline ...
                'cat("TNA:", is.na(bf10_ttest(x = 1, mu = 0)), "\n")' newline ...
                ... % A within design with a known answer: 20 people, three conditions
                ... % whose means differ by 1 against noise of 0.3 (strong), and the same
                ... % people with no condition effect at all (null).
                'set.seed(7); pid <- factor(rep(1:20, each = 3)); bin <- factor(rep(c("A", "B", "C"), 20))' newline ...
                'person <- rep(rnorm(20), each = 3)' newline ...
                'strong <- data.frame(person_id = pid, bin = bin, value = person + as.numeric(bin) + rnorm(60, sd = 0.3))' newline ...
                'null <- data.frame(person_id = pid, bin = bin, value = person + rnorm(60, sd = 0.3))' newline ...
                'cat("STRONG:", bf10_effect(strong, "bin", "bin") > 1000, "\n")' newline ...
                'cat("NULL:", bf10_effect(null, "bin", "bin") < 1, "\n")' newline ...
                'cat("MISSING:", is.na(bf10_effect(strong, "bin", "bin:group")), "\n")' newline];

            folder = testCase.applyFixture( ...
                matlab.unittest.fixtures.TemporaryFolderFixture()).Folder;
            script = fullfile(folder, 'probe.R');
            fid = fopen(script, 'w');
            fprintf(fid, '%s', probe);
            fclose(fid);

            [status, out] = system(sprintf('"%s" "%s"', rscript, script));
            testCase.assertEqual(status, 0, sprintf('The helpers did not run:\n%s', out));
            lines = strtrim(splitlines(strtrim(out)));
            value = @(tag) strtrim(extractAfter(lines{find(startsWith(lines, [tag ':']), 1)}, [tag ':']));

            testCase.verifyEqual(value('FMT'), '|NA|> 1000|< 0.001|3.16|0.0457', ...
                'fmt_bf formats Bayes factors wrongly.');
            testCase.verifyEqual(value('WORD'), ['|' strjoin({'NA', ...
                'no evidence either way', ...
                'extreme for a difference', 'very strong for a difference', ...
                'strong for a difference', 'moderate for a difference', ...
                'anecdotal for a difference', ...
                'anecdotal for no difference', 'moderate for no difference', ...
                'strong for no difference', 'very strong for no difference', ...
                'extreme for no difference'}, '|')], ...
                'bf_word reads a Bayes factor against the wrong cut-offs.');
            testCase.verifyEqual(value('STRONG'), 'TRUE', ...
                'Condition means 1 apart against noise of 0.3 must give overwhelming evidence.');
            testCase.verifyEqual(value('NULL'), 'TRUE', ...
                'With no condition effect the Bayes factor must favour its absence.');
            testCase.verifyEqual(value('MISSING'), 'TRUE', ...
                'An effect the fitted model does not have gets no Bayes factor.');
            testCase.verifyEqual(value('TNA'), 'TRUE', ...
                ['A t-test that cannot be computed should give NA, not an error, so one ' ...
                 'channel failing does not take the rest of its table with it.']);
        end
    end
end
