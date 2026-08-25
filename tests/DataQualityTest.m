classdef DataQualityTest < matlab.unittest.TestCase
%DATAQUALITYTEST  Unit tests for src/IO/dataQualityMetrics.m,
%   src/IO/exportDataQualityCSVs.m and src/IO/generateDataQualityReport.m.
%
%   dataQualityMetrics is the part worth testing hardest: it is a pure
%   function over an epoched EEG struct, and every number the report
%   narrates comes from it. The report generator itself is only checked
%   for the things a template can actually get wrong on its own (it
%   references the CSV names it was handed, it emits a group section only
%   when there are groups, it refuses an empty export) -- not for the R
%   inside it, which needs Quarto and R to say anything about.
%
%   The tree walk (Alakazam.collectDataQualityEntries) is not tested here:
%   it needs a live Alakazam instance and a populated cache tree, the same
%   reason collectEntriesWithField has no unit test either.
%
%   Run with: runtests('tests/DataQualityTest.m').
%
%   See also MAKETESTEEG, DATAQUALITYMETRICS.

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'IO')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'Support')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'tests', 'fixtures')));
        end
    end

    methods (Test)
        % ---- guards ----------------------------------------------------
        function rejectsContinuousData(testCase)
            EEG = makeTestEEG('DataFormat', 'CONTINUOUS');
            testCase.verifyError(@() dataQualityMetrics(EEG), 'Alakazam:dataQualityMetrics');
        end

        function rejectsEmptyData(testCase)
            testCase.verifyError(@() dataQualityMetrics(struct('data', [])), ...
                'Alakazam:dataQualityMetrics');
        end

        % ---- rejection accounting --------------------------------------
        function cleanDataHasNoRejections(testCase)
            q = dataQualityMetrics(makeTestEEG('trials', 8));

            testCase.verifyEqual(q.subject.n_trials, 8);
            testCase.verifyEqual(q.subject.n_trials_rejected, 0);
            testCase.verifyEqual(q.subject.pct_trials_rejected, 0);
            testCase.verifyEqual(q.subject.n_channel_epochs_flagged, 0);
        end

        function wholeEpochRejectionCountsAsARejectedTrial(testCase)
        %WHOLEEPOCHREJECTIONCOUNTSASAREJECTEDTRIAL  ArtefactDetect's
        %   "Whole epoch" scope NaNs every channel of a trial; that must
        %   count once as a rejected TRIAL, not nbchan times as flagged
        %   channels (the two are told apart only by how many channels of
        %   the trial are gone -- see dataQualityMetrics' own comment).
            EEG = makeTestEEG('trials', 4, 'nbchan', 3);
            EEG.data(:, :, 2) = NaN;

            q = dataQualityMetrics(EEG);

            testCase.verifyEqual(q.subject.n_trials_rejected, 1);
            testCase.verifyEqual(q.subject.pct_trials_rejected, 25);
            testCase.verifyEqual(q.subject.n_channel_epochs_flagged, 0);
        end

        function channelScopedRejectionCountsAsAFlaggedChannelEpoch(testCase)
            EEG = makeTestEEG('trials', 4, 'nbchan', 3);
            EEG.data(2, :, 3) = NaN;   % one channel, one trial

            q = dataQualityMetrics(EEG);

            testCase.verifyEqual(q.subject.n_trials_rejected, 0);
            testCase.verifyEqual(q.subject.n_channel_epochs_flagged, 1);
            testCase.verifyEqual(q.subject.pct_channel_epochs_flagged, 100 / 12);
        end

        function aFullyRejectedTrialIsNotAlsoCountedAsFlaggedChannels(testCase)
        %AFULLYREJECTEDTRIALISNOTALSOCOUNTEDASFLAGGEDCHANNELS  The two
        %   counts must not double-count the same lost data: a trial whose
        %   channels are ALL gone is one rejection, and contributes nothing
        %   to the flagged-channel count.
            EEG = makeTestEEG('trials', 4, 'nbchan', 3);
            EEG.data(:, :, 1) = NaN;   % whole trial
            EEG.data(2, :, 2) = NaN;   % one channel elsewhere

            q = dataQualityMetrics(EEG);

            testCase.verifyEqual(q.subject.n_trials_rejected, 1);
            testCase.verifyEqual(q.subject.n_channel_epochs_flagged, 1);
        end

        % ---- truncation vs rejection -----------------------------------
        function aBoundaryTruncatedTrialIsCountedAsTruncatedNotRejected(testCase)
        %ABOUNDARYTRUNCATEDTRIALISCOUNTEDASTRUNCATEDNOTREJECTED  DefineBins
        %   allocates the epoch stack as NaN and fills only the part of each
        %   epoch that overlaps the recording, so an event near the end of a
        %   file leaves a partly-empty trial (confirmed against cutEpochs).
        %   That trial still enters the average, so it must be VISIBLE, and
        %   it must not be reported as an artefact rejection, which would
        %   name a cause that never happened.
            EEG = makeTestEEG('trials', 4, 'nbchan', 3);
            EEG.data(:, 1:40, 2) = NaN;   % epoch ran off the start of the recording

            q = dataQualityMetrics(EEG);

            testCase.verifyEqual(q.subject.n_trials_rejected, 0);
            testCase.verifyEqual(q.subject.n_trials_truncated, 1);
            testCase.verifyEqual(q.subject.n_channel_epochs_flagged, 0);
            testCase.verifyEqual(q.subject.max_truncated_pct_of_epoch, 100 * 40 / EEG.pnts, 'RelTol', 1e-12);
        end

        function anEntirelyEmptyTrialIsNotAlsoCountedAsTruncated(testCase)
            EEG = makeTestEEG('trials', 4, 'nbchan', 3);
            EEG.data(:, :, 2) = NaN;

            q = dataQualityMetrics(EEG);

            testCase.verifyEqual(q.subject.n_trials_rejected, 1);
            testCase.verifyEqual(q.subject.n_trials_truncated, 0);
        end

        function channelScopedRejectionIsNotMistakenForTruncation(testCase)
        %CHANNELSCOPEDREJECTIONISNOTMISTAKENFORTRUNCATION  Truncation is
        %   defined as samples NaN across EVERY channel at once. One channel
        %   NaN'd for a whole trial must stay a flagged channel-epoch.
            EEG = makeTestEEG('trials', 4, 'nbchan', 3);
            EEG.data(2, :, 3) = NaN;

            q = dataQualityMetrics(EEG);

            testCase.verifyEqual(q.subject.n_trials_truncated, 0);
            testCase.verifyEqual(q.subject.n_channel_epochs_flagged, 1);
        end

        function rejectionRanIsRecordedWhenTheCallerKnowsIt(testCase)
            EEG = makeTestEEG('trials', 4, 'nbchan', 2);

            testCase.verifyTrue(isnan(dataQualityMetrics(EEG).subject.rejection_ran));
            testCase.verifyEqual(dataQualityMetrics(EEG, [], {}, true).subject.rejection_ran, 1);
            testCase.verifyEqual(dataQualityMetrics(EEG, [], {}, false).subject.rejection_ran, 0);
        end

        % ---- bins ------------------------------------------------------
        function unbinnedDataReportsOneImplicitBin(testCase)
            q = dataQualityMetrics(makeTestEEG('trials', 4, 'nbchan', 2));

            testCase.verifyEqual(q.subject.n_bins, 1);
            testCase.verifyEqual(unique({q.byBinChannel.bin}), {'all'});
            testCase.verifyEqual(numel(q.byBinChannel), 2); % 1 bin x 2 channels
        end

        function rejectionIsCountedWithinEachBinSeparately(testCase)
        %REJECTIONISCOUNTEDWITHINEACHBINSEPARATELY  The point of the whole
        %   report (see generateDataQualityReport's own by-condition
        %   figure): a rejection that falls entirely in one bin must show
        %   up as that bin's rate, not smeared across both.
            EEG = makeTestEEG('trials', 8, 'nbchan', 1);
            EEG.bindesc = struct( ...
                'label', {'Rare', 'Frequent'}, 'index', {1, 2}, ...
                'trials', {1:4, 5:8});
            EEG.data(:, :, [1 2]) = NaN;   % both rejections land in "Rare"

            q = dataQualityMetrics(EEG);

            rare     = q.byBinChannel(strcmp({q.byBinChannel.bin}, 'Rare'));
            frequent = q.byBinChannel(strcmp({q.byBinChannel.bin}, 'Frequent'));
            testCase.verifyEqual(rare.n_trials_rejected, 2);
            testCase.verifyEqual(rare.pct_trials_rejected, 50);
            testCase.verifyEqual(frequent.n_trials_rejected, 0);
            testCase.verifyEqual(frequent.pct_trials_rejected, 0);
        end

        function combinationBinsAreSkipped(testCase)
        %COMBINATIONBINSARESKIPPED  A combination (difference) bin has no
        %   trials of its own -- Average computes it from the other bins'
        %   averages -- so a rejection rate for one would be meaningless.
            EEG = makeTestEEG('trials', 8, 'nbchan', 1);
            EEG.bindesc = struct( ...
                'label', {'Rare', 'Frequent', 'Rare-Frequent'}, ...
                'index', {1, 2, 3}, ...
                'trials', {1:4, 5:8, []}, ...
                'combo', {[], [], struct('bin', {1, 2}, 'coeff', {1, -1})});

            q = dataQualityMetrics(EEG);

            testCase.verifyEqual(q.subject.n_bins, 2);
            testCase.verifyFalse(ismember('Rare-Frequent', {q.byBinChannel.bin}));
        end

        function everyTrialAppearsOncePerBinItBelongsTo(testCase)
            EEG = makeTestEEG('trials', 6, 'nbchan', 1);
            EEG.bindesc = struct('label', {'A', 'B'}, 'index', {1, 2}, ...
                'trials', {1:6, 1:3});   % trials 1-3 are in both bins

            q = dataQualityMetrics(EEG);

            testCase.verifyEqual(numel(q.byTrial), 9);
            testCase.verifyEqual(sum(strcmp({q.byTrial.bin}, 'A')), 6);
            testCase.verifyEqual(sum(strcmp({q.byTrial.bin}, 'B')), 3);
        end

        % ---- baseline noise --------------------------------------------
        function baselineSdIsMeasuredOverThePreStimulusWindowOnly(testCase)
        %BASELINESDISMEASUREDOVERTHEPRESTIMULUSWINDOWONLY  Noise added
        %   AFTER zero must not move the pre-stimulus estimate at all.
            EEG = makeTestEEG('trials', 4, 'nbchan', 1);
            clean = dataQualityMetrics(EEG);

            postIdx = EEG.times >= 0;
            EEG.data(1, postIdx, :) = EEG.data(1, postIdx, :) + 500;
            noisyAfterZero = dataQualityMetrics(EEG);

            testCase.verifyEqual(noisyAfterZero.subject.median_baseline_sd_uv, ...
                clean.subject.median_baseline_sd_uv, 'AbsTol', 1e-10);
        end

        function anExtremelyNoisyTrialIsFlaggedAsABaselineOutlier(testCase)
        %ANEXTREMELYNOISYTRIALISFLAGGEDASABASELINEOUTLIER  The |z| > 2 rule
        %   Mathot & Vilotijevic apply to baseline pupil size, applied here
        %   to pre-stimulus SD. Needs enough trials for one value to reach
        %   |z| > 2 at all (the ceiling is (n-1)/sqrt(n)).
            EEG = makeTestEEG('trials', 30, 'nbchan', 1);
            preIdx = EEG.times < 0;
            EEG.data(1, preIdx, 7) = EEG.data(1, preIdx, 7) + 200 * randn(1, sum(preIdx));

            q = dataQualityMetrics(EEG);

            outliers = q.byTrial([q.byTrial.baseline_outlier] == 1);
            testCase.verifyEqual(unique([outliers.trial]), 7);
            testCase.verifyEqual(q.subject.n_baseline_outlier_trials, 1);
        end

        function aRejectedTrialIsNeverAlsoABaselineOutlier(testCase)
        %AREJECTEDTRIALISNEVERALSOABASELINEOUTLIER  A trial already gone
        %   must not be counted a second time in the outlier total -- see
        %   dataQualityMetrics' own note on scoring z over kept trials.
            EEG = makeTestEEG('trials', 30, 'nbchan', 1);
            EEG.data(:, :, 7) = NaN;

            q = dataQualityMetrics(EEG);

            rejectedRows = q.byTrial([q.byTrial.trial] == 7);
            testCase.verifyEqual(unique([rejectedRows.rejected]), 1);
            testCase.verifyEqual(unique([rejectedRows.baseline_outlier]), 0);
        end

        % ---- SME -------------------------------------------------------
        function smeIsReadPerChannelAndBinFromTheAverage(testCase)
            EEG = makeTestEEG('trials', 8, 'nbchan', 2);
            EEG.bindesc = struct('label', {'A', 'B'}, 'index', {1, 2}, 'trials', {1:4, 5:8});
            averaged = struct('aSME', [1.5 2.5; 3.5 4.5]);   % channels x bins

            q = dataQualityMetrics(EEG, averaged);

            testCase.verifyEqual(smeOf(q, 'A', 'Ch1'), 1.5);
            testCase.verifyEqual(smeOf(q, 'B', 'Ch1'), 2.5);
            testCase.verifyEqual(smeOf(q, 'A', 'Ch2'), 3.5);
            testCase.verifyEqual(smeOf(q, 'B', 'Ch2'), 4.5);
        end

        function smeIsNaNWithoutAnAverage(testCase)
            q = dataQualityMetrics(makeTestEEG('trials', 4, 'nbchan', 1));

            testCase.verifyTrue(all(isnan([q.byBinChannel.sme_uv])));
        end

        % ---- per-window SME --------------------------------------------
        function noWindowsMeansNoPerWindowSme(testCase)
            q = dataQualityMetrics(makeTestEEG('trials', 8, 'nbchan', 2));
            testCase.verifyEmpty(q.byWindowChannel);
        end

        function aPeakWindowProducesBothAnAmplitudeAndALatencyRow(testCase)
        %APEAKWINDOWPRODUCESBOTHANAMPLITUDEANDALATENCYROW  Measure reports
        %   peak amplitude and peak latency from one window, but their SMEs
        %   are different numbers in different units, so they cannot share
        %   a row (see dataQualityMetrics.scoreVariants).
            EEG = makeTestEEG('trials', 8, 'nbchan', 1);
            q = dataQualityMetrics(EEG, [], {testCase.window('Peak')});

            measures = unique({q.byWindowChannel.measure});
            testCase.verifyEqual(sort(measures), {'Peak', 'Peak Latency'});
            testCase.verifyEqual(unique({q.byWindowChannel.method}), {'bootstrap'});
        end

        function meanAmplitudeWindowUsesTheAnalyticEstimator(testCase)
            EEG = makeTestEEG('trials', 8, 'nbchan', 1);
            q = dataQualityMetrics(EEG, [], {testCase.window('Mean Amplitude')});

            testCase.verifyEqual(unique({q.byWindowChannel.method}), {'analytic'});
        end

        function perWindowSmeIsComputedSeparatelyPerBin(testCase)
            EEG = makeTestEEG('trials', 8, 'nbchan', 1);
            EEG.bindesc = struct('label', {'A', 'B'}, 'index', {1, 2}, 'trials', {1:4, 5:8});

            q = dataQualityMetrics(EEG, [], {testCase.window('Mean Amplitude')});

            testCase.verifyEqual(sort(unique({q.byWindowChannel.bin})), {'A', 'B'});
        end

        function aReferenceChannelWindowIsSkipped(testCase)
        %AREFERENCECHANNELWINDOWISSKIPPED  Its score depends on another
        %   channel, so a per-channel SME would describe a measurement
        %   nobody made. Skipped outright rather than approximated.
            EEG = makeTestEEG('trials', 8, 'nbchan', 2);
            win = testCase.window('Peak');
            win.refChannel = 'Ch1';

            q = dataQualityMetrics(EEG, [], {win});

            testCase.verifyEmpty(q.byWindowChannel);
        end

        function aChannelRestrictedWindowOnlyReportsThoseChannels(testCase)
            EEG = makeTestEEG('trials', 8, 'nbchan', 3);
            win = testCase.window('Mean Amplitude');
            win.channels = {'Ch2'};

            q = dataQualityMetrics(EEG, [], {win});

            testCase.verifyEqual(unique({q.byWindowChannel.channel}), {'Ch2'});
        end

        % ---- CSV export ------------------------------------------------
        function csvExportWritesBothFilesWithOneRowPerUnit(testCase)
            entries = testCase.twoSubjectEntries();
            stem = fullfile(tempname());

            [summaryCsv, trialCsv] = exportDataQualityCSVs(entries, stem);
            testCase.addTeardown(@() delete(summaryCsv));
            testCase.addTeardown(@() delete(trialCsv));

            summary = readtable(summaryCsv, 'TextType', 'string');
            trials  = readtable(trialCsv, 'TextType', 'string');

            expectedSummaryRows = sum(arrayfun(@(e) numel(e.quality.byBinChannel), entries));
            expectedTrialRows   = sum(arrayfun(@(e) numel(e.quality.byTrial), entries));
            testCase.verifyEqual(height(summary), expectedSummaryRows);
            testCase.verifyEqual(height(trials), expectedTrialRows);
            testCase.verifyEqual(sort(unique(summary.dataset))', ["s01", "s02"]);
            testCase.verifyTrue(all(ismember({'pct_trials_rejected', 'sme_uv', 'baseline_sd_uv'}, ...
                summary.Properties.VariableNames)));
        end

        function csvWritesMissingNumbersAsEmptyNotNaN(testCase)
        %CSVWRITESMISSINGNUMBERSASEMPTYNOTNAN  An absent SME must come back
        %   as a real NA in a numeric column, not coerce the whole column
        %   to text -- see exportDataQualityCSVs' own num() helper.
            entries = testCase.twoSubjectEntries();   % built with no Average, so every SME is NaN
            stem = fullfile(tempname());

            [summaryCsv, trialCsv] = exportDataQualityCSVs(entries, stem);
            testCase.addTeardown(@() delete(summaryCsv));
            testCase.addTeardown(@() delete(trialCsv));

            summary = readtable(summaryCsv);
            testCase.verifyTrue(isnumeric(summary.sme_uv));
            testCase.verifyTrue(all(isnan(summary.sme_uv)));
        end

        % ---- report generation -----------------------------------------
        function reportRefersToTheCsvsItWasGiven(testCase)
            qmd = generateDataQualityReport(testCase.twoSubjectEntries(), 'q.csv', 't.csv');

            testCase.verifySubstring(qmd, 'read_csv("q.csv"');
            testCase.verifySubstring(qmd, 'read_csv("t.csv"');
            testCase.verifySubstring(qmd, 'title: "Alakazam Data Quality Report"');
        end

        function mathAndPipeEscapesSurviveIntoTheReport(testCase)
        %MATHANDPIPEESCAPESSURVIVEINTOTHEREPORT  Two escaping levels are
        %   easy to get wrong here and both were, until a real render
        %   showed it, and the two sit at DIFFERENT escaping levels, which
        %   is exactly why they were both wrong.
        %
        %   The chi-squared symbol is written into R SOURCE inside the
        %   .qmd, so R's own parser eats one backslash level before cat()
        %   ever runs. The .qmd must therefore carry "$\\chi^2$" for
        %   $\chi^2$ to reach the page: "$\\\\chi^2$" (the original bug)
        %   emitted \\chi, a LaTeX line break, and MathJax then printed the
        %   letters c-h-i.
        %
        %   The pipe is plain markdown, not inside any R string, so it
        %   passes through at face value and needs exactly ONE backslash.
        %   Two made Pandoc read an escaped backslash followed by a real
        %   cell separator, splitting the table row in half.
            qmd = generateDataQualityReport(testCase.twoSubjectEntries(), 'q.csv', 't.csv');

            testCase.verifySubstring(qmd, '$\\chi^2$');
            testCase.verifyEmpty(strfind(qmd, '$\\\\chi^2$')); %#ok<STRIFCND>
            testCase.verifySubstring(qmd, '\|z\| > 2');
            testCase.verifyEmpty(strfind(qmd, '\\|z\\|')); %#ok<STRIFCND>
        end

        function reportRefusesAnEmptyExport(testCase)
            empty = struct('subject', {}, 'group', {}, 'session', {}, 'quality', {});
            testCase.verifyError(@() generateDataQualityReport(empty, 'q.csv', 't.csv'), ...
                'Alakazam:generateDataQualityReport');
        end

        function groupSectionAppearsOnlyWhenThereAreTwoGroups(testCase)
            ungrouped = testCase.twoSubjectEntries();
            grouped = ungrouped;
            [grouped.group] = deal('patient', 'control');

            testCase.verifyEmpty(strfind(generateDataQualityReport(ungrouped, 'q.csv', 't.csv'), ...
                'Quality by Between-Subjects Group')); %#ok<STRIFCND>
            testCase.verifySubstring(generateDataQualityReport(grouped, 'q.csv', 't.csv'), ...
                'Quality by Between-Subjects Group');
        end
    end

    methods
        function win = window(~, measure)
        %WINDOW  A Measure window struct over the post-stimulus half of
        %   makeTestEEG's own epoch (-200..596 ms), so there is real signal
        %   inside it to score.
            win = struct('label', 'W', 'start', 100, 'stop', 400, 'measure', measure, ...
                'polarity', 'Positive', 'width', [], 'localPoints', 0, 'fraction', 0.5, ...
                'areaMode', 'signed', 'baseline', [], 'refChannel', '', 'channels', '');
        end

        function entries = twoSubjectEntries(~)
        %TWOSUBJECTENTRIES  Two subjects' worth of quality metrics, in the
        %   struct-array shape collectDataQualityEntries returns.
            entries = struct('subject', {}, 'group', {}, 'session', {}, 'quality', {});
            for s = 1:2
                EEG = makeTestEEG('trials', 8, 'nbchan', 2);
                EEG.bindesc = struct('label', {'A', 'B'}, 'index', {1, 2}, 'trials', {1:4, 5:8});
                EEG.data(:, :, s) = NaN;
                entries(s) = struct('subject', sprintf('s%02d', s), 'group', '', ...
                    'session', '', 'quality', dataQualityMetrics(EEG));
            end
        end
    end
end

% ======================================================================= %
function v = smeOf(q, bin, channel)
    row = q.byBinChannel(strcmp({q.byBinChannel.bin}, bin) & ...
        strcmp({q.byBinChannel.channel}, channel));
    v = row.sme_uv;
end
