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
        %RENDERGROUNDTRUTHREPORT  Put src/Reports, src/Support and the tests
        %   folder (for ReportFixtures) on the path, skip the whole class
        %   when R/Quarto/the R packages are unavailable, then pay the one
        %   render cost and cache everything the methods read.
            root = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'Reports')));
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

        function aBayesFactorIsReportedBesideTheTTest(testCase)
        %ABAYESFACTORISREPORTEDBESIDETHETTEST  The reading guide promised
        %   Bayes factors beside every t-test for a long time while no
        %   section computed one; the BayesFactor package had even dropped
        %   out of the setup chunk. Parsing proves nothing here, since the
        %   helpers can parse and still return NA for every channel, so this
        %   reads the rendered table.
        %
        %   The fixture's paired effect is exact, t = 10.00 on 24 df, and for
        %   a paired design the default JZS Bayes factor depends only on t
        %   and n. At that t it is in the millions, so the table has to show
        %   the capped value and the strongest reading, and nothing less.
            testCase.verifySubstring(testCase.PlainText, 'BF10', ...
                ['The rendered report has no BF10 column. See ' testCase.HtmlFile '.']);
            testCase.verifySubstring(testCase.PlainText, '> 1000', ...
                'A t of 10 on 24 df should give a Bayes factor shown as > 1000.');
            testCase.verifySubstring(testCase.PlainText, 'extreme for a difference', ...
                'A Bayes factor above 100 should be read as extreme evidence for a difference.');
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
            testCase.verifySubstring(text, 'mean_angle_deg');
            testCase.verifySubstring(text, 'ci_lo_deg');
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
            [text, html] = testCase.renderCoherence(testCase.coherenceEntries());

            testCase.verifyFalse(contains(text, 'Could not be analysed'), ...
                ['A tryCatch swallowed a genuine R error in the coherence ' ...
                 'section. See ' html '.']);
            testCase.verifySubstring(text, 'Coherence over time');
            testCase.verifySubstring(text, 'Tagged frequency per condition');
            testCase.verifySubstring(text, 'Channels shown');
            testCase.verifyFalse(contains(text, 'No coherence export'), ...
                'The exports were written, so the absent-file branch is wrong here.');
            testCase.verifySubstring(text, 'Coherence at the Tagged Frequency');
            testCase.verifySubstring(text, 'Chance (1/N)');
            testCase.verifySubstring(text, 'Before 0 ms');
            testCase.verifyFalse(contains(text, 'no baseline period'), ...
                'These epochs start before 0 ms, so a baseline exists and nothing should say otherwise.');
            testCase.verifySubstring(text, 'Reference spectrum');
            testCase.verifySubstring(text, 'Strongest reference frequency per condition');
            testCase.verifyFalse(contains(text, 'Outside the analysed band'), ...
                'Both conditions are tagged inside the band, so nothing should be flagged.');
            testCase.verifyFalse(contains(text, 'tagged at different frequencies'), ...
                'Both conditions share one tag, so the frequency warning is wrong here.');
        end

        function theCoherenceSectionChoosesChannelsPerConditionAndIgnoresAGrandAverage(testCase)
        %THECOHERENCESECTIONCHOOSESCHANNELSPERCONDITIONANDIGNORESAGRANDAVERAGE
        %   Two problems found on the first real ten-subject run. (1) A grand
        %   average in the workspace was counted as an eleventh recording
        %   ("Averaged over 11"). (2) The four highlighted channels, which the
        %   table's Peak describes, were chosen across all conditions at once, so
        %   when a strong condition came into the analysed band it took over the
        %   channel set and the 60 Hz Peak fell from 0.290 to 0.213 with nothing
        %   changed in that condition.
        %
        %   The fixture has condition A responding at channels 1 to 4 (coherence
        %   0.83) and condition B at channels 5 to 8 (0.67). Chosen across both,
        %   the four strongest are all A's, so B's row would describe channels
        %   that do not respond in B and read about 0.06. Chosen per condition it
        %   reads 0.670. Two recordings plus a grand average must read as two.
            [text, html] = testCase.renderCoherence(testCase.perConditionEntries());

            testCase.verifyFalse(contains(text, 'Could not be analysed'), ...
                ['A tryCatch swallowed a genuine R error in the coherence ' ...
                 'section. See ' html '.']);
            testCase.verifySubstring(text, 'Averaged over 2 recording(s)');
            testCase.verifyFalse(contains(text, 'Averaged over 3 recording(s)'), ...
                'The grand average was counted as a recording.');
            testCase.verifySubstring(text, '0.830');
            testCase.verifySubstring(text, '0.670');
            testCase.verifySubstring(text, 'Oz mean (SD)');
            testCase.verifySubstring(text, 'Dimigen et al. (2025) report');
        end

        function theCoherenceSectionSaysSoWhenTheEpochsHaveNoBaseline(testCase)
        %THECOHERENCESECTIONSAYSSOWHENTHEEPOCHSHAVENOBASELINE  The real RIFT
        %   epochs run from 0 ms, so nothing precedes the stimulus. A "Before
        %   0 ms" column that is blank for every condition reads as a
        %   measurement that failed; the section has to drop it and say why.
            entries = testCase.outOfBandEntries();
            for s = 1:numel(entries)
                entries(s).EEG.cohTimes = entries(s).EEG.cohTimes + 200;   % -200..800 ms becomes 0..1000 ms
            end
            [text, html] = testCase.renderCoherence(entries);

            testCase.verifyFalse(contains(text, 'Could not be analysed'), ...
                ['A tryCatch swallowed a genuine R error in the coherence ' ...
                 'section. See ' html '.']);
            testCase.verifySubstring(text, 'Coherence at the Tagged Frequency');
            testCase.verifySubstring(text, 'no baseline period');
            testCase.verifyFalse(contains(text, 'Before 0 ms'), ...
                'With no time before 0 ms the column can only be empty, so it should not be shown.');
        end

        function theCoherenceSectionSaysWhenATagIsOutsideTheBandOrTheFrequenciesDiffer(testCase)
        %THECOHERENCESECTIONSAYSWHENATAGISOUTSIDETHEBANDORTHEFREQUENCIESDIFFER
        %   The situation reported from real RIFT data: a 30 Hz SSVEP
        %   condition analysed over a band that stops at 65 Hz was printed as
        %   "SSVEP 30Hz at 60.00 Hz", the strongest thing inside the band and
        %   a 1% residual of the photodiode. The section has to say the
        %   reference actually peaks at 30 Hz, outside the band, and that
        %   conditions tagged at 60 and 64 Hz differ in frequency, and it has
        %   to note that one recording disagreed about the 64 Hz tag.
            [text, html] = testCase.renderCoherence(testCase.outOfBandEntries());

            testCase.verifyFalse(contains(text, 'Could not be analysed'), ...
                ['A tryCatch swallowed a genuine R error in the coherence ' ...
                 'section. See ' html '.']);
            testCase.verifySubstring(text, ...
                'SSVEP 30Hz at 60.00 Hz (the strongest inside the band; the reference peaks at 30.00 Hz)');
            testCase.verifySubstring(text, 'Reference peak (Hz)');
            testCase.verifySubstring(text, 'Outside the analysed band');
            testCase.verifySubstring(text, 'SSVEP 30Hz (the reference peaks at 30.00 Hz');
            testCase.verifySubstring(text, 'the band covers 55.00 to 65.00 Hz');
            testCase.verifySubstring(text, 'Conditions were tagged at different frequencies');
            testCase.verifySubstring(text, ...
                'Recordings did not all find the same tag for RIFT 64Hz (2 of 3 agreed)');
            testCase.verifySubstring(text, 'Coherence at the Tagged Frequency');
        end

        function theCoherenceSectionShowsOnlyTheChannelsTheSpectralMeasureRowsName(testCase)
        %THECOHERENCESECTIONSHOWSONLYTHECHANNELSTHESPECTRALMEASUREROWSNAME
        %   With two Spectral Measure rows on Oz and newcrossf ticked, the
        %   report still drew every channel in both coherence figures. It now
        %   follows the rows: only Oz, in colour and with no grey field behind
        %   it, and the prose says the channel was named, not picked for its
        %   response.
        %
        %   Oz is channel 4 of ten, in condition A's responding channels
        %   (0.83) and outside condition B's (0.67 sits at channels 5 to 8).
        %   B's Peak must therefore read as noise, about 0.06. Had the export
        %   kept every channel, "the four that responded most" would have
        %   put 0.670 in the table.
            [text, html] = testCase.renderCoherence(testCase.perConditionEntries(), {'Oz'});

            testCase.verifyFalse(contains(text, 'Could not be analysed'), ...
                ['A tryCatch swallowed a genuine R error in the coherence ' ...
                 'section. See ' html '.']);
            testCase.verifySubstring(text, ...
                'Only the channels named in the Spectral Measure rows are drawn (Oz)');
            testCase.verifySubstring(text, ...
                'Channels shown: Oz, the channels named in the Spectral Measure rows.');
            testCase.verifyFalse(contains(text, 'The grey lines are the remaining channels'), ...
                'Nothing is drawn in grey when the channels were named.');
            testCase.verifyFalse(contains(text, 'unlike the channels in colour'), ...
                'The channels in colour were named in advance, so Oz is not being contrasted with them.');
            testCase.verifySubstring(text, '0.830');
            testCase.verifyFalse(contains(text, '0.670'), ...
                'Channels 5 to 8 are not Oz; condition B''s response there must not reach the table.');
        end

        function theCoherenceSectionDescribesAnUnnarrowedExportAsTheGeneralFigure(testCase)
        %THECOHERENCESECTIONDESCRIBESANUNNARROWEDEXPORTASTHEGENERALFIGURE
        %   Named channels that no dataset has (a montage that differs from
        %   the analyst's) fall back to the whole montage in the export. The
        %   report must then describe what it drew, not claim it followed
        %   the rows.
            [text, html] = testCase.renderCoherence(testCase.coherenceEntries(), {'NoSuchElectrode'});

            testCase.verifyFalse(contains(text, 'Could not be analysed'), ...
                ['A tryCatch swallowed a genuine R error in the coherence ' ...
                 'section. See ' html '.']);
            testCase.verifySubstring(text, 'The grey lines are the remaining channels');
            testCase.verifyFalse(contains(text, 'the channels named in the Spectral Measure rows'), ...
                'The export holds every channel, so it did not follow the rows.');
            testCase.verifySubstring(text, 'the ones with the strongest response in each condition');
        end

    end

    methods (Access = private)
        function [text, html] = renderCoherence(testCase, coherenceData, named)
        %RENDERCOHERENCE  Export the coherence CSVs for COHERENCEDATA, render a
        %   real report over them, and return its visible text and file. NAMED
        %   are the electrodes the Spectral Measure rows name: the export is
        %   narrowed to them and the report told so, as onExportSpectral does.
            if nargin < 3
                named = {};
            end
            temporary = testCase.applyFixture( ...
                matlab.unittest.fixtures.TemporaryFolderFixture);
            folder = temporary.Folder;

            entries = ReportFixtures.censusEntries('F-SPEC3CR');
            [qmdFile, csvFile] = ReportFixtures.writeReport(entries, folder, 'coherence');
            [~, csvName, csvExt] = fileparts(csvFile);

            [traceFile, mapFile, ~, referenceFile] = exportCoherenceCSVs( ...
                coherenceData, fullfile(folder, 'coherence'), ...
                struct('OnlyChannels', {named}));
            [~, traceName, traceExt] = fileparts(traceFile);
            [~, mapName, mapExt] = fileparts(mapFile);
            [~, refName, refExt] = fileparts(referenceFile);

            qmd = generateQuartoReport(entries, [csvName csvExt], '', '', '', '', ...
                struct('Trace', [traceName traceExt], 'Map', [mapName mapExt], ...
                       'Reference', [refName refExt], 'Channels', {named}));
            writeQmdFile(qmdFile, qmd, 'Alakazam:QuartoReportRenderTest');

            [html, errorMessage] = renderQuartoReport(qmdFile);
            testCase.assertEmpty(errorMessage, sprintf( ...
                'quarto could not render the coherence report:\n%s', errorMessage));
            text = plainTextOf(readWholeFile(html));
        end

        function entries = perConditionEntries(~)
        %PERCONDITIONENTRIES  Two subjects and their grand average, ten channels
        %   (Oz is the fourth). Condition A responds at channels 1 to 4 (0.83) and
        %   condition B at channels 5 to 8 (0.67), both at 60 Hz. The grand
        %   average carries the same data, as a real one carries the subjects' mean.
            entries = struct('subject', {}, 'datasetType', {}, 'group', {}, ...
                'person', {}, 'session', {}, 'EEG', {});
            freqs = 55:1:65;
            times = linspace(-200, 800, 12);
            labels = {'Fz', 'Cz', 'Pz', 'Oz', 'PO7', 'PO8', 'O1', 'O2', 'P3', 'P4'};
            fIdx = find(freqs == 60, 1);
            inWindow = times > 0 & times < 600;
            names = {'sub01', 'sub02', 'ga'};
            types = {'subject', 'subject', 'grand_average'};
            rng(5);
            for s = 1:3
                coh = 0.05 + 0.01 * rand(numel(labels), numel(freqs), numel(times), 2);
                coh(1:4, fIdx, inWindow, 1) = 0.83;
                coh(5:8, fIdx, inWindow, 2) = 0.67;
                refPower = 1e-3 * ones(numel(freqs), numel(times), 2);
                refPower(fIdx, inWindow, :) = 1;
                eeg = struct('cohFreqs', freqs, 'cohTimes', times, ...
                    'chanlocs', struct('labels', labels), ...
                    'bindesc', struct('label', {'A', 'B'}, 'index', {1, 2}, ...
                        'trials', {1:20, 1:20}));
                eeg.coherence = coh;
                eeg.cohRefPower = refPower;
                eeg = withReferenceSpectrum(eeg, [60 60]);
                entries(s) = struct('subject', names{s}, 'datasetType', types{s}, ...
                    'group', '', 'person', names{s}, 'session', '', 'EEG', eeg);
            end
        end

        function entries = outOfBandEntries(~)
        %OUTOFBANDENTRIES  Three recordings, three conditions. RIFT 60Hz: tag
        %   and reference peak both at 60 Hz. SSVEP 30Hz: the reference peaks
        %   at 30 Hz, OUTSIDE the 55 to 65 Hz band, so the strongest in-band
        %   frequency is a 60 Hz residual. RIFT 64Hz: tagged at 64 Hz, except
        %   in the third recording, whose reference peaks at 63 Hz.
            entries = struct('subject', {}, 'datasetType', {}, 'group', {}, ...
                'person', {}, 'session', {}, 'EEG', {});
            freqs = 55:1:65;
            times = linspace(-200, 800, 12);
            labels = {'Fz', 'Cz', 'Pz', 'Oz', 'PO7', 'PO8'};
            inWindow = times > 0 & times < 600;
            rng(11);
            for s = 1:3
                tagsHz = [60 60 64];
                if s == 3
                    tagsHz(3) = 63;
                end
                coh = 0.05 + 0.01 * rand(numel(labels), numel(freqs), numel(times), 3);
                refPower = 1e-3 * ones(numel(freqs), numel(times), 3);
                for b = 1:3
                    fIdx = find(freqs == tagsHz(b), 1);
                    coh(4, fIdx, inWindow, b) = 0.8;
                    refPower(fIdx, inWindow, b) = 1;
                end
                eeg = struct('cohFreqs', freqs, 'cohTimes', times, ...
                    'chanlocs', struct('labels', labels), ...
                    'bindesc', struct('label', {'RIFT 60Hz', 'SSVEP 30Hz', 'RIFT 64Hz'}, ...
                        'index', {1, 2, 3}, 'trials', {1:20, 1:20, 1:20}));
                eeg.coherence = coh;
                eeg.cohRefPower = refPower;
                eeg = withReferenceSpectrum(eeg, [tagsHz(1) 30 tagsHz(3)]);
                entries(s) = struct('subject', sprintf('sub%02d', s), ...
                    'datasetType', 'subject', 'group', '', ...
                    'person', sprintf('p%02d', s), 'session', '', 'EEG', eeg);
            end
        end

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
                    'bindesc', struct('label', {'A', 'B'}, 'index', {1, 2}, 'trials', {1:20, 1:20}));
                eeg.coherence = cat(4, coh, coh * 0.5);

                % The reference (photodiode) channel's own power, exercising
                % the real tag-detection path end to end rather than only
                % the channel-averaged fallback: a clean 60 Hz peak inside
                % the response window, agreeing with the coherence planted
                % above so this test's existing assertions still hold.
                refPower = 1e-3 * ones(numel(freqs), numel(times));
                refPower(fIdx, inWindow) = 1;
                eeg.cohRefPower = cat(3, refPower, refPower);
                eeg = withReferenceSpectrum(eeg, [60 60]);
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

