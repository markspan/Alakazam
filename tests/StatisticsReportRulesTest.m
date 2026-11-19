classdef StatisticsReportRulesTest < matlab.unittest.TestCase
%STATISTICSREPORTRULESTEST  The rules the generated statistics report keeps: each
%   test beside its check, one value per person where no model has a person term,
%   a mixed model that does not pretend to a slope, and error terms that fit the
%   design. The helpers these sections call are checked in R by
%   ReportStatsHelpersTest; a render at the end shows the rules reach a reader.
%
%   See also GENERATEQUARTOREPORT, LMMSECTION, REPORTDESIGNPLAN.
    properties (TestParameter)
        noPersonTerm = struct( ...
            'descriptive', @() ReportSections.descriptiveSection('W', 'mean_amplitude', 'A'), ...
            'paired', @() ReportSections.pairedSection('W', 'mean_amplitude', 'A', 'B'), ...
            'between', @() ReportSections.betweenSection('W', 'mean_amplitude', 'A'), ...
            'combo', @() ReportSections.comboSection('W', 'mean_amplitude', 'C', 'A - B'), ...
            'comboGrouped', @() ReportSections.comboSectionGrouped('W', 'mean_amplitude', 'C', 'A - B', true, true), ...
            'comboLatency', @() ReportSections.comboSection('W', 'peak_latency', 'C', 'A - B'), ...
            'circular', @() ReportSections.circularSection('W', 'phase', {'A', 'B'}));
        withCheck = struct( ...
            'paired', {{@() ReportSections.pairedSection('W', 'mean_amplitude', 'A', 'B'), 'wilcox.test('}}, ...
            'between', {{@() ReportSections.betweenSection('W', 'mean_amplitude', 'A'), 'wilcox.test(value ~ group'}}, ...
            'combo', {{@() ReportSections.comboSection('W', 'mean_amplitude', 'C', 'A - B'), 'wilcox.test(d$value'}}, ...
            'comboGrouped', {{@() ReportSections.comboSectionGrouped('W', 'mean_amplitude', 'C', 'A - B', true, true), 'wilcox.test(.x$value'}});
    end

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            import matlab.unittest.fixtures.PathFixture
            testCase.applyFixture(PathFixture(fullfile(root, 'src', 'Reports')));
            testCase.applyFixture(PathFixture(fullfile(root, 'src', 'Support')));
            testCase.applyFixture(PathFixture(fullfile(root, 'tests')));
        end
    end

    methods (Test)
        function aSectionWithNoPersonTermHasOneValuePerPerson(testCase, noPersonTerm)
            text = noPersonTerm();
            testCase.verifySubstring(text, 'grp <- per_person(grp)');
            filtered = strfind(text, 'grp <- dat %>%');
            averaged = strfind(text, 'grp <- per_person(grp)');
            testCase.verifyLessThan(filtered(1), averaged(1));
        end

        function aMixedModelKeepsEveryRecording(testCase)
        %   It has the person in it, and session designs need the replicates.
            text = ReportSections.lmmSection('W', 'mean_amplitude', {'A', 'B', 'C'}, reportDesignPlan(emptyDesign()));
            testCase.verifyFalse(contains(text, 'per_person('));
        end

        function eachTestKeepsItsCheckBesideIt(testCase, withCheck)
            text = withCheck{1}();
            testCase.verifySubstring(text, 't.test(');
            testCase.verifySubstring(text, withCheck{2});
            testCase.verifySubstring(text, 'rank_biserial_ci(');
            testCase.verifySubstring(text, 'shapiro_note(');
            testCase.verifyFalse(contains(text, 'use_parametric'), 'A normality test chooses nothing.');
            testCase.verifyFalse(contains(text, 'wilcox_effsize'), 'That is |Z| / sqrt(N), not a rank-biserial.');
            testCase.verifyFalse(contains(text, 'nboot = 200'));
            testCase.verifySubstring(text, 'cohens_d_ci(');
        end

        function theGroupsNormalityIsAboutTheirOwnMeans(testCase)
            text = ReportSections.betweenSection('W', 'mean_amplitude', 'A');
            testCase.verifySubstring(text, 'shapiro_note(d$value - ave(d$value, d$group))');
            testCase.verifyFalse(contains(text, 'shapiro.test(d$value)'), ...
                'Two groups pooled are bimodal exactly when the groups differ.');
        end

        function aSlopeIsOnlyTriedWhereThereAreReplicates(testCase)
            text = ReportSections.lmmSection('W', 'mean_amplitude', {'A', 'B', 'C'}, reportDesignPlan(emptyDesign()));
            testCase.verifySubstring(text, 'replicated <- anyDuplicated(d[c("person_id", "bin")]) > 0');
            testCase.verifySubstring(text, 'if (replicated) {');
            testCase.verifySubstring(text, 'so no slope can be separated from error');
            testCase.verifyFalse(contains(text, 'maximal model was singular'));
        end

        function theCorrectedPIsWhatGoesOn(testCase)
            text = ReportSections.lmmSection('W', 'mean_amplitude', {'A', 'B', 'C'}, reportDesignPlan(emptyDesign()));
            testCase.verifySubstring(text, 'huynh_feldt(d, intersect(c("bin", "session"), fixed_vars), intersect("group", fixed_vars))');
            testCase.verifySubstring(text, 'eff_used <- hf_row$p');
            testCase.verifySubstring(text, 'p_head <- eff_used');
            testCase.verifySubstring(text, 'p_bin <- eff_used');
        end

        function aSessionDesignHasAPersonBySessionTerm(testCase)
            txt = generateQuartoReport(ReportFixtures.censusEntries('F-ERP3S'), 'x.csv');
            testCase.verifySubstring(txt, 'value ~ bin * session + (1 + bin | person_id) + (1 | person_id:session)');
            testCase.verifySubstring(txt, 'value ~ bin * session + (1 | person_id) + (1 | person_id:session)');
        end

        function aDesignWithoutSessionsHasNone(testCase)
            txt = generateQuartoReport(ReportFixtures.censusEntries('F-ERP3C'), 'x.csv');
            testCase.verifyFalse(contains(txt, 'person_id:session'));
        end

        function theReportSaysWhenPeopleCameTwice(testCase)
            txt = generateQuartoReport(ReportFixtures.censusEntries('F-ERP3S'), 'x.csv');
            testCase.verifySubstring(txt, 'People recorded more than once');
            once = generateQuartoReport(ReportFixtures.censusEntries('F-ERP3C'), 'x.csv');
            testCase.verifyFalse(contains(once, 'People recorded more than once'));
        end

        function theSingleTrialModelKeepsTheConditionWhenSlopesFail(testCase)
            text = ReportSections.singleTrialSection('W', 'mean_amplitude', {'A', 'B'});
            slopes = strfind(text, '(1 + bin | person_id)');
            middle = strfind(text, '(1 | person_id) + (1 | person_id:bin))');
            testCase.assertNotEmpty(slopes);
            testCase.assertNotEmpty(middle);
            testCase.verifyLessThan(slopes(end), middle(1));
            testCase.verifyEmpty(regexp(text, 'm <- fit\([^\n]*\|\|', 'once'), ...
                'A double bar on a factor does not give uncorrelated slopes.');
        end

        function everyToolTheSectionsCallIsInTheSetup(testCase)
            txt = generateQuartoReport(ReportFixtures.censusEntries('F-ERP3C'), 'x.csv');
            for name = {'cohens_d_ci <- function', 'rank_biserial_ci <- function', 'shapiro_note <- function', ...
                    'per_person <- function', 'huynh_feldt <- function', 'friedman_note <- function', 'term_key <- function'}
                testCase.verifySubstring(txt, name{1});
            end
        end
    end

    methods (Test, TestTags = {'Slow', 'External'})
        function aRenderedReportShowsAllOfThis(testCase)
            testCase.assumeTrue(~isempty(ReportFixtures.rscriptExe()) && ~isempty(ReportFixtures.quartoExe()), ...
                'R and/or Quarto not found.');
            temporary = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            qmd = ReportFixtures.writeReport(moreSubjects(ReportFixtures.censusEntries('F-ERP3C'), 8), temporary.Folder, 'within');
            [htmlFile, problem] = renderQuartoReport(qmd);
            testCase.assertNotEmpty(htmlFile, problem);
            html = fileread(htmlFile);
            testCase.verifySubstring(html, 'one value per person per condition');
            testCase.verifySubstring(html, 'p_HF');
            testCase.verifySubstring(html, 'Friedman_p');
            testCase.verifySubstring(html, 'Wilcoxon signed-rank');
            testCase.verifySubstring(html, 'One-sample t-test');
            testCase.verifySubstring(html, 'Shapiro_Wilk_p');
            testCase.verifyFalse(contains(html, 'Could not be analysed'));
        end

        function aRenderedSessionReportFitsAndSaysSo(testCase)
            testCase.assumeTrue(~isempty(ReportFixtures.rscriptExe()) && ~isempty(ReportFixtures.quartoExe()), ...
                'R and/or Quarto not found.');
            temporary = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            qmd = ReportFixtures.writeReport(ReportFixtures.censusEntries('F-ERP3S'), temporary.Folder, 'session');
            [htmlFile, problem] = renderQuartoReport(qmd);
            testCase.assertNotEmpty(htmlFile, problem);
            html = fileread(htmlFile);
            testCase.verifySubstring(html, 'person_id:session');
            testCase.verifySubstring(html, 'People recorded more than once');
            testCase.verifyFalse(contains(html, 'Could not be analysed'));
            testCase.verifyFalse(contains(html, 'Did not fit'));
        end
    end
end

function entries = moreSubjects(entries, n)
%MORESUBJECTS  N subjects from one fixture subject, with noise on its scores, so
%   the corrections that need three complete people have them.
    rng(17, 'twister');
    base = entries(1);
    out = repmat(base, 1, n);
    for k = 1:n
        out(k).subject = sprintf('s%d', k);
        out(k).person = sprintf('s%d', k);
        for w = 1:numel(base.EEG.measurements)
            m = base.EEG.measurements{w};
            m.amplitude = m.amplitude + randn(size(m.amplitude));
            out(k).EEG.measurements{w} = m;
        end
    end
    entries = out;
end

function design = emptyDesign()
    design = struct('persons', struct([]), 'factors', struct([]), 'cells', struct([]));
end
