classdef ClusterStatsTest < matlab.unittest.TestCase
%CLUSTERSTATSTEST  Unit tests for src/+ClusterStats/*.m, the pure data
%   adapter/design-builder/result-translator behind the Cluster Statistics
%   feature (ft_timelockstatistics with cluster-based permutation
%   correction). Deliberately does not call FieldTrip anywhere: every
%   FieldTrip-shaped struct here (timelock, stat) is hand-built to match
%   FieldTrip's own documented, stable field layout, so these tests run
%   without FieldTrip (or EEGLAB) on the path -- the same reasoning
%   tests/fixtures/makeTestEEG.m's own header gives for the rest of this
%   suite. The actual ft_prepare_neighbours/ft_timelockstatistics calls
%   live in src/ClusterStats.m's own orchestration, which is intentionally
%   thin and not covered here.
%
%   Run with: runtests('tests/ClusterStatsTest.m').

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(root, 'src')));
        end
    end

    methods (Test)
        %% toFieldTripTimelock
        function timelockReshapesTheChosenBinIntoFieldTripShape(testCase)
            EEG = averagedFixture();
            tl = ClusterStats.toFieldTripTimelock(EEG, 'B');

            testCase.verifyEqual(tl.label, {'Ch1'; 'Ch2'});
            testCase.verifyEqual(tl.time, [0 0.004 0.008], 'AbsTol', 1e-12); % ms -> s
            testCase.verifyEqual(tl.dimord, 'chan_time');
            testCase.verifyEqual(tl.avg, EEG.data(:, :, 2), 'AbsTol', 1e-12); % 'B' is bin 2
        end

        function timelockThrowsAFriendlyErrorForAnUnknownBin(testCase)
            EEG = averagedFixture();
            testCase.verifyError(@() ClusterStats.toFieldTripTimelock(EEG, 'nope'), ...
                'Alakazam:ClusterStats');
        end

        %% zeroTimelock
        function zeroTimelockKeepsShapeButZerosTheAverage(testCase)
            EEG = averagedFixture();
            tl = ClusterStats.toFieldTripTimelock(EEG, 'A');
            tl0 = ClusterStats.zeroTimelock(tl);

            testCase.verifyEqual(tl0.label, tl.label);
            testCase.verifyEqual(tl0.time, tl.time);
            testCase.verifyEqual(tl0.dimord, tl.dimord);
            testCase.verifyEqual(tl0.avg, zeros(size(tl.avg)));
        end

        %% pairedDesign
        function pairedDesignPairsEachSubjectAcrossBothConditions(testCase)
            [design, ivar, uvar] = ClusterStats.pairedDesign(3);

            testCase.verifyEqual(design, [1 1 1 2 2 2; 1 2 3 1 2 3]);
            testCase.verifyEqual(ivar, 1);
            testCase.verifyEqual(uvar, 2);
        end

        function pairedDesignRejectsFewerThanTwoSubjects(testCase)
            testCase.verifyError(@() ClusterStats.pairedDesign(1), 'Alakazam:ClusterStats');
        end

        %% independentDesign
        function independentDesignMapsGroupLabelsToNumericCodesInFirstSeenOrder(testCase)
            [design, ivar] = ClusterStats.independentDesign({'B', 'A', 'B', 'A', 'A'});

            % 'B' is seen first, so it becomes code 1; 'A' (seen second) code 2.
            testCase.verifyEqual(design, [1 2 1 2 2]);
            testCase.verifyEqual(ivar, 1);
        end

        function independentDesignRejectsAnythingOtherThanTwoGroups(testCase)
            testCase.verifyError(@() ClusterStats.independentDesign({'A', 'A', 'A'}), ...
                'Alakazam:ClusterStats'); % only one distinct group
            testCase.verifyError(@() ClusterStats.independentDesign({'A', 'B', 'C'}), ...
                'Alakazam:ClusterStats'); % three distinct groups
        end

        %% summarizeClusterStat
        function summarizeReportsOnePositiveAndOneNegativeClusterCorrectly(testCase)
            stat = fakeClusterStat();
            clusters = ClusterStats.summarizeClusterStat(stat, 0.05);

            testCase.verifyEqual(numel(clusters), 2);
            % Sorted by p-value ascending: the positive cluster (p=.01) first.
            testCase.verifyEqual(clusters(1).sign, 'positive');
            testCase.verifyEqual(clusters(1).pValue, 0.01, 'AbsTol', 1e-12);
            testCase.verifyTrue(clusters(1).significant);
            testCase.verifyEqual(sort(clusters(1).channels), sort({'Cz'; 'Pz'}));
            testCase.verifyEqual(clusters(1).timeRangeMs, [200 300], 'AbsTol', 1e-9);
            testCase.verifyEqual(clusters(1).nPoints, 4);
            testCase.verifyEqual(clusters(1).clusterIndex, 1); % 1st (only) positive cluster

            testCase.verifyEqual(clusters(2).sign, 'negative');
            testCase.verifyEqual(clusters(2).pValue, 0.20, 'AbsTol', 1e-12);
            testCase.verifyFalse(clusters(2).significant); % p = .20 >= alpha = .05
            testCase.verifyEqual(clusters(2).channels, {'Fz'});
            testCase.verifyEqual(clusters(2).timeRangeMs, [0 100], 'AbsTol', 1e-9);
            testCase.verifyEqual(clusters(2).nPoints, 2);
            testCase.verifyEqual(clusters(2).clusterIndex, 1); % 1st (only) negative cluster

            % Rebuilding this exact cluster's own per-point mask from
            % clusterIndex must match what it was built from -- the whole
            % point of exposing it (see exportClusterStatsCSVs.m).
            rebuiltMask = stat.posclusterslabelmat == clusters(1).clusterIndex;
            testCase.verifyEqual(nnz(rebuiltMask), clusters(1).nPoints);
        end

        function summarizeReturnsEmptyWhenNothingSurvivedClustering(testCase)
            stat = fakeClusterStat();
            stat.posclusters = struct('prob', {});
            stat.posclusterslabelmat = zeros(size(stat.posclusterslabelmat));
            stat.negclusters = struct('prob', {});
            stat.negclusterslabelmat = zeros(size(stat.negclusterslabelmat));

            clusters = ClusterStats.summarizeClusterStat(stat, 0.05);

            testCase.verifyEqual(numel(clusters), 0);
        end

        function summarizeFallsBackToMaskOnlyForTfce(testCase)
        %SUMMARIZEFALLSBACKTOMASKONLYFORTFCE  cfg.correctm = 'tfce' output
        %   carries .mask/.stat/.prob but no *clusters*/*clusterslabelmat
        %   fields at all -- verify the fallback path (not the
        %   cluster-index path) produces one row per sign present.
            stat = struct();
            stat.label = {'Fz'; 'Cz'; 'Pz'};
            stat.time  = [0, 0.1, 0.2];
            stat.stat  = [ 0.5   3.0   0.2;   % Fz: one strong positive point
                          -0.1  -0.2  -4.0;   % Cz: one strong negative point
                           0.1   0.1   0.1];  % Pz: nothing notable
            stat.mask  = [false true  false;
                          false false true;
                          false false false];
            stat.prob  = ones(3, 3);
            stat.prob(1, 2) = 0.03; % the masked Fz/positive point
            stat.prob(2, 3) = 0.04; % the masked Cz/negative point

            clusters = ClusterStats.summarizeClusterStat(stat, 0.05);

            testCase.verifyEqual(numel(clusters), 2);
            signs = {clusters.sign};
            testCase.verifyTrue(any(strcmp(signs, 'positive')));
            testCase.verifyTrue(any(strcmp(signs, 'negative')));
            pos = clusters(strcmp(signs, 'positive'));
            testCase.verifyEqual(pos.channels, {'Fz'});
            testCase.verifyEqual(pos.pValue, 0.03, 'AbsTol', 1e-12);
            testCase.verifyTrue(pos.significant);
            testCase.verifyTrue(isnan(pos.clusterIndex)); % TFCE has no discrete cluster index
        end

        function summarizeHandlesAnEmptyMaskWithoutError(testCase)
            stat = struct();
            stat.label = {'Fz'; 'Cz'};
            stat.time  = [0, 0.1];
            stat.stat  = zeros(2, 2);
            stat.mask  = false(2, 2);
            stat.prob  = ones(2, 2);

            clusters = ClusterStats.summarizeClusterStat(stat, 0.05);

            testCase.verifyEqual(numel(clusters), 0);
        end

        %% resolveNumRandomization
        function upgradesToAllWhenRequestedExceedsHalfTheExhaustiveCount(testCase)
        %UPGRADESTOALLWHENREQUESTEDEXCEEDSHALFTHEEXHAUSTIVECOUNT  The
        %   exact scenario reported in practice: 10 subjects (max = 2^10 =
        %   1024 unique sign-flips), 1000 requested -- 1000/1024 = .977,
        %   past FieldTrip's own >0.5 "close to the maximum" threshold
        %   (resampledesign.m), so this should upgrade to 'all' rather
        %   than let that warning fire.
            n = ClusterStats.resolveNumRandomization(1000, 'paired', 10);
            testCase.verifyEqual(n, 'all');
        end

        function leavesARequestWellBelowHalfTheExhaustiveCountAlone(testCase)
            n = ClusterStats.resolveNumRandomization(100, 'paired', 10); % 100/1024 = .098
            testCase.verifyEqual(n, 100);
        end

        function boundaryAtExactlyHalfStaysNumericNotAll(testCase)
        %BOUNDARYATEXACTLYHALFSTAYSNUMERICNOTALL  FieldTrip's own check is
        %   a strict "> 0.5", not ">=" -- 512/1024 = exactly .5 must NOT
        %   upgrade, matching that exactly.
            n = ClusterStats.resolveNumRandomization(512, 'vsZero', 10);
            testCase.verifyEqual(n, 512);
        end

        function oneMoreThanTheBoundaryDoesUpgrade(testCase)
            n = ClusterStats.resolveNumRandomization(513, 'vsZero', 10); % 513/1024 = .5010
            testCase.verifyEqual(n, 'all');
        end

        function independentModeIsNeverUpgraded(testCase)
        %INDEPENDENTMODEISNEVERUPGRADED  An independent-samples design's
        %   own exhaustive count is nSubjects! (FieldTrip permutes every
        %   subject individually with no unit variable set), not 2^N --
        %   infeasible to ever generate for a realistic sample, so this
        %   must never upgrade it regardless of how large REQUESTED is.
            n = ClusterStats.resolveNumRandomization(1000, 'independent', 10);
            testCase.verifyEqual(n, 1000);
        end

        function alreadyAllPassesThroughUnchanged(testCase)
            n = ClusterStats.resolveNumRandomization('all', 'paired', 5);
            testCase.verifyEqual(n, 'all');
        end
    end
