classdef AsrTest < matlab.unittest.TestCase
%ASRTEST  ASR: clean_rawdata's bad-channel and burst stages, with the
%   channels put back and rejection marked rather than cut.
%
%   The rule that turns ASR's changes into rejected samples is Alakazam's
%   own copy of clean_rawdata's, and is tested on its own, without EEGLAB.
%   The transformation is tested on a synthetic recording on a real montage
%   (makeScalpEEG) with a flat channel and a burst planted in it: the flat
%   channel must be found and rebuilt in its own place, the burst repaired
%   (or, when asked, rejected on every channel), the peripheral left alone,
%   and a replay must give the same result. Those cases need EEGLAB and its
%   clean_rawdata plugin, and are skipped without them.
%
%   Run with: runtests('tests/AsrTest.m').
%
%   See also ASR, ASRREJECTEDSAMPLES.

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            for p = {fullfile(root, 'src', 'Transformations', 'ASR'), ...
                     fullfile(root, 'src', 'Transformations'), ...
                     fullfile(root, 'src', 'Support'), ...
                     fullfile(root, 'src'), ...
                     fullfile(root, 'tests', 'fixtures')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
        end
    end

    methods (Test)
        % ---- the rejection rule -------------------------------------------
        function everyChangedSampleIsRejected(testCase)
            changed = false(1, 40);
            changed(10:14) = true;

            testCase.verifyEqual(asrRejectedSamples(changed), changed);
        end

        function aShortKeptStretchBetweenBurstsIsRejectedToo(testCase)
        %ASHORTKEPTSTRETCHBETWEENBURSTSISREJECTEDTOO  clean_artifacts drops a
        %   kept interval [first last] with last - first < 5: a handful of
        %   samples between two bursts is not usable data.
            changed = logical([0 0 1 1 0 0 0 1 0 0 0 0 0 0 1]);

            rejected = asrRejectedSamples(changed);

            testCase.verifyEqual(double(rejected), [1 1 1 1 1 1 1 1 0 0 0 0 0 0 1], ...
                'Samples 1-2 and 5-7 are too short to keep; 9-14 spans five intervals and stays.');
        end

        function nothingChangedRejectsNothing(testCase)
            testCase.verifyFalse(any(asrRejectedSamples(false(1, 100))));
        end

        % ---- the transformation ------------------------------------------
        function aFlatChannelIsRebuiltInItsOwnPlace(testCase)
            testCase.requireCleanRawdata();
            [EEG, flat] = testCase.recording();

            out = ASR(EEG, testCase.options('Repaired'));

            testCase.verifyEqual({out.chanlocs.labels}, {EEG.chanlocs.labels}, ...
                'The montage is unchanged, in order.');
            testCase.verifyTrue(ismember('P8', out.etc.alz.asr.interpolated));
            testCase.verifyGreaterThan(std(out.data(flat, :)), 1, ...
                'The flat channel now carries its neighbours'' signal.');
        end

        function aBurstIsRepaired(testCase)
            testCase.requireCleanRawdata();
            [EEG, ~, burst] = testCase.recording();

            out = ASR(EEG, testCase.options('Repaired'));

            testCase.verifyGreaterThan(out.etc.alz.asr.samplesRepaired, 0);
            testCase.verifyEqual(out.etc.alz.asr.samplesRejected, 0);
            testCase.verifyLessThan(max(abs(out.data(1:19, burst)), [], 'all'), ...
                0.5 * max(abs(EEG.data(1:19, burst)), [], 'all'), ...
                'The 300 uV burst should be largely reconstructed away.');
            testCase.verifyFalse(any(isnan(out.data), 'all'));
        end

        function aRejectedBurstIsNaNOnEveryChannel(testCase)
        %AREJECTEDBURSTISNANONEVERYCHANNEL  Marked, not cut: the recording
        %   keeps its length and its events their latencies, and the stretch
        %   is rejected on the peripheral too, since the rejection is about
        %   that moment of the recording.
            testCase.requireCleanRawdata();
            [EEG, ~, burst] = testCase.recording();

            out = ASR(EEG, testCase.options('Rejected'));

            testCase.verifyEqual(size(out.data), size(EEG.data));
            testCase.verifyGreaterThan(out.etc.alz.asr.samplesRejected, 0);
            rejected = all(isnan(out.data), 1);
            testCase.verifyEqual(any(isnan(out.data), 1), rejected, ...
                'A rejected sample is rejected on every channel.');
            testCase.verifyGreaterThan(nnz(rejected(burst)), 0.5 * numel(burst));
        end

        function thePeripheralIsLeftAlone(testCase)
            testCase.requireCleanRawdata();
            EEG = testCase.recording();
            veog = strcmp({EEG.chanlocs.labels}, 'VEOG');

            out = ASR(EEG, testCase.options('Repaired'));

            testCase.verifyEqual(out.data(veog, :), EEG.data(veog, :));
        end

        function aReplayReproducesTheResult(testCase)
            testCase.requireCleanRawdata();
            EEG = testCase.recording();

            [first, options] = ASR(EEG, testCase.options('Repaired'));
            second = ASR(EEG, options);

            testCase.verifyEqual(second.data, first.data);
        end

        function theCallersRandomStreamIsLeftAlone(testCase)
        %THECALLERSRANDOMSTREAMISLEFTALONE  clean_channels resets MATLAB's
        %   random generator to its default; ASR must not pass that on.
            testCase.requireCleanRawdata();
            EEG = testCase.recording();
            rng(1234, 'twister');
            expected = rand(1, 3);
            rng(1234, 'twister');

            ASR(EEG, testCase.options('Repaired'));

            rng(1234, 'twister');
            testCase.verifyEqual(rand(1, 3), expected);
        end

        function rejectedStretchesAreRefused(testCase)
            testCase.requireCleanRawdata();
            EEG = testCase.recording();
            EEG.data(:, 100:200) = NaN;

            testCase.verifyError(@() ASR(EEG, testCase.options('Repaired')), 'Alakazam:ASR');
        end

        function epochedDataIsRefused(testCase)
            testCase.requireCleanRawdata();
            EEG = makeTestEEG();
            testCase.verifyError(@() ASR(EEG, testCase.options('Repaired')), 'Alakazam:ASR');
        end
    end

    methods (Access = private)
        function requireCleanRawdata(testCase)
            try
                EEGLabEnvironment.ensure();
            catch
            end
            testCase.assumeTrue(exist('pop_chanedit', 'file') == 2, 'EEGLAB is not on the path.');
            testCase.assumeTrue(exist('clean_asr', 'file') == 2, ...
                'EEGLAB''s clean_rawdata plugin is not installed.');
        end

        function [EEG, flat, burst] = recording(~)
        %RECORDING  Three minutes on the 10-20 channels plus a VEOG, at 128
        %   Hz: P8 flat throughout, and a 2 s burst of 300 uV on five
        %   frontal channels at 90 s.
            EEG = makeScalpEEG('DataFormat', 'CONTINUOUS', 'seconds', 180, ...
                'extra', {'VEOG'}, 'seed', 21);
            flat = find(strcmp({EEG.chanlocs.labels}, 'P8'));
            EEG.data(flat, :) = 0.5;
            burst = round(90 * EEG.srate):round(92 * EEG.srate);
            stream = RandStream('mt19937ar', 'Seed', 22);
            EEG.data(1:5, burst) = EEG.data(1:5, burst) + 300 * randn(stream, 5, numel(burst));
        end

        function opts = options(~, handling)
            opts = struct('FlatlineSeconds', 5, 'ChannelCorrelation', 0.8, 'LineNoiseSD', 4, ...
                'BurstCriterion', 20, 'BurstHandling', handling, 'RejectWindows', false, ...
                'WindowCriterion', 0.25);
        end
    end
end