function eeg = withReferenceSpectrum(eeg, peakHz)
%WITHREFERENCESPECTRUM  Store the reference channel's own spectrum on EEG: a
%   flat floor with one sharp peak per condition at PEAKHZ, over 0 to 150 Hz.
    specFreqs = 0:0.25:150;
    spec = 1e-3 * ones(numel(specFreqs), numel(peakHz));
    for b = 1:numel(peakHz)
        [~, k] = min(abs(specFreqs - peakHz(b)));
        spec(k, b) = 10;
    end
    eeg.cohRefSpectrum = single(spec);
    eeg.cohRefSpecFreqs = specFreqs;
    eeg.cohRefPeakHz = peakHz;
end

function packages = reportPackages()
%REPORTPACKAGES  The R packages the generated setup chunk loads, so
%   rPackagesPresent can be asked about exactly them and the chunk's own
%   install.packages() branch can never fire during a test run.
%
%   READ FROM A GENERATED REPORT, NOT TYPED OUT HERE. This used to be a
%   hand-kept copy of the generator's list, and a copy drifts: BayesFactor
%   was added to the report when its Bayes factors went in, and a stale copy
%   here would have let this whole class run against a machine without it,
%   the setup chunk would then have tried to install it from the network in
%   the middle of a unit test. Parsing the list out of real output means the
%   two cannot disagree.
    qmd = generateQuartoReport(ReportFixtures.erpEntries(), 'x.csv');
    block = regexp(qmd, 'pkgs <- c\((.*?)\)', 'tokens', 'once');
    packages = regexp(block{1}, '"([^"]+)"', 'tokens');
    packages = cellfun(@(c) c{1}, packages, 'UniformOutput', false);
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
    % Pandoc's smart typography writes a literal non-breaking space (U+00A0),
    % not the entity, after an abbreviation such as "et al." A reader sees a
    % space there, and an assertion typed with one would never match it.
    plain = strrep(plain, char(160), ' ');
    plain = strrep(plain, '&amp;', '&');   % last, so "&amp;lt;" does not become "<"
