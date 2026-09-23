classdef ReportTokensTest < matlab.unittest.TestCase
%REPORTTOKENSTEST  No report is left holding a template placeholder.
%
%   Every section builder writes R and markdown with placeholders such as
%   __WINDOW_R__ and __BLOCKMATCHDIAGNOSTIC__, and fills them in a fixed order. A
%   placeholder that is introduced by a later fill than the one that would have
%   replaced it survives into the document. That happened: the circular and
%   single-trial sections filled the common tokens first and inserted the block-match
%   diagnostic afterwards, so the diagnostic's own __WINDOW_R__ was never replaced.
%   The R printed the literal text (markdown made it bold: "window: WINDOW_R") and
%   looked for a window of that name in the data, so its list of the bin values
%   seen for the window was always empty.
%
%   Nothing parses or renders the placeholders, so nothing failed. This test builds
%   the report for every design the census covers, with and without the single-trial
%   export, and looks for any upper-case placeholder left in the text.
%
%   Run with: runtests('tests/ReportTokensTest.m').
%
%   See also REPORTFIXTURES, GENERATEQUARTOREPORT, REPORTSECTIONS.FILLCOMMONTOKENS.

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            for p = {fullfile(root, 'src', 'Reports'), fullfile(root, 'src', 'Support'), ...
                     fullfile(root, 'src', 'Transformations'), fullfile(root, 'tests')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
        end
    end

    methods (Test)
        function noDesignLeavesAPlaceholderInItsReport(testCase)
            ids = ReportFixtures.censusIds();
            for k = 1:numel(ids)
                entries = ReportFixtures.censusEntries(ids{k});
                % Every optional export as well as none: the waveform,
                % spectrum, single-trial and coherence sections only exist
                % when their CSV was written, and a token left in one of
                % those was invisible to this test while it passed '' for
                % them. That is the same blind spot that let a nested-cell
                % bug into waveformSection.
                for optional = {{'', '', ''}, {'ga.csv', 'trials.csv', 'spectra.csv'}}
                    csvs = optional{1};
                    qmd = generateQuartoReport(entries, 'x.csv', '', csvs{1}, csvs{2}, csvs{3}, ...
                        struct('Trace', 'tr.csv', 'Map', 'map.csv', 'Reference', 'ref.csv', ...
                               'Channels', {{'Oz', 'Cz'}}));
                    left = regexp(qmd, '__[A-Z][A-Z0-9]*(?:_[A-Z0-9]+)*__', 'match');
                    testCase.verifyEmpty(unique(left), sprintf( ...
                        'Design %s (with the optional exports: %d) still holds: %s', ids{k}, ...
                        ~isempty(csvs{1}), strjoin(unique(left), ', ')));
                end
            end
        end

        function theBlockMatchDiagnosticNamesTheRealWindow(testCase)
        %THEBLOCKMATCHDIAGNOSTICNAMESTHEREALWINDOW  The diagnostic prints the block's
        %   window and lists the bin values the data holds for it, so the R has to
        %   test against the window's own label, in the circular section (phase-lag,
        %   which the reference-channel spectral fixture produces) as in the others.
            entries = ReportFixtures.censusEntries('F-SPEC3CR');
            qmd = generateQuartoReport(entries, 'x.csv');

            lines = splitlines(qmd);
            hits = lines(contains(lines, 'Distinct raw bin value(s) seen'));
            testCase.assertNotEmpty(hits, 'The fixture should produce block-match diagnostics.');
            testCase.verifyFalse(any(contains(qmd, 'window == "__')), ...
                'A diagnostic compares the data with a placeholder instead of the window.');
        end
    end
end
