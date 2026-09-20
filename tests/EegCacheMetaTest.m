classdef EegCacheMetaTest < matlab.unittest.TestCase
%EEGCACHEMETATEST  The small record kept beside every cache node, and the
%   activations the node no longer carries.
%
%   Replaying a branch onto a dozen recordings used to load every step of the
%   source branch in full, about 1.7 GB per target on the RIFT chain, to read
%   two small fields from each. saveEegCache now writes those fields to
%   <node>.mat.meta and readEegCacheMeta reads them back, falling back to a
%   full load only for a node that has no fresh record. These tests pin what
%   that record must hold, that it is trusted only while it is at least as new
%   as the node, and that a copy of a dataset's options taken from it match the
%   ones taken from the dataset itself.
%
%   Run with: runtests('tests/EegCacheMetaTest.m').
%
%   See also SAVEEEGCACHE, READEEGCACHEMETA, EEGCACHEMETA.

    properties
        Folder
    end

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(root, 'src')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(root, 'src', 'Support')));
        end
    end

    methods (TestMethodSetup)
        function makeFolder(testCase)
            testCase.Folder = testCase.applyFixture( ...
                matlab.unittest.fixtures.TemporaryFolderFixture).Folder;
        end
    end

    methods (Test)
        function savingWritesBothRecordsAndParamsComeBackExactly(testCase)
        %SAVINGWRITESBOTHRECORDSANDPARAMSCOMEBACKEXACTLY  Through JSON these would
        %   not: a row vector returns as a column and a cell array of structs as
        %   a struct array, which is why the record is a MAT file.
            file = fullfile(testCase.Folder, 'n.mat');
            EEG = testCase.dataset();
            saveEegCache(file, EEG);

            testCase.verifyTrue(isfile([file '.json']));
            testCase.verifyTrue(isfile([file '.meta']));
            meta = readEegCacheMeta(file);
            testCase.verifyEqual(meta.Call, 'Filter');
            testCase.verifyTrue(isequal(meta.params, EEG.params), ...
                'params must come back exactly as they went in.');
            testCase.verifyEqual(meta.id, 'Filter');
            testCase.verifyEqual(meta.dataSize, [3 10]);
            testCase.verifyEqual(meta.timeRange, [-200 700]);
        end

        function theMetaRecordIsNotTakenForAnotherNode(testCase)
        %THEMETARECORDISNOTTAKENFORANOTHERNODE  The tree finds a node's children by
        %   listing *.mat, so the record must not end in .mat.
            file = fullfile(testCase.Folder, 'n.mat');
            saveEegCache(file, testCase.dataset());

            listed = {dir(fullfile(testCase.Folder, '*.mat')).name};
            testCase.verifyEqual(listed, {'n.mat'});
        end

        function theSavedNodeLeavesOutTheActivationsButTheCallersCopyKeepsThem(testCase)
            file = fullfile(testCase.Folder, 'n.mat');
            EEG = testCase.dataset();
            EEG.icaact = rand(2, 10);
            saveEegCache(file, EEG);

            loaded = load(file, 'EEG');
            testCase.verifyEmpty(loaded.EEG.icaact, ...
                'icaact is derived from weights, sphere and data, and doubles the file.');
            testCase.verifyEqual(size(EEG.icaact), [2 10], ...
                'The caller''s dataset must not be changed by saving it.');
        end

        function aFreshRecordIsReadWithoutLoadingTheNode(testCase)
        %AFRESHRECORDISREADWITHOUTLOADINGTHENODE  Proved by planting a value in the
        %   record that the node does not hold: only a read of the record returns it.
            file = fullfile(testCase.Folder, 'n.mat');
            saveEegCache(file, testCase.dataset());
            meta = readEegCacheMeta(file);
            meta.Call = 'PlantedInTheRecord';
            save([file '.meta'], 'meta', '-mat');

            testCase.verifyEqual(readEegCacheMeta(file).Call, 'PlantedInTheRecord');
        end

        function aNodeSavedAfterItsRecordIsReReadAndTheRecordHealed(testCase)
            file = fullfile(testCase.Folder, 'n.mat');
            EEG = testCase.dataset();
            saveEegCache(file, EEG);
            pause(1.1);                        % the record must be strictly older
            EEG.Call = 'Changed';
            save(file, 'EEG');                 % a route that does not write the record

            testCase.verifyEqual(readEegCacheMeta(file).Call, 'Changed');
            recorded = load([file '.meta'], '-mat', 'meta');
            testCase.verifyEqual(recorded.meta.Call, 'Changed', ...
                'Reading a stale record should have rewritten it.');
        end

        function aMissingOrCorruptRecordIsHealed(testCase)
            file = fullfile(testCase.Folder, 'n.mat');
            saveEegCache(file, testCase.dataset());

            delete([file '.meta']);
            testCase.verifyEqual(readEegCacheMeta(file).Call, 'Filter');
            testCase.verifyTrue(isfile([file '.meta']), 'A missing record should be written.');

            fid = fopen([file '.meta'], 'w');
            fwrite(fid, 'this is not a MAT file');
            fclose(fid);
            testCase.verifyEqual(readEegCacheMeta(file).Call, 'Filter');
        end

        function aStandInBuiltFromTheRecordGivesTheSameTreeOptions(testCase)
        %ASTANDINBUILTFROMTHERECORDGIVESTHESAMETREEOPTIONS  The workspace and the
        %   grand-average scans use a stand-in for the dataset, so it has to
        %   answer WorkSpaceTree.optsFor exactly as the dataset would.
            averaged = testCase.dataset();
            averaged.Call = 'Average';
            averaged.DataFormat = 'Averaged';

            grand = averaged;
            grand.etc.GrandAverage = struct('sources', {{'a.mat', 'b.mat'}}, ...
                'weighted', false, 'nSubjects', 2, 'kind', 'erp');

            rejected = testCase.dataset();
            rejected.etc.alz.artefactDetectors = struct('names', {{'x'}});

            continuous = testCase.dataset();
            continuous.DataFormat = 'CONTINUOUS';

            variants = {averaged, grand, rejected, continuous};
            for k = 1:numel(variants)
                file = fullfile(testCase.Folder, sprintf('v%d.mat', k));
                saveEegCache(file, variants{k});
                proxy = eegProxyFromCacheMeta(readEegCacheMeta(file));
                testCase.verifyEqual(WorkSpaceTree.optsFor(proxy), WorkSpaceTree.optsFor(variants{k}), ...
                    sprintf('Variant %d.', k));
            end
        end

        function aGrandAverageProxyCarriesItsSourcesAndDesignCell(testCase)
            grand = testCase.dataset();
            grand.etc.GrandAverage = struct('sources', {{'a.mat', 'b.mat'}}, ...
                'weighted', true, 'nSubjects', 2, 'kind', 'erp');
            grand.etc.DesignCell = struct('group', 'G1', 'session', 'S2');
            file = fullfile(testCase.Folder, 'ga.mat');
            saveEegCache(file, grand);

            proxy = eegProxyFromCacheMeta(readEegCacheMeta(file));
            testCase.verifyEqual(proxy.etc.GrandAverage.sources, {'a.mat', 'b.mat'});
            testCase.verifyTrue(proxy.etc.GrandAverage.weighted);
            testCase.verifyEqual(proxy.etc.DesignCell.group, 'G1');
        end
    end

    methods (Access = private)
        function EEG = dataset(~)
            EEG = struct('data', rand(3, 10), 'times', linspace(-200, 700, 10), ...
                'Call', 'Filter', 'id', 'Filter', 'DataFormat', 'EPOCHED', ...
                'params', struct('highpass', struct('enabled', true, 'freq', 1), ...
                    'rows', {{struct('x', 1), struct('x', 2)}}, 'list', [1 2 3]), ...
                'etc', struct());
        end
    end
end
