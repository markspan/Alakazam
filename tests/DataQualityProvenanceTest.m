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
            testCase.verifyTrue(contains(rows.detail, 'Whole epoch'), ...
                'The scope came off the dropped union row, so it must land here.');
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

            testCase.assertNumElements(rows, 1, 'No zero-rejection row.');
            testCase.verifyEqual(rows.item, 'channels denoised');
            testCase.verifyEqual(rows.n, 2);
            testCase.verifyEqual(rows.n_total, 2);
            testCase.verifyTrue(contains(rows.detail, 'no samples rejected'), ...
                'The zero is still reported, in words, where it cannot be mistaken for inaction.');
            testCase.verifyTrue(contains(rows.detail, 'SENSAI 57.6'), ...
                'One decimal: three on a two-digit score claims precision it lacks.');
        end

        function gedaiAddsARowOnlyWhenItActuallyRejectedSamples(testCase)
            EEG = testCase.epochedFixture();
            EEG.etc.GEDAI = struct('SENSAI_score', 40, 'ENOVA_per_epoch', 0.5, ...
                'ENOVA_per_channel', 0.5, 'channelIndices', [1 2], ...
                'nSamplesRejected', 120, 'excludedChannels', {{}});

            rows = dataQualityMetrics(EEG).provenance;
            rejected = rows(strcmp({rows.item}, 'samples rejected'));

            testCase.assertNotEmpty(rejected);
            testCase.verifyEqual(rejected.n, 120);
            testCase.verifyTrue(contains(rejected.detail, 'NaN'), ...
                'They are NaN''d across all channels, not dropped, which changes what the count means.');
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
            testCase.verifyTrue(contains(ica.detail, '0.60'), ...
                'The threshold is the parameter to adjust, so it has to be shown.');
            testCase.verifyTrue(contains(ica.detail, '1, 12'), ...
                'And which components went, so the decision can be checked.');
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
            testCase.verifyTrue(contains(manual.detail, 'by hand'));
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
            testCase.verifyTrue(contains(g.detail, '0.950'), ...
                'The worst epoch has to appear, not only the median.');
            testCase.verifyTrue(contains(g.detail, 'median 0.175'), ...
                'And the median beside it, or one bad epoch looks like the whole recording.');
            testCase.verifyTrue(contains(g.detail, 'SENSAI'));
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
                'dataset,group,session,step,item,n,n_total,pct,n_unique,detail');
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

        function theReportsStandInFrameDeclaresEveryColumnItUses(testCase)
        %THEREPORTSSTANDINFRAMEDECLARESEVERYCOLUMNITUSES  When the CSV is
        %   missing the section falls back to an empty tibble, and that
        %   tibble has to name every column the chunks then reference, or
        %   the fallback errors where it was meant to degrade quietly.
            qmd = testCase.report('p.csv');

            testCase.verifyTrue(contains(qmd, 'What the Cleaning Steps Did'));
            frame = testCase.lineStartingWith(qmd, 'prov <- ');
            for col = {'step', 'item', 'n', 'n_total', 'pct', 'n_unique', 'detail'}
                testCase.verifyTrue(contains(frame, [col{1} ' = ']), sprintf( ...
                    'The stand-in frame must declare %s, which the chunks use.', col{1}));
            end
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

        function theSectionIsOmittedWhenThereIsNoFile(testCase)
        %THESECTIONISOMITTEDWHENTHEREISNOFILE  An older export has no
        %   provenance CSV, and the report should lose this section rather
        %   than fail to render.
            qmd = testCase.report('');

            testCase.verifyFalse(contains(qmd, 'What the Cleaning Steps Did'));
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
