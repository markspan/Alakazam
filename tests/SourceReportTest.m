classdef SourceReportTest < matlab.unittest.TestCase
%SOURCEREPORTTEST  The source-region report, and the refactor it rests on.
%
%   generateSourceReport deliberately has almost no statistics of its own:
%   it re-titles the shared generator, adds its caveats, and lets the
%   existing design logic and section builders do the rest. Two things
%   therefore need testing, and they pull in opposite directions.
%
%   That it ADDS what it should: the caveats belong at the top, where
%   somebody reading the tables will meet them, and the parcellation
%   provenance has to be printed because six months later nobody remembers
%   which inverse method or atlas produced a table.
%
%   That it CHANGED NOTHING ELSE: making generateQuartoReport take an
%   optional spec, and pulling its section loop into
%   ReportSections.statisticalSections, touched a heavily used file to serve
%   a new one. theOrdinaryReportIsUnaffected is the guard on that, and it is
%   the more important half.
%
%   The structural risk specific to this change is the notes landing INSIDE
%   the YAML front matter rather than after it, which would produce a
%   document quarto refuses to render at all -- and would not show up in any
%   string-contains assertion. theNotesLandAfterTheYamlBlock pins it.

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            for p = {fullfile(root, 'src'), fullfile(root, 'src', 'IO')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
        end
    end

    methods (Test)
        % ---- what it adds ---------------------------------------------------
        function theTitleNamesSourceRegions(testCase)
            qmd = generateSourceReport(testCase.parcellatedEntries(), 'src.csv');

            testCase.verifySubstring(qmd, 'Alakazam Source Region Statistical Report');
        end

        function theTemplateCaveatIsAtTheTop(testCase)
        %THETEMPLATECAVEATISATTHETOP  Not merely present: BEFORE the first
        %   statistical section. A caveat below the tables it qualifies has
        %   been published rather than communicated.
            qmd = generateSourceReport(testCase.parcellatedEntries(), 'src.csv');

            caveatAt = strfind(qmd, 'These are source estimates, not measurements');
            testCase.assertNotEmpty(caveatAt);

            firstSection = strfind(qmd, newline + "## ");
            if ~isempty(firstSection)
                testCase.verifyLessThan(caveatAt(1), firstSection(1));
            end
        end

        function itSaysRegionsAreNotIndependentTests(testCase)
        %ITSAYSREGIONSARENOTINDEPENDENTTESTS  The document ends with an
        %   FDR-adjusted summary across every test. Over a spatially smooth
        %   inverse that adjustment is optimistic, and the report has to say
        %   so rather than let the number speak for itself.
            qmd = generateSourceReport(testCase.parcellatedEntries(), 'src.csv');

            testCase.verifySubstring(qmd, 'not independent tests');
            testCase.verifySubstring(qmd, 'false-discovery-rate');
        end

        function itExplainsWhatTheSignMeans(testCase)
            qmd = generateSourceReport(testCase.parcellatedEntries(), 'src.csv');

            testCase.verifySubstring(qmd, 'NOT between regions');
        end

        function theParcellationSettingsArePrinted(testCase)
            entries = testCase.parcellatedEntries();

            qmd = generateSourceReport(entries, 'src.csv');

            testCase.verifySubstring(qmd, '**Parcellation:**');
            testCase.verifySubstring(qmd, 'inverse method eloreta');
            testCase.verifySubstring(qmd, 'atlas aal');
            testCase.verifySubstring(qmd, 'aggregation mean_flip');
        end

        function anEntryWithNoProvenanceInventsNone(testCase)
        %ANENTRYWITHNOPROVENANCEINVENTSNONE  A CSV exported before the
        %   parcellation settings were recorded has nothing to report. A
        %   plausible-looking made-up line would be worse than silence.
            entries = testCase.parcellatedEntries();
            entries = arrayfun(@(e) rmfield(e.EEG, 'parcellation'), entries, ...
                'UniformOutput', false);
            stripped = testCase.parcellatedEntries();
            for k = 1:numel(stripped)
                stripped(k).EEG = entries{k};
            end

            qmd = generateSourceReport(stripped, 'src.csv');

            testCase.verifyEmpty(strfind(qmd, '**Parcellation:**'));
            testCase.verifySubstring(qmd, 'These are source estimates');
        end

        function itRefusesAnEmptyExport(testCase)
            testCase.verifyError(@() generateSourceReport(struct([]), 'src.csv'), ...
                'Alakazam:generateSourceReport');
        end

        % ---- the structural risk ---------------------------------------------
        function theNotesLandAfterTheYamlBlock(testCase)
        %THENOTESLANDAFTERTHEYAMLBLOCK  YAML front matter is delimited by
        %   two '---' lines. Markdown injected between them is not a caveat,
        %   it is a broken document that quarto refuses outright -- and no
        %   "does it contain the text" assertion would notice.
            qmd = generateSourceReport(testCase.parcellatedEntries(), 'src.csv');
            lines = string(splitlines(qmd));

            delims = find(strtrim(lines) == "---");
            testCase.assertGreaterThanOrEqual(numel(delims), 2);
            noteAt = find(contains(lines, 'These are source estimates'), 1);

            testCase.verifyGreaterThan(noteAt, delims(2), ...
                'The caveat was written inside the YAML front matter.');
        end

        % ---- what it must NOT have changed -------------------------------------
        function theOrdinaryReportIsUnaffected(testCase)
        %THEORDINARYREPORTISUNAFFECTED  The guard on the refactor. Calling
        %   generateQuartoReport the way everything else calls it must give
        %   exactly what it gave before the spec argument existed.
            entries = ReportFixtures.erpEntries();

            qmd = generateQuartoReport(entries, 'meas.csv');

            testCase.verifySubstring(qmd, 'Alakazam ERP Statistical Report');
            testCase.verifyEmpty(strfind(qmd, 'These are source estimates'));
            testCase.verifyEmpty(strfind(qmd, 'Source Region'));
        end

        function anEmptySpecIsTheSameAsNoSpec(testCase)
            entries = ReportFixtures.erpEntries();

            testCase.verifyEqual(generateQuartoReport(entries, 'meas.csv', struct()), ...
                generateQuartoReport(entries, 'meas.csv'));
        end

        function bothReportsBuildTheSameStatisticalSections(testCase)
        %BOTHREPORTSBUILDTHESAMESTATISTICALSECTIONS  The point of sharing
        %   ReportSections.statisticalSections: the design decides the
        %   tests, not what the numbers were measured from. If these ever
        %   diverge, one of the two has grown its own copy of the logic.
            plain  = generateQuartoReport(ReportFixtures.erpEntries(), 'meas.csv');
            source = generateSourceReport(testCase.parcellatedEntries(), 'src.csv');

            testCase.verifyEqual(count(string(source), "```{r}"), ...
                count(string(plain), "```{r}"), ...
                'The two reports emitted different numbers of R chunks.');
        end
    end

    methods (Access = private)
        function entries = parcellatedEntries(~)
        %PARCELLATEDENTRIES  An ordinary ERP export, relabelled as though it
        %   had come through Parcellate: region names instead of electrodes,
        %   plus the provenance Parcellate records on its output.
            entries = ReportFixtures.erpEntries();
            for k = 1:numel(entries)
                entries(k).EEG.isParcellated = true;
                entries(k).EEG.parcellation = struct( ...
                    'Method', 'eloreta', 'Atlas', 'aal', 'Mode', 'mean_flip', ...
                    'Regions', {{'Precentral_L', 'Temporal_Mid_R'}});
            end
        end
    end
end
