classdef EyeTrackingRecordTest < matlab.unittest.TestCase
%EYETRACKINGRECORDTEST  What Alakazam itself does with eye tracking: the
%   record a join leaves in EEG.etc.alz.eyeTracking becomes a row of the
%   data-quality report, and eye channels, typed EYE or named by where an
%   orbital electrode sits, are not scalp EEG.
%
%   The join itself is the Eyetracking plugin's (AlakazamEyetracking), and
%   tested there. JOINRECORD is what it records, written by hand.
%
%   Run with: runtests('tests/EyeTrackingRecordTest.m').
%
%   See also EYETRACKINGROW, DATAQUALITYMETRICS, EEGCHANNELMASK.

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
        function theJoinReachesTheDataQualityReport(testCase)
        %THEJOINREACHESTHEDATAQUALITYREPORT  EEG.etc travels down the branch,
        %   so the epoched node the report reads still carries the record of
        %   the join made on its continuous ancestor, and it becomes a
        %   provenance row with its numbers in columns rather than prose.
            EEG = makeTestEEG('trials', 8);
            EEG.etc.alz.eyeTracking = EyeTrackingRecordTest.joinRecord();

            q = dataQualityMetrics(EEG);

            row = q.provenance(strcmp({q.provenance.step}, 'EyeTracking'));
            testCase.assertNumElements(row, 1);
            testCase.verifyEqual([row.n row.n_total], [31 32]);
            testCase.verifyEqual(row.pct_within_one, 96.8, 'AbsTol', 1e-9);
            testCase.verifyEqual(row.mean_offset_ms, 0.4, 'AbsTol', 1e-9);
            testCase.verifyEqual(row.threshold, 90);
            testCase.verifySubstring(row.detail, 'anchored on 100 and 200');
        end

        function aDatasetWithoutAJoinHasNoSuchRow(testCase)
            q = dataQualityMetrics(makeTestEEG('trials', 8));

            testCase.verifyFalse(any(strcmp({q.provenance.step}, 'EyeTracking')));
        end

        function eyeElectrodesNamedByPositionAreEog(testCase)
        %EYEELECTRODESNAMEDBYPOSITIONAREEOG  Orbital electrodes labelled by
        %   where they sit (LO1, IO2, ...) rather than by type. EYE-EEG's own
        %   reading data carries LO1, LO2, IO1 and IO2, and counting them as
        %   scalp EEG put the recording's largest swings into every scan.
        %   Matched as whole labels, so nothing that merely contains the
        %   letters (O1, PO7, OI1) is caught.
            labels = {'Cz', 'LO1', 'IO2', 'SO1', 'LOC', 'ROC', 'O1', 'PO7', 'Oz', 'OI1', 'POO9'};
            chanlocs = struct('labels', labels, 'type', repmat({''}, 1, numel(labels)));

            testCase.verifyEqual(eegChannelMask(chanlocs), ...
                [true false false false false false true true true true true]);
        end

        function eyeChannelsAreNotScalpEeg(testCase)
        %EYECHANNELSARENOTSCALPEEG  EYE-EEG types its gaze and pupil channels
        %   EYE. They are pixels and pupil units, and counting them as EEG put
        %   them in every display scale, artefact scan and ICA.
            chanlocs = struct('labels', {'Cz', 'L_GAZE_X', 'L_AREA'}, 'type', {'', 'EYE', 'EYE'});

            testCase.verifyEqual(eegChannelMask(chanlocs), [true false false]);
        end
    end

    methods (Static)
        function info = joinRecord()
        %JOINRECORD  What EyeTracking leaves in EEG.etc.alz.eyeTracking.
            info = struct('file', 'C:\data\subject1myex.asc', 'how', 'found', ...
                'keyword', 'MYKEYWORD', 'startEvent', 100, 'endEvent', 200, ...
                'columns', {{'L_GAZE_X'}}, 'channels', {{'L-GAZE-X'}}, ...
                'importEyeEvents', true, 'searchRadius', 4, 'filterEyetrack', false, ...
                'quality', struct('nShared', 31, 'nTriggers', 32, 'pctMatched', 100 * 31 / 32, ...
                    'nWithinOne', 30, 'pctWithinOne', 96.8, 'meanAbsMs', 0.4, 'maxAbsSamples', 2), ...
                'limits', struct('minSharedEvents', 10, 'minPctWithinOne', 90));
        end
    end
end
