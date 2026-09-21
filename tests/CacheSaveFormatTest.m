classdef CacheSaveFormatTest < matlab.unittest.TestCase
%CACHESAVEFORMATTEST  How cache files are written: uncompressed, and in the
%   fastest MAT format their size allows.
%
%   WHY THIS EXISTS. Saving cache files was measured, by the person using
%   the application, as the main cost of working in it. The cause was
%   compression: on a real 543 MB node it made a save take 11.2 s instead of
%   1.1 s, and a load 2.7 s instead of 0.2 s, to make the file a tenth
%   smaller. EEG is noisy floating point and does not compress, so that was
%   nearly all cost. See cacheSaveFormat.
%
%   The cases read the written file's own header rather than trusting what
%   save() was asked for, because the property that matters is what is on
%   disk. And one case checks that the header probe really does tell a
%   compressed file from an uncompressed one; without it, a probe that
%   always answered "uncompressed" would make every other case here pass.
%
%   Run with: runtests('tests/CacheSaveFormatTest.m').

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            here = fileparts(mfilename('fullpath'));
            root = fileparts(here);
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'Support')));
        end
    end

    methods (Test)
        % ---- the choice itself -------------------------------------------
        function aNormalNodeIsVersion7Uncompressed(testCase)
            testCase.verifyEqual(cacheSaveFormat(543e6), {'-v7', '-nocompression'});
        end

        function aNodeTooLargeForVersion7FallsBackTo73(testCase)
        %ANODETOOLARGEFORVERSION7FALLSBACKTO73  Version 7 cannot hold a
        %   variable of 2 GB or more, and a long high-density recording does
        %   cross that line. Still uncompressed.
            testCase.verifyEqual(cacheSaveFormat(3e9), {'-v7.3', '-nocompression'});
        end

        function theThresholdLeavesAMarginUnderTheLimit(testCase)
        %THETHRESHOLDLEAVESAMARGINUNDERTHELIMIT  whos reports the size in
        %   memory and the file adds headers, so something just under 2^31
        %   must not be sent to a format that will refuse it.
            testCase.verifyEqual(cacheSaveFormat(2^31 - 1e6), {'-v7.3', '-nocompression'});
            testCase.verifyEqual(cacheSaveFormat(1e9), {'-v7', '-nocompression'});
        end

        function noSizeIsEverCompressed(testCase)
            for bytes = [0, 1e3, 1e8, 1.8e9, 1.95e9, 5e9]
                testCase.verifyTrue(any(strcmp(cacheSaveFormat(bytes), '-nocompression')), ...
                    sprintf('%g bytes would be written compressed.', bytes));
            end
        end

        % ---- what actually reaches the disk ------------------------------
        function theProbeTellsCompressedFromUncompressed(testCase)
        %THEPROBETELLSCOMPRESSEDFROMUNCOMPRESSED  The guard on the cases
        %   below. Write the same thing both ways with save() directly and
        %   check the probe disagrees about them.
            folder = testCase.tempFolder();
            EEG = CacheSaveFormatTest.smallEEG(); %#ok<NASGU>

            compressedFile = fullfile(folder, 'compressed.mat');
            save(compressedFile, 'EEG', '-v7');
            plainFile = fullfile(folder, 'plain.mat');
            save(plainFile, 'EEG', '-v7', '-nocompression');

            [~, compressed] = CacheSaveFormatTest.matFormat(compressedFile);
            [~, plain] = CacheSaveFormatTest.matFormat(plainFile);

            testCase.assertTrue(compressed, 'The probe did not see a compressed file as compressed.');
            testCase.assertFalse(plain, 'The probe saw an uncompressed file as compressed.');
        end

        function aCacheFileIsWrittenUncompressed(testCase)
            folder = testCase.tempFolder();
            file = fullfile(folder, 'node.mat');

            saveEegCache(file, CacheSaveFormatTest.smallEEG());

            [isV73, compressed] = CacheSaveFormatTest.matFormat(file);
            testCase.verifyFalse(isV73, 'A small node should be version 7, the fastest format.');
            testCase.verifyFalse(compressed, 'The cache file was written compressed.');
        end

        function aFormatFlagFromTheCallerIsIgnored(testCase)
        %AFORMATFLAGFROMTHECALLERISIGNORED  The importers used to pass
        %   '-v7.3' unconditionally. save() refuses two formats at once, so
        %   the flag has to be dropped rather than added to, and the size
        %   check decides instead.
            folder = testCase.tempFolder();
            file = fullfile(folder, 'node.mat');

            saveEegCache(file, CacheSaveFormatTest.smallEEG(), '-v7.3');

            [isV73, compressed] = CacheSaveFormatTest.matFormat(file);
            testCase.verifyFalse(isV73, 'A passed-in -v7.3 should not override the size check.');
            testCase.verifyFalse(compressed);
        end

        function whatIsSavedIsWhatIsLoaded(testCase)
            folder = testCase.tempFolder();
            file = fullfile(folder, 'node.mat');
            original = CacheSaveFormatTest.smallEEG();

            saveEegCache(file, original);
            loaded = load(file, 'EEG');

            testCase.verifyEqual(loaded.EEG.data, original.data);
            testCase.verifyEqual(loaded.EEG.srate, original.srate);
        end

        function anOldCompressedCacheFileStillLoads(testCase)
        %ANOLDCOMPRESSEDCACHEFILESTILLLOADS  Every cache tree built before
        %   this change is compressed. Nothing converts it, and nothing has
        %   to: load() reads whichever format a file is in.
            folder = testCase.tempFolder();
            file = fullfile(folder, 'old.mat');
            EEG = CacheSaveFormatTest.smallEEG();
            save(file, 'EEG', '-v7');   % the old way

            loaded = load(file, 'EEG');

            testCase.verifyEqual(loaded.EEG.data, EEG.data);
        end
    end

    methods (Access = private)
        function folder = tempFolder(testCase)
            folder = testCase.applyFixture( ...
                matlab.unittest.fixtures.TemporaryFolderFixture()).Folder;
        end
    end

    methods (Static, Access = private)
        function EEG = smallEEG()
            EEG = struct('data', single(randn(4, 2000)), 'srate', 500, ...
                'nbchan', 4, 'pnts', 2000, 'trials', 1, 'times', (0:1999) * 2, ...
                'event', struct('type', {}, 'latency', {}), ...
                'chanlocs', struct('labels', {'Fz', 'Cz', 'Pz', 'Oz'}), ...
                'DataType', 'TIMEDOMAIN', 'DataFormat', 'CONTINUOUS', ...
                'id', 'Test', 'Call', 'Test', 'params', struct(), ...
                'File', '', 'icaact', []);
        end

        function [isV73, compressed] = matFormat(file)
        %MATFORMAT  Read a MAT-file's header to see how it was written.
        %   A version 7.3 file names itself "7.3" in the text header. In a
        %   version 6/7 file the first data element's tag, at byte 128, is 14
        %   (miMATRIX) for a variable stored as is and 15 (miCOMPRESSED) for
        %   one stored compressed.
            fid = fopen(file, 'r', 'l');
            closer = onCleanup(@() fclose(fid)); %#ok<NASGU>
            header = fread(fid, 116, 'uint8=>char')';
            isV73 = contains(header, '7.3');
            compressed = false;
            if ~isV73
                fseek(fid, 128, 'bof');
                tag = fread(fid, 1, 'uint32');
                compressed = (tag == 15);
            end
        end
    end
end