end

% ----------------------------------------------------------------------- %
function EEG = averagedFixture()
%AVERAGEDFIXTURE  A minimal, valid Alakazam Averaged EEG: 2 channels, 3
%   samples (0/4/8 ms), 2 ordinary bins 'A'/'B' with distinct, deterministic
%   values so a test can assert on the exact numbers copied through.
    EEG = struct();
    EEG.id = 'subj1';
    EEG.DataFormat = 'Averaged';
    EEG.trials = 1;
    EEG.times  = [0 4 8];
    EEG.chanlocs = struct('labels', {'Ch1', 'Ch2'});
    EEG.bindesc = struct('label', {'A', 'B'}, 'index', {1, 2}, 'n', {10, 10});
    EEG.data = nan(2, 3, 2);
    EEG.data(:, :, 1) = [1 2 3; 4 5 6];       % bin 'A'
    EEG.data(:, :, 2) = [10 20 30; 40 50 60]; % bin 'B'
end

function stat = fakeClusterStat()
%FAKECLUSTERSTAT  A hand-built stat struct matching ft_timelockstatistics'
%   own documented output shape for cfg.correctm = 'cluster': 3 channels
%   (Fz, Cz, Pz) x 4 time points (0/100/200/300 ms), one positive cluster
%   spanning Cz+Pz at 200-300 ms (label 1, prob .01) and one negative
%   cluster on Fz alone at 0-100 ms (label 1, prob .20).
    stat = struct();
    stat.label = {'Fz'; 'Cz'; 'Pz'};
    stat.time  = [0, 0.1, 0.2, 0.3]; % seconds
    stat.stat  = zeros(3, 4);

    stat.posclusters = struct('prob', {0.01});
    stat.posclusterslabelmat = zeros(3, 4);
    stat.posclusterslabelmat(2, 3) = 1; % Cz, 200ms
    stat.posclusterslabelmat(2, 4) = 1; % Cz, 300ms
    stat.posclusterslabelmat(3, 3) = 1; % Pz, 200ms
    stat.posclusterslabelmat(3, 4) = 1; % Pz, 300ms

    stat.negclusters = struct('prob', {0.20});
    stat.negclusterslabelmat = zeros(3, 4);
    stat.negclusterslabelmat(1, 1) = 1; % Fz, 0ms
    stat.negclusterslabelmat(1, 2) = 1; % Fz, 100ms

    stat.mask = stat.posclusterslabelmat > 0 | stat.negclusterslabelmat > 0;
    stat.prob = ones(3, 4);
    stat.prob(stat.posclusterslabelmat == 1) = 0.01;
    stat.prob(stat.negclusterslabelmat == 1) = 0.20;
end
