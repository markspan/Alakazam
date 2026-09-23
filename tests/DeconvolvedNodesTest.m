classdef DeconvolvedNodesTest < matlab.unittest.TestCase
%DECONVOLVEDNODESTEST  A deconvolved dataset is a subject's average, and the
%   rest of the application has to treat it as one.
%
%   Deconvolve produces one waveform per bin in Average's own shape, so
%   Measure, ScalpDistribution and the views read it unchanged. Four places
%   decided separately whether a node counts as "an average of this subject":
%   the grand-average candidate list, the design collector behind the group
%   reports, the drop-to-overlay rule, and the data-quality report. Each had
%   its own copy of the test, each keyed on the name 'Average', so a
%   deconvolved node was missing from all four at once. They now share
%   producesSubjectAverage, which is what these tests pin.
%
%   THE DATA-QUALITY HALF IS NOT THE SAME QUESTION. Letting a deconvolved
%   node into that report is easy; the care is in what the report then says
%   about it, because the measures it is built on (rejection rates, per-trial
%   noise, SME) are all measures over trials, and a deconvolution has none:
%   it fits one waveform per bin against the continuous recording, so there
%   is no trial-to-trial distribution to describe. Those fields must be NaN,
%   which reads as "not measured", and never 0, which would read as a subject
%   who lost nothing.
%
%   Run with: runtests('tests/DeconvolvedNodesTest.m').
%
%   See also PRODUCESSUBJECTAVERAGE, DECONVOLUTIONQUALITY, DECONVOLVE.

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            for p = {fullfile(root, 'src'), fullfile(root, 'src', 'Support'), ...
                     fullfile(root, 'src', 'Reports'), fullfile(root, 'tests', 'fixtures')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
        end
    end

    methods (Test)
        function averagingTransformationsCount(testCase)
            testCase.verifyTrue(producesSubjectAverage('Average'));
            testCase.verifyTrue(producesSubjectAverage('Deconvolve'));
            testCase.verifyTrue(producesSubjectAverage('deconvolve'), 'Case does not decide it.');
            testCase.verifyTrue(producesSubjectAverage("Average"), 'A string is a call too.');
        end

        function downstreamStepsDoNot(testCase)
        %DOWNSTREAMSTEPSDONOT  The distinction the rule exists for: these take
        %   an averaged dataset and hand it on unchanged, so counting them
        %   would give every subject several duplicate averages.
            testCase.verifyFalse(producesSubjectAverage('Measure'));
            testCase.verifyFalse(producesSubjectAverage('ScalpDistribution'));
            testCase.verifyFalse(producesSubjectAverage('Brain3D'));
        end

        function anAbsentCallIsAGrandAverageOrALoadedErp(testCase)
            testCase.verifyTrue(producesSubjectAverage(''));
            testCase.verifyTrue(producesSubjectAverage([]));
            testCase.verifyTrue(producesSubjectAverage());
        end

        function qualityReportsEventsPerBinNotTrials(testCase)
            EEG = DeconvolvedNodesTest.fittedDataset();

            q = deconvolutionQuality(EEG);

            testCase.verifyEqual(q.subject.n_bins, 2);
            testCase.verifyEqual(q.subject.n_channels, 2);
            testCase.verifyEqual(q.subject.n_trials, 120, ...
                'The events behind the bins are what stands in for trials.');
            counts = [q.byBinChannel.n_trials];
            testCase.verifyEqual(unique(counts(strcmp({q.byBinChannel.bin}, 'Rare'))), 30);
        end

        function whatCannotBeMeasuredIsNaNAndNotZero(testCase)
        %WHATCANNOTBEMEASUREDISNANANDNOTZERO  The point of the whole exercise:
        %   a deconvolved subject printed at 0% rejected beside an averaged
        %   subject at 14% would read as the better recording, when in fact
        %   nothing was measured.
            q = deconvolutionQuality(DeconvolvedNodesTest.fittedDataset());

            testCase.verifyTrue(isnan(q.subject.pct_trials_rejected));
            testCase.verifyTrue(isnan(q.subject.n_trials_rejected));
            testCase.verifyTrue(isnan(q.subject.median_baseline_sd_uv));
            testCase.verifyTrue(all(isnan([q.byBinChannel.sme_uv])), ...
                'A regression coefficient has no trials to spread.');
            testCase.verifyEmpty(q.byTrial);
            testCase.verifyEmpty(q.byWindowChannel);
        end

        function theProvenanceCarriesWhatWasExcluded(testCase)
        %THEPROVENANCECARRIESWHATWASEXCLUDED  The honest analogue of a
        %   rejection rate: how much of the recording was left out of the
        %   model, and at what threshold.
            q = deconvolutionQuality(DeconvolvedNodesTest.fittedDataset());

            rows = q.provenance;
            testCase.verifyNotEmpty(rows);
            first = rows(1);
            testCase.verifyEqual(first.step, 'Deconvolve');
            testCase.verifyEqual(first.n, 20);
            testCase.verifyEqual(first.n_total, 200);
            testCase.verifyEqual(first.pct, 10, 'AbsTol', 1e-9);
            testCase.verifyEqual(first.threshold, 150);
            testCase.verifySubstring(first.detail, 'response window -200 to 800 ms');
            testCase.verifySubstring(first.detail, 'baseline -200 to 0 ms');
            testCase.verifyTrue(any(contains({rows.detail}, 'ran out of iterations')), ...
                'A model note reaches the report as its own row.');
        end

        function theQualityStructMatchesTheAveragedOne(testCase)
        %THEQUALITYSTRUCTMATCHESTHEAVERAGEDONE  Every subject's struct is
        %   concatenated into one table by the CSV export, so a differently
        %   shaped one would not concatenate. Checked against the fields
        %   dataQualityMetrics itself produces.
            q = deconvolutionQuality(DeconvolvedNodesTest.fittedDataset());
            reference = dataQualityMetrics(makeTestEEG('trials', 8), [], {}, true);

            testCase.verifyEqual(sort(fieldnames(q)), sort(fieldnames(reference)));
            testCase.verifyEqual(sort(fieldnames(q.subject)), sort(fieldnames(reference.subject)));
            testCase.verifyEqual(sort(fieldnames(q.byBinChannel)), ...
                sort(fieldnames(reference.byBinChannel)));
            testCase.verifyEqual(sort(fieldnames(q.provenance)), ...
                sort(fieldnames(reference.provenance)));
        end

        function itExportsBesideAnAveragedSubject(testCase)
        %ITEXPORTSBESIDEANAVERAGEDSUBJECT  The real risk in adding a second
        %   kind of subject to this report: the export concatenates every
        %   subject's struct into one table per CSV, and a deconvolved
        %   subject contributes empty trial and window tables. Checked
        %   through the real exporter and the real generator, because that
        %   is where a shape mismatch or an empty table would surface.
            folder = testCase.applyFixture( ...
                matlab.unittest.fixtures.TemporaryFolderFixture()).Folder;
            averaged = struct('subject', 's01', 'group', '', 'session', '', ...
                'quality', dataQualityMetrics(DeconvolvedNodesTest.epochedDataset()));
            fitted = struct('subject', 's02', 'group', '', 'session', '', ...
                'quality', deconvolutionQuality(DeconvolvedNodesTest.fittedDataset()));

            [summaryCsv, trialCsv, smeCsv, provenanceCsv] = ...
                exportDataQualityCSVs([averaged fitted], fullfile(folder, 'dq'));

            summary = readtable(summaryCsv, 'TextType', 'string');
            testCase.verifyEqual(sort(unique(summary.dataset))', ["s01", "s02"], ...
                'Both subjects reached the summary table.');
            deconvolved = summary(summary.dataset == "s02", :);
            testCase.verifyTrue(all(ismissing(deconvolved.pct_trials_rejected)), ...
                'Its unmeasurable columns are empty fields, which readr reads as NA.');

            trials = readtable(trialCsv, 'TextType', 'string');
            testCase.verifyFalse(any(trials.dataset == "s02"), ...
                'It contributes no trial rows, having no trials.');

            provenance = readtable(provenanceCsv, 'TextType', 'string');
            testCase.verifyTrue(any(provenance.dataset == "s02" & provenance.step == "Deconvolve"), ...
                'What it excluded from the model is in the provenance table.');

            [~, s] = fileparts(summaryCsv);
            [~, t] = fileparts(trialCsv);
            [~, m] = fileparts(smeCsv);
            qmd = generateDataQualityReport([averaged fitted], [s '.csv'], [t '.csv'], ...
                [m '.csv'], 'N400');

            testCase.verifyNotEmpty(qmd, 'The generator produced a document for the pair.');
        end
    end

    methods (Static)
        function EEG = epochedDataset()
        %EPOCHEDDATASET  An ordinary averaged subject's epoched data, two
        %   bins and one rejected trial, to sit beside the fitted one.
            EEG = makeTestEEG('trials', 8, 'nbchan', 2);
            EEG.bindesc = struct('label', {'Frequent', 'Rare'}, 'index', {1, 2}, ...
                'trials', {1:4, 5:8});
            EEG.data(:, :, 1) = NaN;
        end

        function EEG = fittedDataset()
        %FITTEDDATASET  What Deconvolve leaves behind, without running it:
        %   Average's shape plus the provenance Unfold.fitBins records.
            EEG = struct('data', zeros(2, 100, 2), 'srate', 100, 'pnts', 100, ...
                'trials', 1, 'nbchan', 2, 'times', linspace(-200, 800, 100), ...
                'DataFormat', 'Averaged', 'Call', 'Deconvolve', ...
                'chanlocs', struct('labels', {'Cz', 'Pz'}), ...
                'bindesc', struct('index', {1, 2}, 'label', {'Frequent', 'Rare'}, ...
                                  'combo', {[], []}, 'n', {90, 30}));
            EEG.etc.alz.unfold = struct('window', [-200 800], 'baseline', [-200 0], ...
                'binLabels', {{'Frequent', 'Rare'}}, 'binCounts', [90 30], ...
                'nuisanceTypes', {{'evt_response'}}, ...
                'notes', {{'The solver ran out of iterations before it converged, for at least one channel.'}}, ...
                'excludedSeconds', 20, 'recordingSeconds', 200, ...
                'artifact', struct('thresholdUv', 150, 'windowMs', 2000, 'stepMs', 100), ...
                'hasStandardError', false);
        end
    end
end
