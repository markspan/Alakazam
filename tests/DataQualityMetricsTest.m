classdef DataQualityMetricsTest < matlab.unittest.TestCase
%DATAQUALITYMETRICSTEST  How dataQualityMetrics accounts for the three
%   distinct things that can happen to a channel-epoch.
%
%   The metric derives almost everything from one convention: rejected data
%   is NaN, so a trial with every channel NaN was rejected whole and a trial
%   with only some channels NaN lost just those. That works for anything
%   REMOVED, and not at all for anything REPAIRED -- an interpolated cell
%   holds ordinary numbers and is invisible to every NaN-based count. These
%   tests pin down the three-way split (rejected / flagged / interpolated)
%   and, in particular, that a reconstructed cell is reported rather than
%   silently counted as clean.
%
%   No EEGLAB required: the interpolation MASK is set directly rather than
%   produced by running an interpolation, because what is under test here is
%   the accounting, not eeg_interp's maths (which
%   ArtefactDetectTest/ManualRejectTest cover at the transformation level).
%
%   Run with: runtests('tests/DataQualityMetricsTest.m').
%
%   See also DATAQUALITYMETRICS, MAKETESTEEG, ARTEFACTDETECTTEST.

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'Reports')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'Support')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'tests', 'fixtures')));
            % TransTools: the step function the blink count shares with
            % ArtefactDetect.
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'Transformations')));
        end
    end

    methods (Test)
        % ---- blinks by condition (Zhang et al., 2024) --------------------
        function blinksAreCountedPerBinAmongTheAveragedTrials(testCase)
        %BLINKSARECOUNTEDPERBINAMONGTHEAVERAGEDTRIALS  Two blinks in bin A's
        %   ten trials, six in bin B's, one of them in a rejected trial,
        %   which Average leaves out and so does the count.
            EEG = DataQualityMetricsTest.withEye({'Fz', 'Cz', 'VEOG'}, 3, [1 2], [11 12 13 14 15 16]);
            EEG.data(:, :, 16) = NaN;
            % A 10 Hz oscillation of 160 uV peak to peak: a large range in
            % every window, but whole cycles in each half of it, so no step
            % and no blink.
            EEG.data(3, :, 5) = EEG.data(3, :, 5) + 80 * sin(2 * pi * 10 * double(EEG.times) / 1000);

            q = dataQualityMetrics(EEG);

            testCase.assertNumElements(q.blinks, 2);
            a = q.blinks(strcmp({q.blinks.bin}, 'A'));
            b = q.blinks(strcmp({q.blinks.bin}, 'B'));
            testCase.verifyEqual([a.n_trials, a.n_assessed, a.n_blinks], [10 10 2]);
            testCase.verifyEqual([b.n_trials, b.n_assessed, b.n_blinks], [10 9 5]);
            testCase.verifyEqual(b.pct_blinks, 100 * 5 / 9, 'AbsTol', 1e-12);
            testCase.verifyEqual(a.source, 'VEOG');
        end

        function theAverageVeogIsTheMeanOfTheAveragedTrials(testCase)
            EEG = DataQualityMetricsTest.withEye({'Fz', 'Cz', 'VEOG'}, 3, [1 2], 11);
            EEG.data(:, :, 3) = NaN;

            q = dataQualityMetrics(EEG);

            rows = q.veog(strcmp({q.veog.bin}, 'A'));
            expected = mean(EEG.data(3, :, [1 2 4:10]), 3);
            testCase.verifyEqual([rows.veog_uv], expected, 'AbsTol', 1e-9);
            testCase.verifyEqual([rows.time_ms], double(EEG.times), 'AbsTol', 1e-12);
        end

        function aBipolarEogIsBuiltFromTheChannelBelowTheEye(testCase)
        %ABIPOLAREOGISBUILTFROMTHECHANNELBELOWTHEEYE  ERP CORE records
        %   VEOG-lower under the right eye; the bipolar EOG is FP2 above it
        %   less VEOG-lower, so a blink seen in both counts once, and a
        %   signal common to both, which is brain, is not a blink.
            EEG = DataQualityMetricsTest.withEye({'FP2', 'Cz', 'VEOG-lower'}, 3, [], []);
            blink = DataQualityMetricsTest.blinkShape(EEG);
            EEG.data(1, :, 1) = EEG.data(1, :, 1) + blink;          % above the eye
            EEG.data(3, :, 1) = EEG.data(3, :, 1) - 0.4 * blink;    % below it
            common = 2 * blink;                                    % the same on both
            EEG.data([1 3], :, 12) = EEG.data([1 3], :, 12) + [common; common];

            q = dataQualityMetrics(EEG);

            testCase.verifyEqual(q.blinks(1).source, 'FP2 - VEOG-lower');
            testCase.verifyEqual([q.blinks.n_blinks], [1 0]);
        end

        function withoutAVerticalEogThereIsNothingToCount(testCase)
            q = dataQualityMetrics(makeTestEEG('nbchan', 3, 'trials', 6));
            testCase.verifyEmpty(q.blinks);
            testCase.verifyEmpty(q.veog);
        end

        function cleanDataReportsNothingLost(testCase)
        %CLEANDATAREPORTSNOTHINGLOST  A baseline for the three counts, so a
        %   later failure can be read as "this one moved" rather than
        %   "these numbers are arbitrary".
            EEG = makeTestEEG('nbchan', 4, 'trials', 5);

            q = dataQualityMetrics(EEG);

            testCase.verifyEqual(q.subject.n_trials_rejected, 0);
            testCase.verifyEqual(q.subject.n_channel_epochs_flagged, 0);
            testCase.verifyEqual(q.subject.n_channel_epochs_interpolated, 0);
        end

        function wholeEpochRejectionIsNotCountedAsChannelLoss(testCase)
        %WHOLEEPOCHREJECTIONISNOTCOUNTEDASCHANNELLOSS  A trial with every
        %   channel NaN is one rejected TRIAL and zero flagged channels:
        %   counting its channels again would double-report the same loss.
            EEG = makeTestEEG('nbchan', 4, 'trials', 5);
            EEG.data(:, :, 2) = NaN;

            q = dataQualityMetrics(EEG);

            testCase.verifyEqual(q.subject.n_trials_rejected, 1);
            testCase.verifyEqual(q.subject.n_channel_epochs_flagged, 0);
        end

        function channelScopedRejectionCountsAsFlaggedNotAsARejectedTrial(testCase)
        %CHANNELSCOPEDREJECTIONCOUNTSASFLAGGEDNOTASAREJECTEDTRIAL  The
        %   mirror case: some channels gone, the trial survives.
            EEG = makeTestEEG('nbchan', 4, 'trials', 5);
            EEG.data(2, :, 3) = NaN;
            EEG.data(3, :, 3) = NaN;

            q = dataQualityMetrics(EEG);

            testCase.verifyEqual(q.subject.n_trials_rejected, 0);
            testCase.verifyEqual(q.subject.n_channel_epochs_flagged, 2);
            testCase.verifyEqual(q.subject.pct_channel_epochs_flagged, 100 * 2 / (4 * 5), ...
                'AbsTol', 1e-10);
        end

        function interpolatedCellsAreReportedRatherThanCountedAsClean(testCase)
        %INTERPOLATEDCELLSAREREPORTEDRATHERTHANCOUNTEDASCLEAN  The reason
        %   the mask exists. The data here is entirely non-NaN, so every
        %   NaN-derived count is legitimately zero -- and without reading
        %   EEG.etc.alz.interpolated the report would describe a recording
        %   with three reconstructed channel-epochs as untouched.
            EEG = makeTestEEG('nbchan', 4, 'trials', 5);
            mask = false(4, 5);
            mask(1, 1) = true;
            mask(2, 4) = true;
            mask(2, 5) = true;
            EEG.etc.alz.interpolated = mask;

            q = dataQualityMetrics(EEG);

            testCase.verifyEqual(q.subject.n_trials_rejected, 0);
            testCase.verifyEqual(q.subject.n_channel_epochs_flagged, 0);
            testCase.verifyEqual(q.subject.n_channel_epochs_interpolated, 3);
            testCase.verifyEqual(q.subject.pct_channel_epochs_interpolated, ...
                100 * 3 / (4 * 5), 'AbsTol', 1e-10);
        end

        function interpolatedAndFlaggedAreCountedSeparately(testCase)
        %INTERPOLATEDANDFLAGGEDARECOUNTEDSEPARATELY  A dataset that has been
        %   through both treatments must not fold one into the other:
        %   discarded and reconstructed are different claims about the data.
            EEG = makeTestEEG('nbchan', 4, 'trials', 5);
            EEG.data(4, :, 1) = NaN;          % discarded
            mask = false(4, 5);
            mask(1, 2) = true;                % reconstructed
            EEG.etc.alz.interpolated = mask;

            q = dataQualityMetrics(EEG);

            testCase.verifyEqual(q.subject.n_channel_epochs_flagged, 1);
            testCase.verifyEqual(q.subject.n_channel_epochs_interpolated, 1);
        end

        function aMaskOfTheWrongShapeIsIgnored(testCase)
        %AMASKOFTHEWRONGSHAPEISIGNORED  A mask written before a resample or
        %   a channel edit no longer maps onto this dataset. There is no
        %   honest way to realign it, so it is dropped rather than applied
        %   to whichever cells happen to line up.
            EEG = makeTestEEG('nbchan', 4, 'trials', 5);
            EEG.etc.alz.interpolated = true(2, 2);

            q = dataQualityMetrics(EEG);

            testCase.verifyEqual(q.subject.n_channel_epochs_interpolated, 0);
        end

        function aDatasetWithNoEtcFieldIsFine(testCase)
        %ADATASETWITHNOETCFIELDISFINE  Every dataset saved before the mask
        %   existed has no etc.alz at all, and must read as "nothing was
        %   interpolated" rather than erroring.
            EEG = makeTestEEG('nbchan', 3, 'trials', 3);
            testCase.verifyFalse(isfield(EEG, 'etc'));

            q = dataQualityMetrics(EEG);

            testCase.verifyEqual(q.subject.n_channel_epochs_interpolated, 0);
        end

        function perChannelInterpolationCountsReachTheBinTable(testCase)
        %PERCHANNELINTERPOLATIONCOUNTSREACHTHEBINTABLE  The subject-level
        %   percentage dilutes badly (one channel rebuilt in every trial of
        %   a large montage is a small share of all channel-epochs), so the
        %   per-channel row is what actually surfaces a mostly-reconstructed
        %   channel in the report. It has to be populated.
            EEG = makeTestEEG('nbchan', 4, 'trials', 5);
            mask = false(4, 5);
            mask(3, :) = true;            % channel 3 rebuilt in every trial
            EEG.etc.alz.interpolated = mask;

            q = dataQualityMetrics(EEG);

            rows = q.byBinChannel;
            testCase.verifyNotEmpty(rows);
            names = {rows.channel};
            row3 = rows(strcmp(names, 'Ch3'));
            testCase.verifyNotEmpty(row3);
            testCase.verifyEqual(sum([row3.n_interpolated]), 5);
            testCase.verifyEqual(max([row3.pct_interpolated]), 100, 'AbsTol', 1e-10);

            row1 = rows(strcmp(names, 'Ch1'));
            testCase.verifyEqual(sum([row1.n_interpolated]), 0);
        end
    end

    methods (Static, Access = private)
        function EEG = withEye(labels, eye, blinksA, blinksB)
        %WITHEYE  Twenty trials in two bins, A (1 to 10) and B (11 to 20), on
        %   channels LABELS, with a blink added to channel EYE in the trials
        %   BLINKSA and BLINKSB (trial numbers).
            EEG = makeTestEEG('nbchan', numel(labels), 'trials', 20);
            EEG.chanlocs = struct('labels', labels);
            EEG.bindesc = struct('label', {'A', 'B'}, 'index', {1, 2}, 'trials', {1:10, 11:20});
            blink = DataQualityMetricsTest.blinkShape(EEG);
            for t = [blinksA, blinksB]
                EEG.data(eye, :, t) = EEG.data(eye, :, t) + blink;
            end
        end

        function blink = blinkShape(EEG)
        %BLINKSHAPE  A blink as the vertical EOG sees one: a 300 uV raised
        %   cosine 300 ms long, peaking 300 ms after the event.
            t = double(EEG.times);
            inside = abs(t - 300) < 150;
            blink = zeros(size(t));
            blink(inside) = 300 * (1 + cos(pi * (t(inside) - 300) / 150)) / 2;
        end
    end
end
