classdef ExportSetTest < matlab.unittest.TestCase
%EXPORTSETTEST  A dataset exported as an EEGLAB .set file reads back in
%   EEGLAB as EEGLAB's own: prepareSetExport, then the real pop_saveset and
%   pop_loadset.
%
%   THE ONE THIS PINS. Alakazam keeps a continuous recording's EEG.times in
%   seconds; EEGLAB keeps it in milliseconds, and eeg_checkset only
%   rebuilds it when its length is wrong, so an exported continuous
%   recording carried a seconds axis into EEGLAB.
%
%   Run with: runtests('tests/ExportSetTest.m').
%
%   See also PREPARESETEXPORT, ONEXPORTSET.

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            for p = {fullfile(root, 'src'), fullfile(root, 'src', 'IO'), ...
                     fullfile(root, 'src', 'Transformations'), fullfile(root, 'src', 'Support')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
        end

        function ensureEeglab(testCase)
            testCase.assumeTrue(~isempty(which('eeglab')), 'EEGLAB is not on the MATLAB path.');
            if isempty(which('eeg_checkset'))
                eeglab('nogui');
            end
            testCase.assumeFalse(isempty(which('pop_saveset')), 'EEGLAB is not initialised.');
        end
    end

    methods (Test)
        function aContinuousRecordingReadsBackInMilliseconds(testCase)
            EEG = ExportSetTest.continuousRecording();

            loaded = testCase.roundTrip(EEG);

            testCase.verifyEqual(loaded.times(1), 0, 'AbsTol', 1e-9);
            testCase.verifyEqual(loaded.times(end), (EEG.pnts - 1) / EEG.srate * 1000, 'AbsTol', 1e-6, ...
                'EEGLAB''s time axis is in milliseconds.');
            testCase.verifyEqual(loaded.data, EEG.data, 'The data are the data.');
        end

        function anAverageKeepsItsMillisecondAxis(testCase)
            EEG = ExportSetTest.continuousRecording();
            EEG.data = EEG.data(:, 1:250);
            EEG.pnts = 250;
            EEG.xmin = -0.2;
            EEG.xmax = EEG.xmin + (EEG.pnts - 1) / EEG.srate;
            EEG.times = (EEG.xmin + (0:EEG.pnts - 1) / EEG.srate) * 1000;
            EEG.DataFormat = 'Averaged';

            loaded = testCase.roundTrip(EEG);

            testCase.verifyEqual(loaded.times, EEG.times, 'AbsTol', 1e-6);
        end
    end

    methods (Access = private)
        function loaded = roundTrip(testCase, EEG)
            folder = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture).Folder;
            evalc('pop_saveset(prepareSetExport(EEG), ''filename'', ''export.set'', ''filepath'', folder);');
            loaded = [];
            evalc('loaded = pop_loadset(''filename'', ''export.set'', ''filepath'', folder);');
        end
    end

    methods (Static)
        function EEG = continuousRecording()
        %CONTINUOUSRECORDING  A continuous recording as Alakazam holds one:
        %   EEG.times in seconds (see loadSETFile).
            EEG = eeg_emptyset();
            rng(3);
            EEG.data = single(randn(3, 1000));
            EEG.nbchan = 3;
            EEG.pnts = 1000;
            EEG.trials = 1;
            EEG.srate = 250;
            EEG.xmin = 0;
            EEG.xmax = (EEG.pnts - 1) / EEG.srate;
            EEG.times = (0:EEG.pnts - 1) / EEG.srate;     % seconds, Alakazam's convention
            EEG.chanlocs = struct('labels', {'Fz', 'Cz', 'Pz'});
            EEG.event = struct('type', {'S1', 'S2'}, 'latency', {100, 600});
            EEG.DataFormat = 'CONTINUOUS';
            EEG.DataType = 'TIMEDOMAIN';
        end
    end
end
