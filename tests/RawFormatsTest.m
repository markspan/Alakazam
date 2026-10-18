classdef RawFormatsTest < matlab.unittest.TestCase
%RAWFORMATSTEST  The formats Alakazam opens (rawFormats) and the reader
%   chain behind the new ones (readRecording).
%
%   The registry is checked for what WorkSpace.open relies on: every loader
%   it names exists, no extension is claimed twice, the ambiguous ones are
%   claimed by none, and every format read through loadRawFile has a
%   reader and ends in the File-IO fall-back. The chain is checked with
%   stand-in readers, without EEGLAB: the first reader that returns data
%   wins, a failure moves on to the next, and when all fail the error says
%   what each one said. Two real files: an EDF written and read back, where
%   EEGLAB's BIOSIG plugin is installed, and an XDF file read by xdfimport,
%   where it is installed.
%
%   Run with: runtests('tests/RawFormatsTest.m').
%
%   See also RAWFORMATS, READRECORDING, WORKSPACE.LOADRAWFILE.

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            for p = {fullfile(root, 'src', 'IO'), fullfile(root, 'src', 'Support'), ...
                     fullfile(root, 'src'), fullfile(root, 'src', 'Transformations'), ...
                     fullfile(root, 'tests', 'fixtures')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
        end
    end

    methods (Test)
        % ---- the registry --------------------------------------------------
        function theFourOriginalFormatsKeepTheirLoaders(testCase)
            formats = rawFormats();
            expected = {'.mat', 'loadMATFile'; '.vhdr', 'loadBVAFile'; ...
                '.set', 'loadSETFile'; '.erp', 'loadERPFile'};
            for k = 1:size(expected, 1)
                f = formats(arrayfun(@(x) any(strcmp(x.extensions, expected{k, 1})), formats));
                testCase.assertNumElements(f, 1);
                testCase.verifyEqual(f.loader, expected{k, 2});
            end
        end

        function everyLoaderIsAWorkSpaceMethod(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            for f = rawFormats()
                testCase.verifyTrue(isfile(fullfile(root, 'src', '@WorkSpace', [f.loader '.m'])), ...
                    sprintf('%s names %s, which WorkSpace does not have.', f.name, f.loader));
            end
        end

        function noExtensionIsClaimedTwice(testCase)
            formats = rawFormats();
            extensions = [formats.extensions];
            testCase.verifyEqual(numel(unique(extensions)), numel(extensions));
            testCase.verifyTrue(all(startsWith(extensions, '.')));
            testCase.verifyEqual(extensions, lower(extensions));
        end

        function anAmbiguousExtensionIsClaimedByNone(testCase)
        %ANAMBIGUOUSEXTENSIONISCLAIMEDBYNONE  '.eeg' is BrainVision's data
        %   file, Nihon Kohden's recording and Neuroscan's epoched file at
        %   once; claiming it would open every BrainVision recording twice.
            formats = rawFormats();
            extensions = [formats.extensions];
            testCase.verifyFalse(any(ismember({'.eeg', '.dat', '.txt', '.csv'}, extensions)));
        end

        function everyNewFormatHasReadersEndingInFileIo(testCase)
            for f = rawFormats()
                if ~strcmp(f.loader, 'loadRawFile')
                    continue;
                end
                testCase.verifyNotEmpty(f.readers, sprintf('%s has no reader.', f.name));
                testCase.verifyEqual(f.readers(end).function, 'pop_fileio', ...
                    sprintf('%s should fall back to File-IO.', f.name));
                testCase.verifyTrue(all(arrayfun(@(r) isa(r.read, 'function_handle'), f.readers)));
            end
        end

        function theMajorFormatsAreAllThere(testCase)
            formats = rawFormats();
            extensions = [formats.extensions];
            for ext = {'.edf', '.bdf', '.gdf', '.cnt', '.mff', '.raw', '.xdf', '.trc', '.fif'}
                testCase.verifyTrue(ismember(ext{1}, extensions), sprintf('%s is not read.', ext{1}));
            end
        end

        function anEyeLinkEdfIsNotTakenForARecording(testCase)
        %ANEYELINKEDFISNOTTAKENFORARECORDING  EyeLink's '.edf' lies beside
        %   the recording for EyeTracking to join; offered as a recording of
        %   its own it would fail to read on every workspace open. The
        %   European Data Format is told apart by its header, which opens
        %   with its version, '0' and seven spaces.
            folder = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture).Folder;
            european = fullfile(folder, 'sub01.edf');
            eyelink = fullfile(folder, 'sub01eye.edf');
            writeBytes(european, [uint8('0       ') uint8('rest of the header')]);
            writeBytes(eyelink, uint8('SR_RESEARCH_COMPRESSED'));
            formats = rawFormats();
            edf = formats(arrayfun(@(f) any(strcmp(f.extensions, '.edf')), formats));

            testCase.verifyTrue(edf.accepts(european));
            testCase.verifyFalse(edf.accepts(eyelink));
        end

        % ---- the reader chain ----------------------------------------------
        function theFirstReaderThatReturnsDataWins(testCase)
            format = testCase.fakeFormat( ...
                @(path) failing('Fake:first', 'this one fails'), ...
                @(path) struct('data', ones(2, 5)), ...
                @(path) struct('data', 2 * ones(2, 5)));

            [EEG, used] = readRecording('/nowhere/rec.fake', format);

            testCase.verifyEqual(EEG.data, ones(2, 5));
            testCase.verifyEqual(used, 'num2str');
        end

        function aReaderReturningNoDataIsPassedOver(testCase)
            format = testCase.fakeFormat(@(path) struct('data', []), @(path) struct('data', 7));

            [EEG, used] = readRecording('/nowhere/rec.fake', format);

            testCase.verifyEqual(EEG.data, 7);
            testCase.verifyEqual(used, 'num2str');
        end

        function whenAllFailTheErrorSaysWhatEachSaid(testCase)
            format = testCase.fakeFormat( ...
                @(path) failing('Fake:first', 'header is corrupt'), ...
                @(path) failing('Fake:second', 'unknown file type'));

            try
                readRecording('/nowhere/rec.fake', format);
                testCase.verifyFail('Expected an error.');
            catch err
                testCase.verifyEqual(err.identifier, 'Alakazam:readRecording');
                testCase.verifySubstring(err.message, 'rec.fake');
                testCase.verifySubstring(err.message, 'header is corrupt');
                testCase.verifySubstring(err.message, 'unknown file type');
            end
        end

        function aReaderThatIsNotInstalledIsReportedAsSuch(testCase)
            format = testCase.fakeFormat(@(path) struct('data', 1));
            format.readers(1).function = 'noSuchReaderFunction_alakazam';

            try
                readRecording('/nowhere/rec.fake', format);
                testCase.verifyFail('Expected an error.');
            catch err
                testCase.verifySubstring(err.message, 'not on the path');
            end
        end

        function aFormatCanBeNamedByItsExtension(testCase)
            testCase.verifyError(@() readRecording('/nowhere/rec.xyz', '.xyz'), 'Alakazam:readRecording');
        end

        % ---- a real file ----------------------------------------------------
        function anEdfWrittenByEeglabReadsBack(testCase)
            try
                EEGLabEnvironment.ensure();
            catch
            end
            testCase.assumeTrue(exist('pop_writeeeg', 'file') == 2 && exist('sopen', 'file') == 2, ...
                'EEGLAB''s BIOSIG plugin is not installed.');
            EEG = makeScalpEEG('DataFormat', 'CONTINUOUS', 'seconds', 10, 'srate', 128, 'seed', 51);
            EEG.times = (0:EEG.pnts - 1) / EEG.srate * 1000;   % EEGLAB's own units, for its writer
            folder = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture).Folder;
            file = fullfile(folder, 'roundtrip.edf');
            pop_writeeeg(EEG, file, 'TYPE', 'EDF');

            [back, used] = readRecording(file, '.edf');

            testCase.verifyEqual(used, 'pop_biosig');
            testCase.verifyEqual(back.srate, EEG.srate);
            testCase.verifyEqual(back.nbchan, EEG.nbchan);
            testCase.verifyEqual({back.chanlocs.labels}, {EEG.chanlocs.labels});
            % EDF stores 16-bit integers scaled per channel, so the data
            % come back quantised: within one step of each channel's range.
            step = (max(EEG.data, [], 2) - min(EEG.data, [], 2)) / 65535;
            testCase.verifyLessThan(max(abs(double(back.data) - EEG.data) ./ step, [], 'all'), 2);
        end

        function anXdfIsReadByXdfimportItself(testCase)
        %ANXDFISREADBYXDFIMPORTITSELF  An EEG stream at 500 Hz beside an ECG
        %   stream at 1000 Hz, with load_xdf off the path, as it is when
        %   EEGLAB started without its menus (eeglab nogui, as Alakazam
        %   starts it, runs no plugin's hook). Still read by pop_loadxdf: the
        %   EEG stream, at its nominal rate, with its labels. File-IO, the
        %   fall-back, would keep the stream with the highest rate, the ECG.
            try
                EEGLabEnvironment.ensure();
            catch
            end
            testCase.assumeNotEmpty(which('pop_loadxdf'), 'EEGLAB''s xdfimport plugin is not installed.');
            testCase.addTeardown(@path, path);
            while ~isempty(which('load_xdf'))   % xdfimport's own, or FieldTrip's copy
                rmpath(fileparts(which('load_xdf')));
            end
            folder = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture).Folder;
            file = fullfile(folder, 'sub01.xdf');
            stream = RandStream('mt19937ar', 'Seed', 61);
            eegTimes = 100 + (0:4999) / 500;
            ecgTimes = 100 + (0:9999) / 1000;
            offsets = [(95:5:125)', zeros(7, 1)];
            writeXdf(file, struct('name', {'Amp EEG', 'Chest ECG'}, 'type', {'EEG', 'ECG'}, ...
                'labels', {{'Fz', 'Cz', 'Pz'}, {'ECG'}}, 'rate', {500, 1000}, ...
                'times', {eegTimes, ecgTimes}, 'data', {randn(stream, 3, 5000), randn(stream, 1, 10000)}, ...
                'offsets', {offsets, offsets}));

            [EEG, used] = readRecording(file, '.xdf');

            testCase.verifyEqual(used, 'pop_loadxdf');
            testCase.verifyEqual(EEG.srate, 500);
            testCase.verifyEqual({EEG.chanlocs.labels}, {'Fz', 'Cz', 'Pz'});
            testCase.verifyEqual(size(EEG.data), [3 5000]);
        end
    end

    methods (Static, Access = private)
        function format = fakeFormat(varargin)
        %FAKEFORMAT  A format whose readers are the given functions. Each is
        %   named after a MATLAB function that always exists (disp, num2str,
        %   sum, max, in order), since the chain checks a reader is on the
        %   path before calling it.
            names = {'disp', 'num2str', 'sum', 'max'};
            readers = struct('function', {}, 'backend', {}, 'plugin', {}, 'read', {});
            for k = 1:numel(varargin)
                readers(k) = struct('function', names{k}, 'backend', '', ...
                    'plugin', '', 'read', varargin{k});
            end
            format = struct('name', 'Fake format', 'extensions', {{'.fake'}}, 'isFolder', false, ...
                'loader', 'loadRawFile', 'readers', readers, 'note', '');
        end
    end
end

% ======================================================================= %
function EEG = failing(id, message)
%FAILING  A reader that fails with MESSAGE. It declares an output: an
%   anonymous @(path) error(...) does not, and asked for a dataset it fails
%   with "Too many output arguments" before error is ever reached, so the
%   chain reported that instead of the message under test.
    EEG = [];
    error(id, '%s', message);
end

function writeBytes(path, bytes)
    fid = fopen(path, 'w');
    fwrite(fid, bytes, 'uint8');
    fclose(fid);
end
