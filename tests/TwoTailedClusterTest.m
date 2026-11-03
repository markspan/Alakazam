classdef TwoTailedClusterTest < matlab.unittest.TestCase
%TWOTAILEDCLUSTERTEST  A two-tailed cluster test spends its alpha on both tails,
%   whichever route it takes, and each person counts once.
%
%   FieldTrip's probabilities describe one tail. This used to ask for
%   correcttail 'alpha', which leaves them so, and then compare them with the
%   whole alpha in the summary, so that on null data the report called a cluster
%   significant in 12.0% of runs and FieldTrip's own mask in 5.5%. The split
%   route's mask, built outside FieldTrip, did the same.
%
%   See also CLUSTERSTATS, SOURCECLUSTERSTATS, CLUSTERSTATS.POOLMONTECARLO,
%   CLUSTERSTATS.SUMMARIZECLUSTERSTAT, CLUSTERSTATS.AVERAGEWITHINPERSON.
    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            import matlab.unittest.fixtures.PathFixture
            testCase.applyFixture(PathFixture(fullfile(root, 'src')));
            testCase.applyFixture(PathFixture(fullfile(root, 'src', 'Transformations')));
            testCase.applyFixture(PathFixture(fullfile(root, 'src', 'Support')));
            testCase.applyFixture(PathFixture(fullfile(root, 'tests')));
        end
    end

    methods (Test)
        function theSplitRouteDoublesProbabilitiesUnderProb(testCase)
            [results, counts] = splitRun();
            plain = ClusterStats.poolMontecarlo(results, counts, struct('tail', 0, 'alpha', 0.05));
            cfg = struct('tail', 0, 'alpha', 0.05, 'correcttail', 'prob');
            stat = ClusterStats.poolMontecarlo(results, counts, cfg);
            testCase.verifyEqual(stat.prob, min(2 * plain.prob, 1), 'AbsTol', 1e-15);
            testCase.verifyEqual(stat.mask, stat.prob <= 0.05);
        end

        function theSplitRouteHalvesAlphaUnderAlpha(testCase)
            [results, counts] = splitRun();
            cfg = struct('tail', 0, 'alpha', 0.05, 'correcttail', 'alpha');
            stat = ClusterStats.poolMontecarlo(results, counts, cfg);
            testCase.verifyEqual(stat.mask, stat.prob <= 0.025);
        end

        function oneTailIsNotCorrected(testCase)
            [results, counts] = splitRun();
            plain = ClusterStats.poolMontecarlo(results, counts, struct('tail', 1, 'alpha', 0.05));
            stat = ClusterStats.poolMontecarlo(results, counts, ...
                struct('tail', 1, 'alpha', 0.05, 'correcttail', 'prob'));
            testCase.verifyEqual(stat.prob, plain.prob);
            testCase.verifyEqual(stat.mask, plain.prob <= 0.05);
        end

        function theSummaryUsesTheComparisonTheMaskUses(testCase)
            stat = struct('label', {{'Fz'; 'Cz'}}, 'time', [0 0.1 0.2], ...
                'prob', [0.05 0.05 1; 1 1 1], 'mask', logical([1 1 0; 0 0 0]), ...
                'posclusters', struct('prob', {0.05}, 'clusterstat', {3}), ...
                'posclusterslabelmat', [1 1 0; 0 0 0]);
            clusters = ClusterStats.summarizeClusterStat(stat, 0.05);
            testCase.verifyTrue(clusters.significant, ...
                'FieldTrip masks p <= alpha, so a cluster at exactly alpha is significant.');
        end

        function bothScalpAndSourceAskForTheSameCorrection(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            for file = {'ClusterStats.m', 'SourceClusterStats.m'}
                text = fileread(fullfile(root, 'src', file{1}));
                testCase.verifySubstring(text, 'cfg.correcttail = ''prob''', file{1});
                testCase.verifyFalse(contains(text, 'cfg.correcttail = ''alpha'''), file{1});
            end
        end

        function aTwoTailedRunReportsDoubledProbabilities(testCase)
        %   The one check that cannot pass by luck: every cluster's printed p is
        %   twice the share of its own tail's null distribution, and what the
        %   summary calls significant is what FieldTrip's mask holds.
            FieldTripFixtures.require(testCase);
            for seed = 1:3
                rng(seed, 'twister');
                files = testCase.writeFiles(randomSubjects(12));
                summary = FieldTripFixtures.quietly(@() ClusterStats(files, ...
                    struct('mode', 'vsZero', 'bin', 'A'), struct('numrandomization', 300)));
                stat = summary.stat;
                testCase.assumeTrue(isfield(stat, 'posclusters') && ~isempty(stat.posclusters));
                top = stat.posclusters(1);
                share = (1 + nnz(stat.posdistribution > top.clusterstat)) / (numel(stat.posdistribution) + 1);
                testCase.verifyEqual(top.prob, min(2 * share, 1), 'AbsTol', 1e-12);
                for c = 1:numel(summary.clusters)
                    entry = summary.clusters(c);
                    if strcmp(entry.sign, 'positive')
                        points = stat.posclusterslabelmat == entry.clusterIndex;
                    else
                        points = stat.negclusterslabelmat == entry.clusterIndex;
                    end
                    testCase.verifyEqual(entry.significant, any(stat.mask(points)));
                end
            end
        end

        function theChannelOrderDoesNotChangeTheTest(testCase)
            FieldTripFixtures.require(testCase);
            rng(7, 'twister');
            subjects = randomSubjects(10);
            mixed = subjects;
            for i = 2:2:numel(mixed)
                mixed{i}.data = mixed{i}.data(end:-1:1, :, :);
                mixed{i}.chanlocs = mixed{i}.chanlocs(end:-1:1);
            end
            options = struct('numrandomization', 100);
            contrast = struct('mode', 'vsZero', 'bin', 'A');
            a = FieldTripFixtures.quietly(@() ClusterStats(testCase.writeFiles(subjects), contrast, options));
            b = FieldTripFixtures.quietly(@() ClusterStats(testCase.writeFiles(mixed), contrast, options));
            testCase.verifyEqual(b.stat.stat, a.stat.stat, 'AbsTol', 1e-10);
        end

        function aPeripheralChannelIsDroppedByItsOwnLabel(testCase)
        %   The mask used to be the first subject's, applied by position to all.
            FieldTripFixtures.require(testCase);
            rng(8, 'twister');
            subjects = randomSubjects(8);
            for i = 1:numel(subjects)
                subjects{i}.data = [subjects{i}.data; zeros(1, size(subjects{i}.data, 2))];
                subjects{i}.chanlocs(end + 1).labels = 'VEOG';
            end
            subjects{2}.data = subjects{2}.data([end, 1:end - 1], :, :);
            subjects{2}.chanlocs = subjects{2}.chanlocs([end, 1:end - 1]);
            summary = FieldTripFixtures.quietly(@() ClusterStats(testCase.writeFiles(subjects), ...
                struct('mode', 'vsZero', 'bin', 'A'), struct('numrandomization', 50)));
            testCase.verifyFalse(any(strcmp(summary.stat.label, 'VEOG')));
            testCase.verifyEqual(numel(summary.stat.label), 19);
        end

        function aDifferentChannelSetIsRefused(testCase)
            subjects = randomSubjects(3);
            subjects{2}.chanlocs(3).labels = 'Oz';
            testCase.verifyError(@() ClusterStats(testCase.writeFiles(subjects), ...
                struct('mode', 'vsZero', 'bin', 'A'), struct()), 'Alakazam:ClusterStats');
        end

        function aShiftedTimeAxisIsRefused(testCase)
            subjects = randomSubjects(3);
            subjects{2}.times = subjects{2}.times + 100;
            testCase.verifyError(@() ClusterStats(testCase.writeFiles(subjects), ...
                struct('mode', 'vsZero', 'bin', 'A'), struct()), 'Alakazam:ClusterStats');
        end

        function withNoPersonsEveryRecordingStands(testCase)
            subjects = randomSubjects(3);
            [out, contrast, kept] = ClusterStats.averageWithinPerson(subjects, struct('mode', 'vsZero'));
            testCase.verifyEqual(kept, 1:3);
            testCase.verifyEqual(numel(out), 3);
            testCase.verifyFalse(isfield(contrast, 'recordingsPerPerson'));
        end

        function aPersonsRecordingsBecomeOneSubject(testCase)
            subjects = randomSubjects(3);
            contrast = struct('mode', 'vsZero', 'personOf', {{'p1', 'p2', 'p1'}});
            [out, contrast, kept] = ClusterStats.averageWithinPerson(subjects, contrast);
            testCase.verifyEqual(kept, [1 2]);
            testCase.verifyEqual(contrast.recordingsPerPerson, [2 1]);
            testCase.verifyEqual(contrast.personOf, {'p1', 'p2'});
            testCase.verifyEqual(out{1}.data, (subjects{1}.data + subjects{3}.data) / 2, 'AbsTol', 1e-12);
            testCase.verifyEqual(out{2}.data, subjects{2}.data);
        end

        function channelsAreAveragedByLabel(testCase)
            subjects = randomSubjects(2);
            shuffled = subjects{2};
            shuffled.data = shuffled.data(end:-1:1, :, :);
            shuffled.chanlocs = shuffled.chanlocs(end:-1:1);
            contrast = struct('mode', 'vsZero', 'personOf', {{'p', 'p'}});
            out = ClusterStats.averageWithinPerson({subjects{1}, shuffled}, contrast);
            testCase.verifyEqual(out{1}.data, (subjects{1}.data + subjects{2}.data) / 2, 'AbsTol', 1e-12);
        end

        function aBlankPersonIsItsOwnPerson(testCase)
            subjects = randomSubjects(3);
            [out, ~, kept] = ClusterStats.averageWithinPerson(subjects, ...
                struct('mode', 'vsZero', 'personOf', {{'', 'p', ''}}));
            testCase.verifyEqual(numel(out), 3);
            testCase.verifyEqual(kept, 1:3);
        end

        function theGroupsFollowThePeople(testCase)
            subjects = randomSubjects(4);
            contrast = struct('mode', 'independent', 'personOf', {{'a', 'a', 'b', 'c'}}, ...
                'groupOf', {{'g1', 'g1', 'g1', 'g2'}});
            [out, contrast] = ClusterStats.averageWithinPerson(subjects, contrast);
            testCase.verifyEqual(numel(out), 3);
            testCase.verifyEqual(contrast.groupOf, {'g1', 'g1', 'g2'});
        end

        function aPersonInTwoGroupsIsRefused(testCase)
            subjects = randomSubjects(2);
            contrast = struct('mode', 'independent', 'personOf', {{'a', 'a'}}, 'groupOf', {{'g1', 'g2'}});
            testCase.verifyError(@() ClusterStats.averageWithinPerson(subjects, contrast), 'Alakazam:ClusterStats');
        end

        function theNoiseOfAMeanIsTheSumOverKSquared(testCase)
            subjects = randomSubjects(2);
            nChan = size(subjects{1}.data, 1);
            subjects{1}.noiseCov = 2 * eye(nChan);
            subjects{2}.noiseCov = 4 * eye(nChan);
            out = ClusterStats.averageWithinPerson(subjects, struct('mode', 'vsZero', 'personOf', {{'p', 'p'}}));
            testCase.verifyEqual(out{1}.noiseCov, 1.5 * eye(nChan), 'AbsTol', 1e-12);
        end

        function aMissingNoiseCovarianceDropsThePersons(testCase)
            subjects = randomSubjects(2);
            subjects{1}.noiseCov = eye(size(subjects{1}.data, 1));
            subjects{2}.noiseCov = [];
            out = ClusterStats.averageWithinPerson(subjects, struct('mode', 'vsZero', 'personOf', {{'p', 'p'}}));
            testCase.verifyEmpty(out{1}.noiseCov);
        end

        function aPersonsShiftedRecordingsAreRefused(testCase)
            subjects = randomSubjects(2);
            subjects{2}.times = subjects{2}.times + 8;
            testCase.verifyError(@() ClusterStats.averageWithinPerson(subjects, ...
                struct('mode', 'vsZero', 'personOf', {{'p', 'p'}})), 'Alakazam:ClusterStats');
        end
    end

    methods
        function files = writeFiles(testCase, subjects)
            folder = tempname();
            mkdir(folder);
            testCase.addTeardown(@() rmdir(folder, 's'));
            files = cell(1, numel(subjects));
            for i = 1:numel(subjects)
                EEG = subjects{i};
                files{i} = fullfile(folder, sprintf('s%d.mat', i));
                save(files{i}, 'EEG');
            end
        end
    end
end

function [results, counts] = splitRun()
    rng(3, 'twister');
    statobs = linspace(-3, 3, 41).';
    counts = [40 40 40];
    results = cell(1, 3);
    for k = 1:3
        results{k} = struct('stat', statobs, 'prob', zeros(41, 1), ...
            'posdistribution', randn(1, counts(k)) + 1, 'negdistribution', randn(1, counts(k)) - 1);
    end
end

function subjects = randomSubjects(n)
%RANDOMSUBJECTS  N Averaged subjects of smoothed noise on the 10-20 montage.
    labels = {'Fp1', 'Fp2', 'F7', 'F3', 'Fz', 'F4', 'F8', 'T7', 'C3', 'Cz', ...
        'C4', 'T8', 'P7', 'P3', 'Pz', 'P4', 'P8', 'O1', 'O2'};
    times = -100:4:300;
    subjects = cell(1, n);
    for i = 1:n
        x = conv2(randn(numel(labels), numel(times)), ones(1, 9) / 9, 'same');
        subjects{i} = struct('data', x, 'chanlocs', struct('labels', labels), 'times', times, ...
            'srate', 250, 'nbchan', numel(labels), 'trials', 1, 'pnts', numel(times), ...
            'DataFormat', "Averaged", 'id', sprintf('s%d', i), 'setname', sprintf('s%d', i), ...
            'bindesc', struct('index', 1, 'label', 'A', 'combo', [], 'n', 40));
    end
end
