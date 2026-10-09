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
                     fullfile(root, 'src', 'Transformations'), fullfile(root, 'src', 'Support'), ...
                     fullfile(root, 'src', 'Transformations', 'DefineBins'), ...
                     fullfile(root, 'src', 'Transformations', 'Average')}
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

        function anAverageOfRealTrialsSavesWithItsBinsAsEpochs(testCase)
        %ANAVERAGEOFREALTRIALSSAVESWITHITSBINSASEPOCHS  An average made by
        %   Average from DefineBins' trials still carried the trials' own
        %   epoch records, and pop_saveset refused it: "the number of epoch
        %   indices in the epoch array/struct (233) is different from the
        %   number of epochs in the data (5)". EEGLAB reads its bins as its
        %   epochs, so that is what it gets: one epoch per bin, its event at
        %   time zero named by the bin.
            EEG = ExportSetTest.continuousRecording();
            script = ['bin 1 "First" "S1"' newline 'bin 2 "Second" "S2"' newline ...
                'bin 3 "Second minus first" = bin 2 - bin 1' newline 'epoch [-200,800] ms'];
            epoched = [];
            evalc('epoched = DefineBins(EEG, struct(''script'', script));');
            average = [];
            evalc('average = Average(epoched);');
            testCase.assertEqual(size(average.data, 3), 3);

            loaded = testCase.roundTrip(average);

            testCase.verifyEqual(loaded.trials, 3, 'One epoch per bin.');
            testCase.verifyEqual(double(loaded.data), double(average.data), 'AbsTol', 1e-5);
            testCase.verifyEqual(loaded.times, average.times, 'AbsTol', 1e-6);
            types = arrayfun(@(e) char(string(e.eventtype)), loaded.epoch, 'UniformOutput', false);
            testCase.verifyEqual(types, {'First', 'Second', 'Second minus first'});
            latencies = arrayfun(@(e) double(e.eventlatency), loaded.epoch);
            testCase.verifyEqual(latencies, [0 0 0], 'AbsTol', 1000 / EEG.srate, ...
                'Each bin''s event sits at its time zero.');
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
