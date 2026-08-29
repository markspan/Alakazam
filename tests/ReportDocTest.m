classdef ReportDocTest < matlab.unittest.TestCase
%REPORTDOCTEST  The shared report scaffolding: one YAML header, one package
%   bootstrap, one set of APA helpers, used by all three generators.
%
%   WHAT THIS FILE IS REALLY FOR. These three pieces used to be copied into
%   generateQuartoReport, generateDataQualityReport and
%   generateClusterStatsReport, and had already drifted: apa_gt rounded
%   decimal columns to three places in two reports and two in the third,
%   undocumented, so the same table rounded differently depending on which
%   report you opened. Nobody had noticed, because nothing could.
%
%   The drift check below is therefore the point of the file, more than the
%   unit tests above it: it asserts that no generator has grown its own
%   copy back. A helper that is shared today and copied tomorrow is exactly
%   how this started.
%
%   Run with: runtests('tests/ReportDocTest.m').

    properties (Constant)
        Generators = {'generateQuartoReport', 'generateDataQualityReport', ...
            'generateClusterStatsReport'}
    end

    methods (TestClassSetup)
        function addSourceToPath(testCase)
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
        % ---- the pieces themselves ---------------------------------------
        function theHeaderIsWellFormedYaml(testCase)
            lines = ReportDoc.yamlHeader('Some Title');

            testCase.verifyEqual(lines{1}, '---');
            testCase.verifyEqual(lines{end}, '---');
            testCase.verifyEqual(lines{2}, 'title: "Some Title"');
            testCase.verifyTrue(any(strcmp(strtrim(lines), 'self-contained: true')));
        end

        function theHeaderPinsLightMode(testCase)
        %THEHEADERPINSLIGHTMODE  Not cosmetic: the plots baked into these
        %   reports are ggplot output on a white canvas with black text, so
        %   a dark-mode render leaves white rectangles in an inverted page
        %   and black axis labels on a dark ground.
            joined = strjoin(ReportDoc.yamlHeader('T'), newline);

            testCase.verifySubstring(joined, 'color-scheme" content="light"');
            testCase.verifySubstring(joined, 'background-color: #ffffff !important');
        end

        function theBootstrapQuotesEveryPackage(testCase)
            joined = strjoin(ReportDoc.packageBootstrap({'tidyverse', 'gt'}), newline);

            testCase.verifySubstring(joined, '"tidyverse"');
            testCase.verifySubstring(joined, '"gt"');
            testCase.verifySubstring(joined, 'install.packages(missing');
            testCase.verifySubstring(joined, 'invisible(lapply(pkgs, library, character.only = TRUE))');
        end

        function theBootstrapWrapsALongList(testCase)
        %THEBOOTSTRAPWRAPSALONGLIST  The statistical report loads ten
        %   packages, and this ends up in a .qmd an analyst may open.
            lines = ReportDoc.packageBootstrap({'tidyverse', 'rstatix', 'ggpubr', ...
                'gt', 'BayesFactor', 'lme4', 'lmerTest', 'emmeans', 'performance', ...
                'effectsize'});

            testCase.verifyGreaterThan(numel(lines), 4, ...
                'A ten-package list should have wrapped onto a continuation line.');
            for k = 1:numel(lines)
                testCase.verifyLessThanOrEqual(numel(lines{k}), 100, ...
                    sprintf('Line %d is too long to read in a .qmd.', k));
            end
        end

        function anEmptyPackageListIsRefused(testCase)
            testCase.verifyError(@() ReportDoc.packageBootstrap({}), ...
                'Alakazam:ReportDoc:noPackages');
        end

        function theApaHelpersDefineAllThree(testCase)
            joined = strjoin(ReportDoc.apaHelpers(), newline);

            for fn = {'apa_p <- function', 'apa_num <- function', 'apa_gt <- function'}
                testCase.verifySubstring(joined, fn{1});
            end
        end

        function apaGtRoundsToThreeDecimals(testCase)
        %APAGTROUNDSTOTHREEDECIMALS  The value the drift was over. Three is
        %   what two of the three copies used and what the surviving comment
        %   described as the intent; pinned so the question is settled once.
            joined = strjoin(ReportDoc.apaHelpers(), newline);

            testCase.verifySubstring(joined, 'all_of(dec_cols), decimals = 3');
            testCase.verifySubstring(joined, 'all_of(int_cols), decimals = 0');
        end

        % ---- the drift check ----------------------------------------------
        function noGeneratorCarriesItsOwnCopy(testCase)
        %NOGENERATORCARRIESITSOWNCOPY  The reason this file exists. Each of
        %   these markers used to appear once per generator; all three must
        %   now come from ReportDoc alone.
            root = fileparts(fileparts(mfilename('fullpath')));
            markers = {'apa_p <- function', 'apa_num <- function', ...
                'apa_gt <- function', 'self-contained: true', ...
                'install.packages(missing'};

            for g = ReportDocTest.Generators
                source = fileread(fullfile(root, 'src', 'IO', [g{1} '.m']));
                for m = markers
                    testCase.verifyEmpty(strfind(source, m{1}), ...
                        sprintf(['%s defines "%s" itself again. That is how apa_gt came ' ...
                            'to round differently in different reports; take it from ' ...
                            'ReportDoc instead.'], g{1}, m{1})); %#ok<STREMP>
                end
            end
        end

        function everyGeneratorStillProducesTheScaffolding(testCase)
        %EVERYGENERATORSTILLPRODUCESTHESCAFFOLDING  The other half: removing
        %   the copies must not have removed the content. Every generator's
        %   output still has to carry a header, a bootstrap and the helpers.
        %
        %   generateQuartoReport is driven through its real entry point; the
        %   other two need arguments this test has no fixture for, so their
        %   SOURCE is checked for the ReportDoc call instead. A weaker
        %   assertion, but it still fails if the call is deleted.
            txt = generateQuartoReport(ReportFixtures.erpEntries(), 'x.csv');

            testCase.verifySubstring(txt, 'self-contained: true');
            testCase.verifySubstring(txt, 'apa_gt <- function');
            testCase.verifySubstring(txt, 'pkgs <- c("tidyverse"');
            testCase.verifySubstring(txt, 'decimals = 3');

            root = fileparts(fileparts(mfilename('fullpath')));
            for g = ReportDocTest.Generators
                source = fileread(fullfile(root, 'src', 'IO', [g{1} '.m']));
                for call = {'ReportDoc.yamlHeader(', 'ReportDoc.packageBootstrap(', ...
                        'ReportDoc.apaHelpers('}
                    testCase.verifySubstring(source, call{1}, ...
                        sprintf('%s no longer calls %s).', g{1}, call{1}));
                end
            end
        end
    end
end
