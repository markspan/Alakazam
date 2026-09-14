classdef DataQualityProvenanceTest < matlab.unittest.TestCase
%DATAQUALITYPROVENANCETEST  The data-quality report's record of WHAT each
%   cleaning step did, as opposed to how much data was lost.
%
%   The rest of the report answers "how much went"; these rows answer "what
%   took it" -- which detector cost which trials, and what the correction
%   steps removed. All of it is read off the dataset, where each step wrote
%   it as it ran, so these cases build those records by hand and test the
%   reading rather than re-running ICA.
%
%   Run with: runtests('tests/DataQualityProvenanceTest.m').

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            for p = {fullfile(root, 'src', 'IO'), fullfile(root, 'src', 'Support'), ...
                     fullfile(root, 'tests', 'fixtures')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
        end
    end

    methods (Test)
        function aDatasetWithNoCleaningHistoryHasNoRows(testCase)
        %ADATASETWITHNOCLEANINGHISTORYHASNOROWS  Nothing invented for a
        %   dataset that was never cleaned, and no error either.
            q = dataQualityMetrics(testCase.epochedFixture());

            testCase.verifyEmpty(q.provenance);
        end

        function detectorRowsCarryTheirOwnAndUniqueCounts(testCase)
            EEG = testCase.epochedFixture();
            EEG.etc.alz.artefactDetectors = testCase.detectorRecord();

            rows = dataQualityMetrics(EEG).provenance;

            abs_ = rows(strcmp({rows.item}, 'Absolute threshold'));
            testCase.assertNotEmpty(abs_);
            testCase.verifyEqual(abs_.step, 'ArtefactDetect');
            testCase.verifyEqual(abs_.n, 6);
            testCase.verifyEqual(abs_.n_total, 10);
            testCase.verifyEqual(abs_.n_unique, 1);
            testCase.verifyEqual(abs_.pct, 60, 'AbsTol', 1e-9);
        end

        function theAnyDetectorRowIsTheRealTotal(testCase)
        %THEANYDETECTORROWISTHEREALTOTAL  The per-detector figures overlap,
        %   so the total cannot be their sum and has to be carried
        %   separately, or a reader would conclude more trials were lost
        %   than actually were.
            EEG = testCase.epochedFixture();
            EEG.etc.alz.artefactDetectors = testCase.detectorRecord();

            rows = dataQualityMetrics(EEG).provenance;
            any_ = rows(strcmp({rows.item}, 'any detector'));
            perDetector = rows(~strcmp({rows.item}, 'any detector'));

            testCase.verifyEqual(any_.n, 7, 'The union, not the sum.');
            testCase.verifyGreaterThan(sum([perDetector.n]), any_.n, ...
                'The per-detector counts must overlap, which is the point of the caveat.');
            testCase.verifyTrue(isnan(any_.n_unique), ...
                '"Only this one" is meaningless for the union row.');
        end

        function oneDetectorGetsOneRowAndNoAttribution(testCase)
        %ONEDETECTORGETSONEROWANDNOATTRIBUTION  With a single detector its
        %   own count IS the total, so an "any detector" row would repeat it
        %   verbatim, and "how many did only this one catch" is trivially all
        %   of them. Two identical rows and a column restating the first is
        %   what the report actually showed; attribution belongs only where
        %   there is something to attribute.
            EEG = testCase.epochedFixture();
            EEG.etc.alz.artefactDetectors = testCase.oneDetectorRecord();

            rows = dataQualityMetrics(EEG).provenance;

            testCase.assertNumElements(rows, 1);
            testCase.verifyEqual(rows.item, 'Absolute threshold');
            testCase.verifyEqual(rows.n, 4);
            testCase.verifyTrue(isnan(rows.n_unique));
            testCase.verifyEqual(rows.scope, 'Whole epoch', ...
                'Every detector row carries the scope, so dropping the union row loses nothing.');
            testCase.verifyEqual(rows.channels_tested, 2);
        end

        function gedaiLeadsWithWhatItDidNotWithWhatItDidNot(testCase)
        %GEDAILEADSWITHWHATITDIDNOTWITHWHATITDIDNOT  GEDAI corrects in place
        %   and leaves nSamplesRejected at 0 on every path that drops no
        %   samples, which is the usual one. Leading with "0 of 46,600
        %   samples, 0.0%" put the one thing it did NOT do in the only
        %   columns a skimming reader takes in, and read as "this step
        %   changed nothing".
            EEG = testCase.epochedFixture();
            EEG.etc.GEDAI = struct('SENSAI_score', 57.636, ...
                'ENOVA_per_epoch', [0.1 0.95], 'ENOVA_per_channel', [0.2 0.4], ...
                'channelIndices', [1 2], 'nSamplesRejected', 0, ...
                'excludedChannels', {{'HEOG'}});

            rows = dataQualityMetrics(EEG).provenance;

            testCase.assertNumElements(rows, 1, 'One row for GEDAI, not two.');
            testCase.verifyEqual(rows.item, 'channels denoised');
            testCase.verifyEqual(rows.n, 2);
            testCase.verifyEqual(rows.n_total, 2);
            testCase.verifyEqual(rows.n_samples_rejected, 0, ...
                'The zero is still carried, as a column the report can drop when it is zero.');
            testCase.verifyEqual(rows.sensai, 57.636, 'AbsTol', 1e-9, ...
                'Unrounded: the report decides the precision it prints.');
        end

        function gedaiQualityScoresGetColumnsNotProse(testCase)
        %GEDAIQUALITYSCORESGETCOLUMNSNOTPROSE  SENSAI and ENOVA are the only
        %   part of a GEDAI row that says whether it helped, and they were
        %   unreadable packed into one semicolon-separated sentence: a
        %   heading can carry the direction ("higher better", "> 0.9 bad"),
        %   a blob cannot.
            EEG = testCase.epochedFixture();
            EEG.etc.GEDAI = struct('SENSAI_score', 40, ...
                'ENOVA_per_epoch', [0.1 0.3 0.9], 'ENOVA_per_channel', [0.2 0.6], ...
                'channelIndices', [1 2], 'nSamplesRejected', 120, ...
                'excludedChannels', {{'HEOG', 'VEOG'}});

            g = dataQualityMetrics(EEG).provenance;

            testCase.verifyEqual(g.sensai, 40);
            testCase.verifyEqual(g.enova_epoch_max, 0.9, 'AbsTol', 1e-12);
            testCase.verifyEqual(g.enova_epoch_median, 0.3, 'AbsTol', 1e-12);
            testCase.verifyEqual(g.enova_channel_max, 0.6, 'AbsTol', 1e-12);
            testCase.verifyEqual(g.n_excluded, 2, ...
                'The channels GEDAI could not match are why n is below n_total.');
            testCase.verifyEqual(g.n_samples_rejected, 120);
            testCase.verifyGreaterThan(g.n_samples, 0, ...
                'A rejected-sample count needs its denominator to mean anything.');
        end

        function automaticIcaReportsWhichComponentsWentAndWhy(testCase)
        %AUTOMATICICAREPORTSWHICHCOMPONENTSWENTANDWHY  AutoEyeICA's own
        %   options carry only the threshold, and pop_subcomp rewrites the
        %   classifications to describe the survivors, so the removed
        %   indices are recoverable only because the step records them.
            EEG = testCase.epochedFixture();
            EEG.etc.alz.eyeICA = struct('threshold', 0.6, 'removed', [1 12], ...
                'nRemoved', 2, 'nComponents', 28, 'eyeProbabilities', [0.88 0.74]);

            rows = dataQualityMetrics(EEG).provenance;
            ica = rows(strcmp({rows.step}, 'AutoICA'));

            testCase.assertNotEmpty(ica);
            testCase.verifyEqual(ica.n, 2);
            testCase.verifyEqual(ica.n_total, 28);
            testCase.verifyEqual(ica.threshold, 0.6, 'AbsTol', 1e-12, ...
                'The threshold is the parameter to adjust, so it gets its own column.');
            testCase.verifyEqual(ica.components, '1, 12', ...
                'And which components went, so the decision can be checked.');
            testCase.verifyTrue(contains(ica.detail, '0.88'), ...
                'How eye-like each was stays as a note; nothing tabulates it.');
        end

        function manualIcaIsReportedSeparatelyFromAutomatic(testCase)
        %MANUALICAISREPORTEDSEPARATELYFROMAUTOMATIC  They are different
        %   decisions -- a threshold against a person's judgement -- and a
        %   report that merged them would hide which was made.
            EEG = testCase.epochedFixture();
            EEG.etc.alz.manualICA = struct('removed', [3 7], 'nRemoved', 2, ...
                'nComponents', 20);

            rows = dataQualityMetrics(EEG).provenance;

            testCase.verifyEmpty(rows(strcmp({rows.step}, 'AutoICA')));
            manual = rows(strcmp({rows.step}, 'ICA'));
            testCase.assertNotEmpty(manual);
            testCase.verifyEqual(manual.n, 2);
            testCase.verifyEqual(manual.n_total, 20);
            testCase.verifyEqual(manual.item, 'by hand', ...
                'How the components were chosen is the difference worth showing.');
            testCase.verifyEqual(manual.components, '3, 7');
            testCase.verifyTrue(isnan(manual.threshold), ...
                'A hand-picked removal has no threshold, so the column is blank rather than 0.');
        end

        function gedaiReportsItsWorstEpochNotJustAnAverage(testCase)
        %GEDAIREPORTSITSWORSTEPOCHNOTJUSTANAVERAGE  ENOVA is per epoch, and
        %   a mean over epochs hides the single bad one that is the reason to
        %   look at all.
            EEG = testCase.epochedFixture();
            EEG.etc.GEDAI = struct('SENSAI_score', 83, ...
                'ENOVA_per_epoch', [0.1 0.2 0.95 0.15], ...
                'ENOVA_per_channel', [0.2 0.4], 'channelIndices', [1 2], ...
                'nSamplesRejected', 120, 'excludedChannels', {{'HEOG'}});

            rows = dataQualityMetrics(EEG).provenance;
            g = rows(strcmp({rows.item}, 'channels denoised'));

            testCase.assertNotEmpty(g);
            testCase.verifyEqual(g.enova_epoch_max, 0.95, 'AbsTol', 1e-12, ...
                'The worst epoch has to appear, not only the median.');
            testCase.verifyEqual(g.enova_epoch_median, 0.175, 'AbsTol', 1e-12, ...
                'And the median beside it, or one bad epoch looks like the whole recording.');
        end

        function severalStepsInOneChainAllAppear(testCase)
        %SEVERALSTEPSINONECHAINALLAPPEAR  Correction upstream and rejection
        %   downstream is the ordinary case (chapter 9's recipe), and the
        %   report has to show both: EEG.etc travels down the chain, so the
        %   epoched node carries the lot.
            EEG = testCase.epochedFixture();
            EEG.etc.alz.artefactDetectors = testCase.detectorRecord();
            EEG.etc.alz.eyeICA = struct('threshold', 0.6, 'removed', 1, ...
                'nRemoved', 1, 'nComponents', 28, 'eyeProbabilities', 0.9);

            rows = dataQualityMetrics(EEG).provenance;

            testCase.verifyNotEmpty(rows(strcmp({rows.step}, 'ArtefactDetect')));
            testCase.verifyNotEmpty(rows(strcmp({rows.step}, 'AutoICA')));
        end

        function aMalformedRecordCostsItsSectionNotTheReport(testCase)
        %AMALFORMEDRECORDCOSTSITSSECTIONNOTTHEREPORT  etc is EEGLAB's
        %   free-form field and anything may be in it, including an older
        %   release's half-shaped record. A report is worse than useless if
        %   it invents numbers out of one it cannot read.
            junk = {42, 'not a struct', struct('unexpected', 1), ...
                struct('methods', {{'Absolute threshold'}}, 'epochs', 3)};
            for k = 1:numel(junk)
                EEG = testCase.epochedFixture();
                EEG.etc.alz.artefactDetectors = junk{k};

                q = dataQualityMetrics(EEG);

                testCase.verifyEmpty(q.provenance, ...
                    sprintf('Record %d should have been skipped, not read.', k));
            end
        end

        function theCsvCarriesEveryRowAndItsOwnHeader(testCase)
            EEG = testCase.epochedFixture();
            EEG.etc.alz.artefactDetectors = testCase.detectorRecord();
            q = dataQualityMetrics(EEG);
            entries = struct('subject', 'S1', 'group', 'g', 'session', '1', 'quality', q);

            [stem, provCsv] = testCase.exportTo(entries);

            testCase.assertTrue(isfile(provCsv), ...
                sprintf('Expected a provenance CSV beside %s.', stem));
            lines = splitlines(strtrim(fileread(provCsv)));
            testCase.verifyEqual(lines{1}, ...
                ['dataset,group,session,step,item,n,n_total,pct,n_unique,' ...
                 'channel_epochs,channels_tested,scope,threshold,components,' ...
                 'n_samples_rejected,n_samples,sensai,enova_epoch_max,' ...
                 'enova_epoch_median,enova_channel_max,n_excluded,detail']);
            testCase.verifyEqual(numel(lines) - 1, numel(q.provenance));
            testCase.verifyTrue(contains(lines{2}, 'S1'));
        end

        function theUnionRowsEmptyUniqueCellReadsBackAsMissing(testCase)
        %THEUNIONROWSEMPTYUNIQUECELLREADSBACKASMISSING  NaN is written as an
        %   empty field, not the text "NaN", or readr types the whole column
        %   as character and the chart's arithmetic fails.
            EEG = testCase.epochedFixture();
            EEG.etc.alz.artefactDetectors = testCase.detectorRecord();
            entries = struct('subject', 'S1', 'group', '', 'session', '', ...
                'quality', dataQualityMetrics(EEG));

            [~, provCsv] = testCase.exportTo(entries);

            lines = splitlines(strtrim(fileread(provCsv)));
            union_ = lines(contains(lines, 'any detector'));
            testCase.assertNotEmpty(union_);
            testCase.verifyFalse(contains(union_{1}, 'NaN'));
            fields = split(union_{1}, ',');
            testCase.verifyEmpty(fields{9}, 'n_unique is the ninth column.');
        end

        function theCsvIsWrittenEvenWithNothingToReport(testCase)
        %THECSVISWRITTENEVENWITHNOTHINGTOREPORT  Header-only rather than
        %   absent, so the report's read_csv never has to be conditional --
        %   the same choice writeSmeCsv makes.
            entries = struct('subject', 'S1', 'group', '', 'session', '', ...
                'quality', dataQualityMetrics(testCase.epochedFixture()));

            [~, provCsv] = testCase.exportTo(entries);

            testCase.assertTrue(isfile(provCsv));
            lines = splitlines(strtrim(fileread(provCsv)));
            testCase.verifyEqual(numel(lines), 1, 'Header only.');
        end

        function theSectionAppearsWhenThereIsAFile(testCase)
            testCase.verifyTrue(contains(testCase.report('p.csv'), ...
                'What the Cleaning Steps Did'));
        end

        function theChartUsesTheColumnRatherThanParsingTheProse(testCase)
        %THECHARTUSESTHECOLUMNRATHERTHANPARSINGTHEPROSE  n_unique exists as
        %   its own column precisely so the figure does not have to regex it
        %   out of a sentence written for a human; a reworded sentence would
        %   turn the red bars silently into NA.
            qmd = testCase.report('p.csv');

            testCase.verifyTrue(contains(qmd, '100 * n_unique / n_total'));
            testCase.verifyFalse(contains(qmd, 'str_match(detail'), ...
                'Parsing the detail prose back out is what the column replaced.');
        end

        function oneTablePerStepEachWithItsOwnHeadings(testCase)
        %ONETABLEPERSTEPEACHWITHITSOWNHEADINGS  One combined table could
        %   only label its count column "n", which counted epochs on one
        %   row, components on the next and channels on the third: unreadable
        %   without a legend, and a legend is a second copy of the truth that
        %   rots. Three tables can each name their own unit in the heading.
            qmd = testCase.report('p.csv');

            for label = {'provenance-rejection-table', 'provenance-ica-table', ...
                         'provenance-gedai-table'}
                testCase.verifyTrue(contains(qmd, label{1}), sprintf( ...
                    'Expected a separate %s chunk.', label{1}));
            end
            for heading = {'`Epochs rejected` = n', '`of epochs` = n_total', ...
                           'Removed = n', '`of components` = n_total', ...
                           '`Channels denoised` = n', '`of channels` = n_total'}
                testCase.verifyTrue(contains(qmd, heading{1}), sprintf( ...
                    'A heading must name its own unit: missing %s.', heading{1}));
            end
            testCase.verifyFalse(contains(qmd, 'never down the column'), ...
                'The legend existed only because one table could not describe itself.');
        end

        function anInapplicableCellRendersEmptyRatherThanAsTheLettersNA(testCase)
        %ANINAPPLICABLECELLRENDERSEMPTYRATHERTHANASTHELETTERSNA  These
        %   tables have columns that apply to some rows and not others (the
        %   union row has no "only this one"), and gt prints an NA as the
        %   text "NA", which reads as a measurement that went missing rather
        %   than as a column that does not apply. Opted in per table, since
        %   elsewhere in the report an NA really is a failed measurement.
            qmd = testCase.report('p.csv');

            testCase.verifyTrue(contains(qmd, 'blank_missing <- function'), ...
                'The helper has to be defined in the setup chunk to be callable.');
            for title = {'Epochs Rejected, by Detector', 'ICA Components Removed', ...
                         'AutoGEDAI Denoising and Its Quality Scores'}
                testCase.verifyTrue( ...
                    contains(qmd, ['blank_missing(apa_gt(tab, "' title{1} '"))']), ...
                    sprintf('The "%s" table should blank its inapplicable cells.', title{1}));
            end
        end

        function theGedaiHeadingsCarryTheDirectionOfEachScore(testCase)
        %THEGEDAIHEADINGSCARRYTHEDIRECTIONOFEACHSCORE  "SENSAI 69.0" is not
        %   actionable on its own: nothing on the page said whether high was
        %   good, and ENOVA runs the other way from SENSAI. The heading is
        %   the only place a reader is certain to look.
            qmd = testCase.report('p.csv');

            testCase.verifyTrue(contains(qmd, 'SENSAI (higher better)'));
            testCase.verifyTrue(contains(qmd, 'ENOVA (>0.9 bad)'));
            testCase.verifyTrue(contains(qmd, 'higher is worse'), ...
                'ENOVA''s direction is the opposite of SENSAI''s, so it is stated too.');
        end

        function sensaiIsExplainedAsBoundedNotOpenEnded(testCase)
        %SENSAIISEXPLAINEDASBOUNDEDNOTOPENENDED  A shipped draft of this
        %   section once claimed SENSAI had "no fixed upper bound". It does:
        %   signal- and noise-subspace similarity are each a mean
        %   cosine-angle product in [0, 1] scaled to 0-100
        %   (GEDAI-master 1.7's auxiliaries/SENSAI_basic.m), and the weight
        %   GEDAI.m gives the noise term for the score AutoGEDAI reads is 1
        %   -- so the range is exactly -100 to 100, checked against that
        %   source directly rather than trusted from an earlier draft.
            qmd = testCase.report('p.csv');

            testCase.verifyTrue(contains(qmd, '-100 to 100'), ...
                'SENSAI''s true range should be stated, not left implied.');
            testCase.verifyFalse(contains(qmd, 'no fixed upper bound'), ...
                'That claim is the one this test exists to keep out: it is false.');
        end

        function enovaIsExplainedNotJustBounded(testCase)
        %ENOVAISEXPLAINEDNOTJUSTBOUNDED  "0 to 1, higher worse" says the
        %   scale without saying what is being scaled; ENOVA is a named,
        %   concrete quantity (Explained Noise Variance, a variance ratio),
        %   not an arbitrary index, and a reader should not have to ask.
            qmd = testCase.report('p.csv');

            testCase.verifyTrue(contains(qmd, 'Explained Noise Variance'));
            testCase.verifyTrue(contains(qmd, 'variance of what GEDAI classified as noise'), ...
                'The variance-ratio definition itself should be stated, not only its range.');
        end

        function gedaiExplainsWhatCountsAsAnArtifactAndWhy(testCase)
        %GEDAIEXPLAINSWHATCOUNTSASANARTIFACTANDWHY  Checked against the
        %   method paper itself (Ros et al., 2025, bioRxiv preprint
        %   2025.10.04.680449, Docs/2025.10.04.680449v1.full.pdf): "those
        %   components with a spatial covariance inconsistent with the brain
        %   model are identified as artifacts (large eigenvalues), while
        %   consistent components are treated as neural signals". That is
        %   the actual mechanism, and the whole reason GEDAI is not just
        %   another variance threshold -- a big, brain-like event survives
        %   where a plain-amplitude method (ASR) cannot tell it apart from
        %   an eyeblink of the same size. The old text never said any of
        %   this; it only described the input/output shape (denoises in
        %   place, matches by label) and left "what makes something noise"
        %   unstated.
            qmd = testCase.report('p.csv');

            testCase.verifyTrue(contains(qmd, 'leadfield'), ...
                'The theoretical reference GEDAI compares against should be named.');
            testCase.verifyTrue(contains(qmd, '40-brain average head'), ...
                'Where the reference comes from (not this recording) is the point.');
            testCase.verifyTrue(contains(qmd, 'not simply because it is large'), ...
                'The deviation-from-a-brain-model criterion is what distinguishes this from a variance threshold.');
        end

        function gedaiExplainsItHasNoSeparateBadChannelStep(testCase)
        %GEDAIEXPLAINSITHASNOSEPARATEBADCHANNELSTEP  The paper: "GEDAI
        %   offers a novel alternative by avoiding this binary rejection. It
        %   instead treats activity from compromised channels as artifactual
        %   components... removed if their spatial characteristics deviate
        %   from the theoretical brain signal model." A reader looking for
        %   which channels were "rejected" needs to know there is no such
        %   list -- a chronically bad channel shows up as a high ENOVA
        %   instead, which is the connection this section now states rather
        %   than leaving the two facts to be pieced together separately.
            qmd = testCase.report('p.csv');

            testCase.verifyTrue(contains(qmd, 'no separate bad-channel step'), ...
                'GEDAI folds a bad channel into the same per-epoch correction; it does not flag it.');
            testCase.verifyTrue(contains(qmd, 'high ENOVA across most epochs'), ...
                'The two facts (no channel flag, but a persistent ENOVA signature) should be connected explicitly.');
        end

        function gedaiNamesElectrodePositionAccuracyAsItsOwnStatedLimitation(testCase)
        %GEDAINAMESELECTRODEPOSITIONACCURACYASITSOWNSTATEDLIMITATION  The
        %   paper is direct about this: "GEDAI's performance is highly
        %   dependent on an accurate match between the theoretical leadfield
        %   model and the actual EEG electrode positions. Any spatial
        %   mismatch will proportionally degrade its efficacy." Without this,
        %   a low SENSAI reads as "the recording was noisy" when it might
        %   instead mean "the electrode positions given to GEDAI were only
        %   approximate" -- a materially different thing to go fix.
            qmd = testCase.report('p.csv');

            testCase.verifyTrue(contains(qmd, 'electrode-position accuracy'), ...
                'The paper''s own named main limitation should appear, not just the denoising mechanism.');
            testCase.verifyTrue(contains(qmd, 'not only genuine contamination'), ...
                'A low score having two different possible causes is the actionable part.');
        end

        function theIcaSectionExplainsWhatTheProbabilityThresholdActuallyTests(testCase)
        %THEICASECTIONEXPLAINSWHATTHEPROBABILITYTHRESHOLDACTUALLYTESTS  The
        %   threshold is on the Eye class alone, not on whether Eye is a
        %   component's most likely class overall -- a real distinction a
        %   reader cannot get right by guessing, and the section previously
        %   said nothing about it at all.
            qmd = testCase.report('p.csv');

            testCase.verifyTrue(contains(qmd, 'seven classes'), ...
                'ICLabel''s classes should be named, not left as an unexplained number.');
            testCase.verifyTrue(contains(qmd, 'not the same test as Eye being the single most likely class'), ...
                'The threshold-vs-plurality distinction is the part easiest to misread.');
        end

        function everyColumnTheTablesUseIsDeclaredInTheFallbackFrame(testCase)
        %EVERYCOLUMNTHETABLESUSEISDECLAREDINTHEFALLBACKFRAME  With three
        %   tables over many more columns, the empty stand-in tibble is easy
        %   to leave a column out of, and the omission only shows on the
        %   workspace the fallback exists to protect. So it is checked
        %   against the columns the exporter actually writes.
            EEG = testCase.epochedFixture();
            EEG.etc.alz.artefactDetectors = testCase.detectorRecord();
            entries = struct('subject', 'S1', 'group', '', 'session', '', ...
                'quality', dataQualityMetrics(EEG));
            [~, provCsv] = testCase.exportTo(entries);
            lines = splitlines(strtrim(fileread(provCsv)));
            header = split(lines{1}, ',');

            frame = testCase.lineStartingWith(testCase.report('p.csv'), 'prov <- ');

            for k = 1:numel(header)
                testCase.verifyTrue(contains(frame, [header{k} ' = ']), sprintf( ...
                    ['The stand-in frame does not declare "%s", which the exporter ' ...
                     'writes and the tables read.'], header{k}));
            end
        end

        function theSectionIsOmittedWhenThereIsNoFile(testCase)
        %THESECTIONISOMITTEDWHENTHEREISNOFILE  An older export has no
        %   provenance CSV, and the report should lose this section rather
        %   than fail to render.
            qmd = testCase.report('');

            testCase.verifyFalse(contains(qmd, 'What the Cleaning Steps Did'));
        end

        function theGedaiPaperIsCitedInTheReferencesSection(testCase)
        %THEGEDAIPAPERISCITEDINTHEREFERENCESSECTION  The report explains
        %   GEDAI/SENSAI/ENOVA at length now (see the provenance-gedai-table
        %   chunk), sourced from Ros et al., 2025 -- a claim that has to
        %   trace to a citation a reader can actually go verify, the same
        %   way the SME section already cites Luck et al., 2021. Present
        %   regardless of whether this particular export used GEDAI, since
        %   References is one fixed section, not conditioned on the data.
            qmd = testCase.report('p.csv');

            testCase.verifyTrue(contains(qmd, '## References'));
            testCase.verifyTrue(contains(qmd, 'Ros, T.'), ...
                'The GEDAI paper should be cited, not only named in passing.');
            testCase.verifyTrue(contains(qmd, '10.1101/2025.10.04.680449'), ...
                'A DOI, not just an author/year, is what lets a reader actually find it.');
        end
    end

    methods (Access = private)
        function EEG = epochedFixture(~)
            EEG = makeTestEEG('nbchan', 2, 'trials', 10, 'labels', {'Fz', 'Cz'});
            EEG.etc = struct();
        end

        function [stem, provCsv] = exportTo(testCase, entries)
            stem = tempname();
            [~, ~, ~, provCsv] = exportDataQualityCSVs(entries, stem);
            testCase.addTeardown(@() delete([stem '*.csv']));
        end

        function qmd = report(testCase, provenanceCsvName)
            entries = struct('subject', 'S1', 'group', '', 'session', '', ...
                'quality', dataQualityMetrics(testCase.epochedFixture()));
            qmd = generateDataQualityReport(entries, 'q.csv', 't.csv', 's.csv', '', ...
                provenanceCsvName);
        end

        function line = lineStartingWith(testCase, text, prefix)
            lines = splitlines(text);
            hit = lines(startsWith(strtrim(lines), prefix));
            testCase.assertNotEmpty(hit, sprintf('No line starting "%s".', prefix));
            line = hit{1};
        end

        function d = oneDetectorRecord(testCase)
        %ONEDETECTORRECORD  The commonest real case, and the one the report
        %   handled worst: a single ticked detector over 10 trials.
            d = testCase.detectorRecord();
            mask = d.epochMask(:, 1);
            d.methods       = {'Absolute threshold'};
            d.epochs        = 4;
            d.channelEpochs = 5;
            d.onlyThis      = 4;
            d.epochMask     = mask(:);
            d.totalEpochs   = 4;
        end

        function d = detectorRecord(~)
        %DETECTORRECORD  Two detectors over 10 trials that overlap on five,
        %   so the union (7) is smaller than the sum (12) and each catches
        %   exactly one epoch the other misses.
            epochMask = false(10, 2);
            epochMask(1:6, 1) = true;     % absolute threshold: 1..6
            epochMask(2:7, 2) = true;     % peak-to-peak: 2..7
            d = struct( ...
                'methods', {{'Absolute threshold', 'Moving-window peak-to-peak'}}, ...
                'epochs', [6 6], ...
                'channelEpochs', [8 9], ...
                'onlyThis', [1 1], ...
                'epochMask', epochMask, ...
                'totalEpochs', 7, ...
                'nTrials', 10, ...
                'channelsTested', 2, ...
                'scope', 'Whole epoch');
        end
    end
end
