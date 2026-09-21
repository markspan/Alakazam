classdef ReportProseTruthTest < matlab.unittest.TestCase
%REPORTPROSETRUTHTEST  Sentences in the statistics report that were not true of
%   the report they sat in, and the fixes that made them true.
%
%   Found by rendering the ERP and spectral fixtures and reading every sentence
%   against the code that produces the numbers beside it:
%
%     - The reading guide said each result was "stated as an estimate first:
%       which condition was larger, by how much", after the narrated sentences
%       that did so had been replaced by tables, and that the raw difference was
%       reported beside every standardised effect. It was not.
%     - The summary said it "gathers every test reported above". The pairwise
%       comparisons after a mixed model and the per-group tests of a combination
%       bin are not in its table.
%     - The pairwise comparisons were captioned "run only because the effect
%       they follow up was significant", but the within-subjects and mixed
%       designs run them unconditionally; only the session design gates them.
%     - The forest plot labelled every point from a paired, one-sample or
%       two-group design "Cohen's d / dz", including rows where a rank-based
%       test was run and the estimate is a rank-biserial r.
%     - The circular section's table listed the combination bin among the
%       conditions, and the combination bin of a circular measure was given a
%       linear mean and SD, under a sentence saying those are not valid for it.
%     - The block diagnostic said "window: 10Hz" in a spectral report.
%
%   Run with: runtests('tests/ReportProseTruthTest.m').
%
%   See also GENERATEQUARTOREPORT, REPORTSECTIONS.TESTCAPTION,
%   REPORTSECTIONS.CIRCULARSTATSLINES.

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            here = fileparts(mfilename('fullpath'));
            root = fileparts(here);
            for p = {fullfile(root, 'src', 'Reports'), fullfile(root, 'src', 'Support'), ...
                     fullfile(root, 'src', 'Transformations'), here}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
        end
    end

    methods (Test)
        function theGuideDescribesTablesNotNarratedEstimates(testCase)
            qmd = generateQuartoReport(ReportFixtures.censusEntries('F-ERP2'), 'x.csv');

            testCase.verifyFalse(contains(qmd, 'estimate first'), ...
                'No section states an estimate before its test any more.');
            testCase.verifyFalse(contains(qmd, 'Both are reported where both exist'), ...
                'The raw difference is not reported beside every standardised effect.');
            testCase.verifySubstring(qmd, 'the rank-biserial *r* beside a rank-based test');
            testCase.verifySubstring(qmd, 'descriptive table');
        end

        function aSpectralReportTalksAboutFrequencies(testCase)
            qmd = generateQuartoReport(ReportFixtures.censusEntries('F-SPEC3C'), 'x.csv');
            erp = generateQuartoReport(ReportFixtures.censusEntries('F-ERP2'), 'x.csv');

            testCase.verifySubstring(qmd, 'block_unit <- "frequency"');
            testCase.verifySubstring(erp, 'block_unit <- "time window"');
            testCase.verifySubstring(qmd, 'run on the frequencies, channels and conditions');
            testCase.verifyFalse(contains(qmd, 'this block (window: %s)'), ...
                'The diagnostic must name the block by its unit, not always "window".');
        end

        function theSummarySaysWhatItsTableLeavesOut(testCase)
            qmd = generateQuartoReport(ReportFixtures.censusEntries('F-ERP3CG'), 'x.csv');

            testCase.verifyFalse(contains(qmd, 'gathers every test reported above'));
            testCase.verifySubstring(qmd, 'The pairwise comparisons that follow a mixed model');
            testCase.verifySubstring(qmd, 'whether the difference between conditions itself differs', ...
                'In a mixed design the primary test is the interaction, not whether the conditions differ.');
        end

        function thePostHocCaptionMatchesWhetherTheyWereGated(testCase)
            within = generateQuartoReport(ReportFixtures.censusEntries('F-ERP3C'), 'x.csv');
            mixed = generateQuartoReport(ReportFixtures.censusEntries('F-ERP3CG'), 'x.csv');
            session = generateQuartoReport(ReportFixtures.censusEntries('F-ERP3S'), 'x.csv');
            gated = ReportSections.testCaption('emmeans_holm_gated');
            always = ReportSections.testCaption('emmeans_holm');

            testCase.verifySubstring(within, ReportSections.rLit(always));
            testCase.verifyFalse(contains(within, ReportSections.rLit(gated)), ...
                'The within-subjects design runs its pairwise comparisons whatever the model gave.');
            testCase.verifyFalse(contains(mixed, ReportSections.rLit(gated)));
            testCase.verifySubstring(session, ReportSections.rLit(gated), ...
                'The session design runs them only after a significant effect, and should say so.');
        end

        function theForestPlotNamesARankBasedEffect(testCase)
            qmd = generateQuartoReport(ReportFixtures.censusEntries('F-ERP2'), 'x.csv');

            rankRule = strfind(qmd, '"mann_whitney_u") ~ "Rank-biserial r"');
            dRule = strfind(qmd, '~ "Cohen''s d / dz"');
            testCase.assertNotEmpty(rankRule, 'A rank-based test must be labelled with its own effect size.');
            testCase.assertNotEmpty(dRule);
            testCase.verifyLessThan(rankRule(1), dRule(1), ...
                'case_when takes the first match, so the rank-based rule must come first.');
            testCase.verifyFalse(contains(qmd, 'design %in% c("paired_t", "one_sample_vs_0", "indep_t") ~'), ...
                'Labelling by design alone calls a rank-biserial r a Cohen''s d.');
        end

        function circularMeasuresGetCircularStatisticsOnly(testCase)
            qmd = generateQuartoReport(ReportFixtures.censusEntries('F-SPEC3CR'), 'x.csv');

            ordinary = ReportProseTruthTest.section(qmd, '## 10Hz -- phase');
            combo = ReportProseTruthTest.section(qmd, '## 10Hz -- phase: A-B');

            testCase.verifySubstring(ordinary, 'bin %in% c("A", "B", "C")', ...
                'The conditions table must not list the combination bin.');
            testCase.verifySubstring(combo, 'atan2(mean(sin(value)), mean(cos(value)))', ...
                'A combination bin of a phase is an angle too.');
            testCase.verifyFalse(contains(combo, 'M = mean(value)'), ...
                'A linear mean of an angle is what the section''s own sentence rules out.');
            testCase.verifyFalse(contains(combo, 'ggplot('), ...
                'No linear plot of an angle, as for the ordinary bins.');
        end

        function aLatencyCombinationKeepsItsLinearSummary(testCase)
            qmd = generateQuartoReport(ReportFixtures.censusEntries('F-ERP3C'), 'x.csv');

            combo = ReportProseTruthTest.section(qmd, '## N400 -- peak\_latency: A-B');   % mdLit escapes the underscore
            testCase.verifySubstring(combo, 'M = mean(value)');
            testCase.verifySubstring(combo, 'ggplot(');
        end
    end

    methods (Static, Access = private)
        function s = section(qmd, heading)
        %SECTION  From HEADING (a whole line) to the next level-two heading.
            lines = splitlines(qmd);
            at = find(strcmp(lines, heading), 1);
            assert(~isempty(at), 'No section headed "%s".', heading);
            rest = lines(at + 1:end);
            stop = find(startsWith(rest, '## '), 1);
            if isempty(stop)
                stop = numel(rest) + 1;
            end
            s = strjoin(rest(1:stop - 1), newline);
        end
    end
end
