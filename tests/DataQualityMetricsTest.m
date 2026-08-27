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
                fullfile(root, 'src', 'IO')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'Support')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'tests', 'fixtures')));
        end
    end

    methods (Test)
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
end
