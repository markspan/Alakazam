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

            for fn = {'bf10_ttest <- function', 'fmt_bf <- function', 'bf_word <- function'}
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
            qmd = generateQuartoReport(ReportFixtures.erpEntries(), 'x.csv');

            testCase.verifySubstring(qmd, 'rank-based test was reported instead, no Bayes factor');
            testCase.verifySubstring(qmd, 'JZS prior');
            testCase.verifySubstring(qmd, 'Welch');
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
                'cat(fmt_bf(c(NA, 2000, 0.0001, 3.158488, 0.04567)), sep = "|"); cat("\n")' newline ...
                'cat(bf_word(c(NA, 1, 150, 50, 15, 5, 2, 0.5, 0.2, 0.05, 0.02, 0.005)), sep = "|"); cat("\n")' newline ...
                'cat(is.na(bf10_ttest(x = 1, mu = 0)), "\n")' newline];

            folder = testCase.applyFixture( ...
                matlab.unittest.fixtures.TemporaryFolderFixture()).Folder;
            script = fullfile(folder, 'probe.R');
            fid = fopen(script, 'w');
            fprintf(fid, '%s', probe);
            fclose(fid);

            [status, out] = system(sprintf('"%s" "%s"', rscript, script));
            testCase.assertEqual(status, 0, sprintf('The helpers did not run:\n%s', out));
            lines = strtrim(splitlines(strtrim(out)));

            testCase.verifyEqual(lines{end - 2}, 'NA|> 1000|< 0.001|3.16|0.0457', ...
                'fmt_bf formats Bayes factors wrongly.');
            testCase.verifyEqual(lines{end - 1}, strjoin({'NA', ...
                'no evidence either way', ...
                'extreme for a difference', 'very strong for a difference', ...
                'strong for a difference', 'moderate for a difference', ...
                'anecdotal for a difference', ...
                'anecdotal for no difference', 'moderate for no difference', ...
                'strong for no difference', 'very strong for no difference', ...
                'extreme for no difference'}, '|'), ...
                'bf_word reads a Bayes factor against the wrong cut-offs.');
            testCase.verifyEqual(lines{end}, 'TRUE', ...
                ['A t-test that cannot be computed should give NA, not an error, so one ' ...
                 'channel failing does not take the rest of its table with it.']);
        end
    end
end