end

function stats = parsePairedSentence(plain)
%PARSEPAIREDSENTENCE  The paired t-test row's numbers out of the "Test
%   Result" gt table in the stripped render, as a struct with .df, .t,
%   .dz, .ciLow and .ciHigh, or an empty struct when the row is not there
%   at all.
%
%   Anchored on the table's own "Paired t-test" cell, which the Wilcoxon
%   branch (a differently-labelled, differently-shaped row) cannot
%   produce -- this ground-truth fixture's Shapiro-Wilk p-value is .39
%   (checked directly against R), so the parametric branch is the one
%   that always renders here, but anchoring on its own label rather than
%   assuming that is what keeps this loose match from wandering into some
%   other row. A gt table's cells each sit on their own line once tags
%   are stripped, so the pattern spans newlines (dotall) between them
%   rather than assuming single spaces.
    pattern = ['Paired t-test\s*(-?\d+\.\d+)\s*(\d+)\s*[<=]\s*\S+\s*' ...
        '[^0-9\-]*?(-?\d+\.\d+)\s*(-?\d+\.\d+)\s*(-?\d+\.\d+)'];
    tokens = regexp(plain, pattern, 'tokens', 'once', 'dotall');
    if isempty(tokens)
        stats = struct();
        return;
    end
    stats = struct('df', str2double(tokens{2}), 't', str2double(tokens{1}), ...
        'dz', str2double(tokens{3}), 'ciLow', str2double(tokens{4}), ...
        'ciHigh', str2double(tokens{5}));
end
