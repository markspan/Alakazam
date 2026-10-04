classdef SourceNoiseModelTest < matlab.unittest.TestCase
%SOURCENOISEMODELTEST  The baseline noise covariance, end to end: Average
%   stores it, SourceEstimate and the source cluster test resolve and use
%   it, and their keys, infos and provenance say which noise model ran.
%
%   On synthetic subjects with a standard 10-20 montage, through the real
%   template forward model (the 5124-vertex sheet, to stay quick), so it
%   runs without the cached study data the data-gated cases need. Needs
%   FieldTrip, and skips without it.
%
%   See also NOISECOVARIANCETEST, SOURCEESTIMATE, SOURCECLUSTERSTATS.

    properties (Constant)
        Labels = {'Fp1', 'Fp2', 'F7', 'F3', 'Fz', 'F4', 'F8', 'T7', 'C3', 'Cz', ...
                  'C4', 'T8', 'P7', 'P3', 'Pz', 'P4', 'P8', 'O1', 'O2'}
    end

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            for p = {fullfile(root, 'src'), fullfile(root, 'src', 'Support'), ...
                     fullfile(root, 'src', 'Reports'), fullfile(root, 'src', 'Transformations'), ...
                     fullfile(root, 'src', 'Transformations', 'Average'), ...
                     fullfile(root, 'src', 'Transformations', 'SourceEstimate'), ...
                     fullfile(root, 'tests', 'fixtures')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
        end

        function requireFieldTrip(testCase)
            FieldTripFixtures.require(testCase);
        end
    end

    methods (Test)
        function sourceEstimateUsesTheBaselineWhenItCan(testCase)
            avg = testCase.subjectAverage(1);
            withNoise = FieldTripFixtures.quietly(@() SourceEstimate(avg, testCase.estimateOpts('auto')));
            stored = withNoise.sourceEstimate(end);
            testCase.verifyEqual(stored.key.noiseModel, 'baseline');
            testCase.verifyEqual(stored.key.snr, 3);
            testCase.verifyEqual({stored.info.noiseModel}, {'baseline', 'baseline'});

            white = FieldTripFixtures.quietly(@() SourceEstimate(avg, testCase.estimateOpts('identity')));
            whiteStored = white.sourceEstimate(end);
            testCase.verifyEqual(whiteStored.key.noiseModel, 'identity');
            testCase.verifyGreaterThan(max(abs(stored.values(:) - whiteStored.values(:))), 0, ...
                'The two noise models give different estimates.');

            sl = FieldTripFixtures.quietly(@() SourceEstimate(avg, ...
                testCase.estimateOpts('auto', 'Method', 'sloreta')));
            testCase.verifyEqual(sl.sourceEstimate(end).key.noiseModel, 'identity', ...
                'sLORETA does not use it, and its key says so.');
        end

        function aDatasetWithoutOneFallsBackOrRefuses(testCase)
            avg = testCase.subjectAverage(1);
            avg.noiseCov = [];
            auto = FieldTripFixtures.quietly(@() SourceEstimate(avg, testCase.estimateOpts('auto')));
            testCase.verifyEqual(auto.sourceEstimate(end).key.noiseModel, 'identity');
            testCase.verifyError(@() FieldTripFixtures.quietly(@() ...
                SourceEstimate(avg, testCase.estimateOpts('baseline'))), 'Alakazam:SourceEstimate');
        end

    end

    methods (Test, TestTags = {'Slow'})
        function theClusterTestResolvesOneModelForEveryone(testCase)
            folder = tempname;
            mkdir(folder);
            cleanUp = onCleanup(@() rmdir(folder, 's'));
            files = cell(1, 3);
            for s = 1:3
                EEG = testCase.subjectAverage(s);
                files{s} = fullfile(folder, sprintf('s%d.mat', s));
                save(files{s}, 'EEG');
            end
            opts = struct('SourceSpace', 5124, 'ResampleHz', 50, 'TimeWindow', [0 300], ...
                'numrandomization', 10, 'correctm', 'cluster', 'Accelerate', false);
            contrast = struct('mode', 'paired', 'binA', 'A', 'binB', 'B');
            summary = FieldTripFixtures.quietly(@() SourceClusterStats(files, contrast, opts));
            testCase.verifyEqual(summary.provenance.noiseModel, 'baseline');
            testCase.verifyTrue(contains(summary.provenance.noiseCovariance, 'baseline'));
            testCase.verifyNotEmpty(summary.psfNoiseCov, 'The report''s point spread uses it too.');

            loaded = load(files{2}, 'EEG');
            EEG = loaded.EEG;
            EEG.noiseCov = [];
            save(files{2}, 'EEG');
            summary = FieldTripFixtures.quietly(@() SourceClusterStats(files, contrast, opts));
            testCase.verifyEqual(summary.provenance.noiseModel, 'identity', ...
                'One subject without it: the identity for everyone, never a mixture.');
            testCase.verifyEmpty(summary.psfNoiseCov);
        end
    end

    methods (Access = private)
        function avg = subjectAverage(testCase, seed)
        %SUBJECTAVERAGE  Forty epochs, -200 to 500 ms at 100 Hz, in two bins:
        %   correlated noise, plus a response after 100 ms in bin A.
            rng(seed);
            EEG = makeTestEEG('nbchan', numel(testCase.Labels), 'trials', 40, ...
                'srate', 100, 'epochMs', [-200 500], 'labels', testCase.Labels);
            nChan = numel(testCase.Labels);
            mixing = eye(nChan) + 0.3 * randn(nChan);
            noise = reshape(mixing * reshape(randn(nChan, EEG.pnts * 40), nChan, []), ...
                nChan, EEG.pnts, 40);
            pattern = linspace(-1, 1, nChan)';
            response = pattern * (EEG.times > 100 & EEG.times < 300) * 3;
            EEG.data = noise;
            EEG.data(:, :, 1:20) = EEG.data(:, :, 1:20) + response;
            EEG.bindesc(1) = struct('index', 1, 'label', 'A', 'trials', 1:20, 'combo', []);
            EEG.bindesc(2) = struct('index', 2, 'label', 'B', 'trials', 21:40, 'combo', []);
            avg = Average(EEG);
            avg.File = sprintf('subject%d.set', seed);
        end

        function opts = estimateOpts(~, noise, varargin)
            opts = struct('Method', 'mne', 'Orientation', 'normal', 'SourceSpace', 5124, ...
                'TimeWindow', [], 'ResampleHz', [], 'RegParam', 0.05, ...
                'NoiseCovariance', noise, 'SNR', 3);
            for k = 1:2:numel(varargin)
                opts.(varargin{k}) = varargin{k + 1};
            end
        end
    end
end
