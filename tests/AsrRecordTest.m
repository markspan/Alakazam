classdef AsrRecordTest < matlab.unittest.TestCase
%ASRRECORDTEST  What Alakazam itself does with ASR: the record a repair
%   leaves in EEG.etc.alz.asr becomes two rows of the data-quality report,
%   the channels interpolated and the samples repaired.
%
%   The repair itself is the ASR plugin's (AlakazamASR), and tested there.
%   The record here is written by hand, in the shape the plugin writes it,
%   and in the shapes a JSON round trip turns a short list into.
%
%   Run with: runtests('tests/AsrRecordTest.m').
%
%   See also DATAQUALITYMETRICS.

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            for p = {fullfile(root, 'src'), fullfile(root, 'src', 'Support'), ...
                     fullfile(root, 'src', 'Reports'), fullfile(root, 'src', 'Transformations'), ...
                     fullfile(root, 'tests', 'fixtures')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
        end
    end

    methods (Test)
        function theRepairReachesTheDataQualityReport(testCase)
            EEG = makeTestEEG('trials', 8);
            EEG.etc.alz.asr = AsrRecordTest.record();

            q = dataQualityMetrics(EEG);

            rows = q.provenance(strcmp({q.provenance.step}, 'ASR'));
            testCase.assertNumElements(rows, 2);
            channels = rows(strcmp({rows.item}, 'channels interpolated'));
            testCase.verifyEqual([channels.n channels.n_total], [2 5]);
            testCase.verifyEqual(channels.components, 'P8, T7');
            samples = rows(strcmp({rows.item}, 'samples repaired'));
            testCase.verifyEqual([samples.n samples.n_total], [1200 60000]);
            testCase.verifyEqual(samples.pct, 2, 'AbsTol', 1e-9);
            testCase.verifyEqual(samples.n_samples_rejected, 300);
            testCase.verifyEqual(samples.threshold, 20);
            testCase.verifyEqual(samples.detail, '2.10.2');
        end

        function aSingleInterpolatedChannelStillCounts(testCase)
        %ASINGLEINTERPOLATEDCHANNELSTILLCOUNTS  Saved and read back as JSON,
        %   a one-element list comes back as a bare string, and an empty one
        %   as [].
            EEG = makeTestEEG('trials', 8);
            EEG.etc.alz.asr = AsrRecordTest.record();
            EEG.etc.alz.asr.interpolated = 'P8';
            q = dataQualityMetrics(EEG);
            channels = q.provenance(strcmp({q.provenance.item}, 'channels interpolated'));
            testCase.verifyEqual(channels.n, 1);

            EEG.etc.alz.asr.interpolated = [];
            q = dataQualityMetrics(EEG);
            channels = q.provenance(strcmp({q.provenance.item}, 'channels interpolated'));
            testCase.verifyEqual(channels.n, 0);
        end

        function aDatasetWithoutARepairHasNoSuchRows(testCase)
            q = dataQualityMetrics(makeTestEEG('trials', 8));

            testCase.verifyFalse(any(strcmp({q.provenance.step}, 'ASR')));
        end
    end

    methods (Static)
        function info = record()
        %RECORD  What ASR leaves in EEG.etc.alz.asr.
            info = struct('version', '2.10.2', ...
                'channels', {{'Fz', 'Cz', 'Pz', 'P8', 'T7'}}, ...
                'interpolated', {{'P8', 'T7'}}, ...
                'samplesRepaired', 1200, 'samplesRejected', 300, 'nSamples', 60000, ...
                'burstCriterion', 20, 'options', struct('BurstCriterion', 20));
        end
    end
end
