classdef QuartoReportRenderTest < matlab.unittest.TestCase
%QUARTOREPORTRENDERTEST  Renders one analytically exact fixture end to end
%   (ReportFixtures.pairedGroundTruthEntries -> the real
%   exportMeasurementsCSV -> the real generateQuartoReport -> the real
%   renderQuartoReport) and reads the statistics back out of the rendered
%   HTML.
%
%   This is the ONLY oracle in the whole Quarto-report suite that can see a
%   defect introduced by the GENERATED R itself rather than by the MATLAB
%   text assembly. Every other file in the suite asserts on the .qmd: its
%   chunk-label census, its escaping, its CSV column contract, its R
%   syntax. All of those can be perfectly satisfied by a document whose R
%   computes the wrong quantity -- a swapped subtraction, a wrong
%   denominator, an effect size taken from the wrong pair of levels. Only
%   executing the document can tell.
%
%   The fixture is constructed so the answer is EXACT rather than merely
%   plausible, which is what lets these tests assert a number without
%   tolerance-fudging and without a random seed that could drift:
%
%       v = (1:25)', z = (v - mean(v)) / std(v)
%
%   MATLAB's std and R's sd share the N-1 denominator, so z has mean
%   exactly 0 and sd exactly 1. Bin A = v and bin B = v + 2 + z therefore
%   give paired differences of mean 2.000000 and sd 1.000000, hence
%
%       t = 2 / (1 / sqrt(25)) = 10.000000 on 24 df,  |Cohen's dz| = 2.000000
%
%   Establishing that the arithmetic is sound matters beyond this file: it
%   is precisely what makes the sign disagreement pinned by
%   QuartoReportKnownGapTest/pairedEffectSizeSignMatchesTestStatistic
%   unambiguously a SIGN-CONVENTION defect (pairedSection's t.test runs in
%   bindesc order while its rstatix::cohens_d runs in alphabetical
%   factor-level order) rather than a computation error. That sign
%   invariant is deliberately NOT asserted here: this file states only what
%   is correct today, so it stays green.
%
%   Parsing note: the render is read back through the stripped HTML, not
%   the markdown. Pandoc turns the apostrophe of "Cohen's" into a
%   typographic one (U+2019) and "<" into "&lt;", so the assertions below
%   unescape entities and match the APA sentence loosely -- one regex
%   captures df, t, dz and both CI bounds in a single pass, so the three
%   test methods share one parse rather than re-deriving it three times.
%
%   The ~40-60 s render happens ONCE, in TestClassSetup, and its qmd/csv/
%   html paths and parsed statistics are cached in properties for every
%   method to share. Nothing is ever written into the repository: the
%   report is built inside a TemporaryFolderFixture.
%
%   Both external tools are assumed, not required: the class skips cleanly
%   (as one) on a machine without R or without Quarto, and skips equally
%   cleanly when the R packages the setup chunk wants are not installed --
%   otherwise that chunk's own install.packages() branch would fire and
%   reach the network from inside a unit test.
%
%   Tagged {'Slow', 'External'}.
%
%   Run with: runtests('tests/QuartoReportRenderTest.m').

    properties (Access = private)
        %QMDFILE  The generated .qmd, inside the temporary folder.
        QmdFile char = ''

        %CSVFILE  The CSV the real exporter wrote alongside it.
        CsvFile char = ''

        %HTMLFILE  The rendered .html renderQuartoReport produced.
        HtmlFile char = ''

        %PLAINTEXT  The rendered HTML with tags stripped and entities
        %   unescaped -- what a reader actually sees.
        PlainText char = ''

        %PAIRED  The parsed APA sentence: .df, .t, .dz, .ciLow, .ciHigh.
        Paired struct = struct()

        %TRUTH  The fixture's own analytically exact expectations.
        Truth struct = struct()
    end

    methods (TestClassSetup)
        function renderGroundTruthReport(testCase)
        %RENDERGROUNDTRUTHREPORT  Put src/IO, src/Support and the tests
        %   folder (for ReportFixtures) on the path, skip the whole class
        %   when R/Quarto/the R packages are unavailable, then pay the one
        %   render cost and cache everything the methods read.
            root = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'IO')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'Support')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'tests')));

            testCase.assumeTrue( ...
                ~isempty(ReportFixtures.rscriptExe()) && ~isempty(ReportFixtures.quartoExe()), ...
                'R and/or Quarto not found; skipping render checks.');
            testCase.assumeTrue(ReportFixtures.rPackagesPresent(reportPackages()), ...
                ['Not every R package the generated setup chunk loads is installed; ' ...
                'skipping render checks rather than letting its own install.packages() ' ...
                'branch reach the network from a unit test.']);

            temporary = testCase.applyFixture( ...
                matlab.unittest.fixtures.TemporaryFolderFixture);

            [entries, truth] = ReportFixtures.pairedGroundTruthEntries();
            testCase.Truth = truth;
            [testCase.QmdFile, testCase.CsvFile] = ReportFixtures.writeReport( ...
                entries, temporary.Folder, 'paired_ground_truth');

            % Through the REAL renderQuartoReport, so its own
            % locateQuartoTools (a private local function no test can call
            % directly) is exercised for free.
            [html, errorMessage] = renderQuartoReport(testCase.QmdFile);
            testCase.assertEmpty(errorMessage, ...
                sprintf('quarto could not render the ground-truth report:\n%s', errorMessage));
            testCase.assertEqual(exist(html, 'file'), 2, ...
                'renderQuartoReport reported success but produced no HTML file.');
            testCase.HtmlFile = html;

            testCase.PlainText = plainTextOf(readWholeFile(html));
            testCase.Paired = parsePairedSentence(testCase.PlainText);
        end
    end

    methods (Test, TestTags = {'Slow', 'External'})

        function knownPairedEffectIsRecoveredExactly(testCase)
        %KNOWNPAIREDEFFECTISRECOVEREDEXACTLY  The rendered APA sentence
        %   must report the fixture's analytically exact answer: t = 10.00
        %   on 24 df with |dz| = 2.00. The tolerance is 0.005, i.e. half of
        %   the last digit the report itself prints -- nothing looser, and
        %   nothing that could absorb a genuinely different statistic.
        %
        %   |dz| rather than dz, deliberately: the sign disagreement
        %   between pairedSection's t.test and its rstatix::cohens_d is the
        %   business of QuartoReportKnownGapTest, and asserting it here
        %   would make this file red for a defect it is not pinning.
            testCase.assertTrue(isfield(testCase.Paired, 'df'), ...
                ['The rendered report carries no parsable "A paired-samples *t*-test found ..." ' ...
                'sentence at all -- see the rendered HTML at ' testCase.HtmlFile '.']);

            testCase.verifyEqual(testCase.Paired.df, testCase.Truth.df, ...
                'The paired t-test reported the wrong degrees of freedom.');
            testCase.verifyEqual(testCase.Paired.t, testCase.Truth.t, 'AbsTol', 0.005, ...
                'The paired t-test statistic is not the fixture''s exact t = 10.000.');
            testCase.verifyEqual(abs(testCase.Paired.dz), testCase.Truth.dz, 'AbsTol', 0.005, ...
                'Cohen''s dz is not the fixture''s exact |dz| = 2.000.');
        end

        function effectSizeCiBracketsItsEstimate(testCase)
        %EFFECTSIZECIBRACKETSITSESTIMATE  The reported Cohen's dz must lie
        %   inside its own reported 95% CI.
        %
        %   Green today, and trivially so: estimate and bounds all come out
        %   of one rstatix::cohens_d call. Its job is to be a guard rail
        %   against a HALF-DONE fix to the sign defect -- negating
        %   dz$effsize for the prose without also negating dz$conf.low /
        %   dz$conf.high would report dz = +2.00 with a CI of about
        %   [-2.57, -1.44], which every other assertion in this file would
        %   happily accept and this one would not.
            testCase.assertTrue(isfield(testCase.Paired, 'dz'), ...
                'The rendered report carries no parsable Cohen''s dz and CI.');

            testCase.verifyGreaterThanOrEqual(testCase.Paired.dz, testCase.Paired.ciLow, ...
                sprintf('Cohen''s dz = %.2f falls below its own reported CI lower bound %.2f.', ...
                testCase.Paired.dz, testCase.Paired.ciLow));
            testCase.verifyLessThanOrEqual(testCase.Paired.dz, testCase.Paired.ciHigh, ...
                sprintf('Cohen''s dz = %.2f exceeds its own reported CI upper bound %.2f.', ...
                testCase.Paired.dz, testCase.Paired.ciHigh));
        end

        function renderCompletesWithoutSwallowedChannelErrors(testCase)
        %RENDERCOMPLETESWITHOUTSWALLOWEDCHANNELERRORS  Every section
        %   builder wraps its per-channel body in a tryCatch that turns a
        %   genuine R error into a bland italic "*Could not be analysed:
        %   ...*" note, so a render can "succeed", exit 0 and produce a
        %   perfectly presentable HTML file while having analysed nothing
        %   at all.
        %
        %   This is the assertion that makes the other two trustworthy: it
        %   states that the numbers they read were computed rather than
        %   apologised for. "Skipped" (the deliberate too-few-subjects
        %   path) is a different message and is not asserted against here.
            testCase.verifyFalse(contains(testCase.PlainText, 'Could not be analysed'), ...
                ['A per-channel tryCatch swallowed a genuine R error: the render ' ...
                '"succeeded" while reporting no analysis. See ' testCase.HtmlFile '.']);
        end

        function theCircularSectionComputesRatherThanParses(testCase)
        %THECIRCULARSECTIONCOMPUTESRATHERTHANPARSES  The one section whose R
        %   no other test runs.
        %
        %   The syntax test hands every chunk to R's parser, which is a real
        %   oracle for form and blind to everything else: the bootstrap
        %   closure, group_modify and the sprintf calls all parse cleanly
        %   and can still die at render time, and a per-channel tryCatch
        %   would turn that into a bland italic note inside a document that
        %   looks finished. The ground-truth render above is an ERP export
        %   and reaches no circular section at all, so this renders a
        %   spectral one, which carries phase and (with a reference)
        %   phaselag.
            temporary = testCase.applyFixture( ...
                matlab.unittest.fixtures.TemporaryFolderFixture);

            entries = ReportFixtures.censusEntries('F-SPEC3CR');
            qmdFile = ReportFixtures.writeReport(entries, temporary.Folder, 'circular');

            [html, errorMessage] = renderQuartoReport(qmdFile);
            testCase.assertEmpty(errorMessage, sprintf( ...
                'quarto could not render the spectral report:\n%s', errorMessage));

            text = plainTextOf(readWholeFile(html));
            testCase.verifyFalse(contains(text, 'Could not be analysed'), ...
                ['A per-channel tryCatch swallowed a genuine R error in the ' ...
                 'circular section. See ' html '.']);
            testCase.verifySubstring(text, 'Circular Descriptive Statistics');
            testCase.verifySubstring(text, 'mean angle');
            testCase.verifySubstring(text, '95% CI');
        end

        function theCoherenceSectionComputesRatherThanParses(testCase)
        %THECOHERENCESECTIONCOMPUTESRATHERTHANPARSES  The RIFT figures.
        %
        %   Until this section existed a CoherenceMap result could be seen
        %   in the application and nowhere else, so the figure a tagging
        %   paper is built on left Alakazam only as a screenshot. The R that
        %   replaced that does two group_by/summarise passes, a faceted
        %   raster and several sprintf calls, all of which parse cleanly
        %   whatever they compute, and a per-section tryCatch would turn a
        %   genuine failure into an italic note in a document that still
        %   looks finished.
        %
        %   The fixture plants a 60 Hz response at Oz between 0 and 600 ms,
        %   so the section has something real to find and the assertions
        %   below are about content rather than the absence of an error.
            temporary = testCase.applyFixture( ...
                matlab.unittest.fixtures.TemporaryFolderFixture);
            folder = temporary.Folder;

            entries = ReportFixtures.censusEntries('F-SPEC3CR');
            [qmdFile, csvFile] = ReportFixtures.writeReport(entries, folder, 'coherence');
            [~, csvName, csvExt] = fileparts(csvFile);

            [traceFile, mapFile] = exportCoherenceCSVs( ...
                testCase.coherenceEntries(), fullfile(folder, 'coherence'));
            [~, traceName, traceExt] = fileparts(traceFile);
            [~, mapName, mapExt] = fileparts(mapFile);

            qmd = generateQuartoReport(entries, [csvName csvExt], '', '', '', '', ...
                struct('Trace', [traceName traceExt], 'Map', [mapName mapExt]));
            writeQmdFile(qmdFile, qmd, 'Alakazam:QuartoReportRenderTest');

            [html, errorMessage] = renderQuartoReport(qmdFile);
            testCase.assertEmpty(errorMessage, sprintf( ...
                'quarto could not render the coherence report:\n%s', errorMessage));

            text = plainTextOf(readWholeFile(html));
            testCase.verifyFalse(contains(text, 'Could not be analysed'), ...
                ['A tryCatch swallowed a genuine R error in the coherence ' ...
                 'section. See ' html '.']);
            testCase.verifySubstring(text, 'Coherence over time');
            testCase.verifySubstring(text, 'Tagged frequency per condition');
            testCase.verifySubstring(text, 'Channels shown');
            testCase.verifyFalse(contains(text, 'No coherence export'), ...
                'The exports were written, so the absent-file branch is wrong here.');
        end

    end

    methods (Access = private)
        function entries = coherenceEntries(~)
        %COHERENCEENTRIES  Two recordings with a planted 60 Hz tag at Oz,
        %   present between 0 and 600 ms and absent outside it, so the
        %   section's own tag detection and channel choice have a known
        %   answer to find.
            entries = struct('subject', {}, 'datasetType', {}, 'group', {}, ...
                'person', {}, 'session', {}, 'EEG', {});
            freqs = 55:1:65;
            times = linspace(-200, 800, 12);
            labels = {'Fz', 'Cz', 'Pz', 'Oz', 'PO7', 'PO8'};
            rng(7);
            for s = 1:2
                coh = 0.05 + 0.01 * rand(numel(labels), numel(freqs), numel(times));
                fIdx = find(freqs == 60, 1);
                inWindow = times > 0 & times < 600;
                coh(4, fIdx, inWindow) = 0.8;
                coh(6, fIdx, inWindow) = 0.6;
                eeg = struct('cohFreqs', freqs, 'cohTimes', times, ...
                    'chanlocs', struct('labels', labels), ...
                    'bindesc', struct('label', {'A', 'B'}, 'index', {1, 2}));
                eeg.coherence = cat(4, coh, coh * 0.5);
                entries(s) = struct('subject', sprintf('sub%02d', s), ...
                    'datasetType', 'subject', 'group', '', ...
                    'person', sprintf('p%02d', s), 'session', '', 'EEG', eeg);
            end
        end
    end
end

% =========================================================================== %
%  Local helpers (callable only from the class above)
% =========================================================================== %

function packages = reportPackages()
%REPORTPACKAGES  The R packages the generated setup chunk loads, so
%   rPackagesPresent can be asked about exactly them and the chunk's own
%   install.packages() branch can never fire during a test run.
    packages = {'tidyverse', 'rstatix', 'ggpubr', 'gt', 'BayesFactor', ...
        'lme4', 'lmerTest', 'emmeans', 'performance', 'effectsize'};
end

function txt = readWholeFile(path)
%READWHOLEFILE  A whole file as one char row vector.
    fid = fopen(path, 'r');
    if fid < 0
        throw(MException('Alakazam:QuartoReportRenderTest:cannotRead', ...
            'I am afraid I could not open "%s" for reading.', path));
    end
    closeFile = onCleanup(@() fclose(fid)); %#ok<NASGU>
    txt = fread(fid, '*char')';
end

function plain = plainTextOf(html)
%PLAINTEXTOF  HTML reduced to what a reader actually sees: script and
%   style blocks dropped whole (a self-contained render embeds a great deal
%   of both), then every remaining tag stripped, then the entities pandoc
%   introduced turned back into their characters.
%
%   Unescaping matters for this report specifically: "*p* < .001" leaves
%   pandoc as "&lt;", so a naive tag strip alone would leave the APA
%   sentence unreadable to a regex written the way an analyst reads it.
    plain = regexprep(html, '<script\b.*?</script>', ' ', 'ignorecase', 'dotall');
    plain = regexprep(plain, '<style\b.*?</style>', ' ', 'ignorecase', 'dotall');
    plain = regexprep(plain, '<[^>]*>', '');
    plain = strrep(plain, '&lt;', '<');
    plain = strrep(plain, '&gt;', '>');
    plain = strrep(plain, '&quot;', '"');
    plain = strrep(plain, '&#39;', '''');
    plain = strrep(plain, '&nbsp;', ' ');
    plain = strrep(plain, '&amp;', '&');   % last, so "&amp;lt;" does not become "<"
end

function stats = parsePairedSentence(plain)
%PARSEPAIREDSENTENCE  The paired-samples APA sentence's numbers out of the
%   stripped render, as a struct with .df, .t, .dz, .ciLow and .ciHigh, or
%   an empty struct when the sentence is not there at all.
%
%   Deliberately loose about everything except the numbers. Pandoc renders
%   "Cohen's" with a typographic apostrophe and "*d~z~*" as a d with a
%   subscripted z, which the tag strip flattens to "dz"; matching those
%   exactly would make this test fail on a pandoc upgrade rather than on a
%   statistical defect. Anchoring on "A paired-samples" instead is what
%   keeps the loose match from wandering into some other section's numbers.
%
%   A lookbehind rather than \b in front of the "t(": MATLAB's own regexp
%   does not honour \b as a word boundary (verified live -- "\bt\(" matches
%   nothing at all in text where "t\(" matches perfectly well), so a \b
%   here would silently make this test unable to see any render whatsoever.
    pattern = ['A paired-samples.*?(?<![A-Za-z0-9_])t\((\d+)\)\s*=\s*(-?\d+\.\d+)\s*,' ...
        '.*?=\s*(-?\d+\.\d+)\s*\([^)]*\)\s*,\s*' ...
        '95%\s*CI\s*\[\s*(-?\d+\.\d+)\s*,\s*(-?\d+\.\d+)\s*\]'];
    tokens = regexp(plain, pattern, 'tokens', 'once', 'dotall');
    if isempty(tokens)
        stats = struct();
        return;
    end
    stats = struct('df', str2double(tokens{1}), 't', str2double(tokens{2}), ...
        'dz', str2double(tokens{3}), 'ciLow', str2double(tokens{4}), ...
        'ciHigh', str2double(tokens{5}));
end
