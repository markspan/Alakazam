classdef GrandAverageSourcesTest < matlab.unittest.TestCase
%GRANDAVERAGESOURCESTEST  A grand average kept consistent with the tree it
%   was made from.
%
%   A grand average is a fixed list of datasets, computed once.
%   Recalculating one of them refreshes it; deleting one used to leave it
%   with its old numbers and nothing to say so, and ERP & Report drew every
%   grand average in the tree, so a report on one pipeline showed the
%   waveforms of another, made from branches deleted since. These cases hold
%   the plain functions that keep it consistent: which grand averages a
%   branch feeds (asked before Delete and a move), which ones a report may
%   draw, and the label that says when sources were deleted.
%
%   Each case builds a small cache on disk: recordings s1, s2 and s3, each
%   with an Average and a Measure on it, and grand averages recording their
%   sources as saveGrandAverage does.
%
%   Run with: runtests('tests/GrandAverageSourcesTest.m').
%
%   See also GRANDAVERAGESUSING, GRANDAVERAGESFORREPORT, GRANDAVERAGELABEL,
%   MARKGRANDAVERAGESOURCES, BRANCHCACHEFILES.

    properties
        Cache       % the cache folder
        Average     % containers.Map: recording -> its Average's file
        Measure     % containers.Map: recording -> the Measure on that Average
    end

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            for p = {fullfile(root, 'src'), fullfile(root, 'src', 'Support'), ...
                     fullfile(root, 'src', 'Reports'), fullfile(root, 'tests', 'fixtures')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
        end
    end

    methods (TestMethodSetup)
        function makeCache(testCase)
            testCase.Cache = testCase.applyFixture( ...
                matlab.unittest.fixtures.TemporaryFolderFixture).Folder;
            testCase.Average = containers.Map();
            testCase.Measure = containers.Map();
            for s = {'s1', 's2', 's3'}
                saveEegCache(fullfile(testCase.Cache, [s{1} '.mat']), dataset(s{1}));
                average = fullfile(testCase.Cache, s{1}, 'Average01.mat');
                measure = fullfile(testCase.Cache, s{1}, 'Average01', 'Measure01.mat');
                mkdir(fileparts(measure));
                saveEegCache(average, dataset('Average'));
                saveEegCache(measure, dataset('Measure'));
                testCase.Average(s{1}) = average;
                testCase.Measure(s{1}) = measure;
            end
            mkdir(fullfile(testCase.Cache, 'GrandAverages'));
        end
    end

    methods (Test)
        function aBranchIsItsFileAndEverythingUnderIt(testCase)
            files = branchCacheFiles(testCase.Average('s1'));

            testCase.verifyEqual(files, {testCase.Average('s1'), testCase.Measure('s1')});
            testCase.verifyEqual(branchCacheFiles(testCase.Measure('s1')), {testCase.Measure('s1')});
        end

        function theGrandAveragesABranchFeedsAreNamed(testCase)
            ga = testCase.grandAverage('ga', {'s1', 's2'});
            other = testCase.grandAverage('other', {'s3'});
            nodes = [node('g1', 'ga', ga, true), node('g2', 'other', other, true), ...
                node('g3', 'Measure', fullfile(fileparts(ga), 'ga', 'Measure01.mat'), false)];

            testCase.verifyEqual(grandAveragesUsing(nodes, branchCacheFiles(testCase.Average('s1'))), {'ga'});
            testCase.verifyEqual(grandAveragesUsing(nodes, branchCacheFiles(testCase.Average('s3'))), {'other'});
            testCase.verifyEmpty(grandAveragesUsing(nodes, {testCase.Measure('s2')}), ...
                'A step computed from a source is not a source.');
            if ispc
                testCase.verifyEqual(grandAveragesUsing(nodes, {upper(testCase.Average('s2'))}), {'ga'}, ...
                    'Windows paths compare whatever their case.');
            end
            testCase.verifyEmpty(grandAveragesUsing([], {testCase.Average('s1')}));
        end

        function aReportDrawsOnlyTheGrandAveragesOfWhatItMeasured(testCase)
        %AREPORTDRAWSONLYTHEGRANDAVERAGESOFWHATITMEASURED  The measurements
        %   are Measure nodes; a grand average belongs when every one of its
        %   sources has one in its branch.
            both = testCase.grandAverage('both', {'s1', 's2'});
            third = testCase.grandAverage('third', {'s3'});
            nodes = [node('g1', 'both', both, true), node('g2', 'third', third, true)];
            measured = {testCase.Measure('s1'), testCase.Measure('s2')};

            kept = grandAveragesForReport(nodes, measured);

            testCase.verifyEqual({kept.Id}, {'g1'}, 'Only the grand average of the measured datasets.');
            testCase.verifyEmpty(grandAveragesForReport(nodes, {testCase.Measure('s1')}), ...
                'A grand average with an unmeasured source is another analysis.');
            testCase.verifyEmpty(grandAveragesForReport([], measured));
        end

        function aGrandAverageWithADeletedSourceIsNotDrawn(testCase)
            both = testCase.grandAverage('both', {'s1', 's2'});
            nodes = node('g1', 'both', both, true);
            measured = {testCase.Measure('s1'), testCase.Measure('s2')};
            delete(testCase.Average('s2'));

            testCase.verifyEmpty(grandAveragesForReport(nodes, measured));
        end

        function aMeasuredGrandAverageIsDrawn(testCase)
            ga = testCase.grandAverage('ga', {'s1', 's2'});
            measureOnIt = fullfile(fileparts(ga), 'ga', 'Measure01.mat');

            kept = grandAveragesForReport(node('g1', 'ga', ga, true), {measureOnIt});

            testCase.verifyEqual({kept.Id}, {'g1'});
        end

        function theLabelSaysWhenSourcesWereDeleted(testCase)
            ga = testCase.grandAverage('ga', {'s1', 's2'});
            testCase.verifyEqual(grandAverageLabel(ga), 'ga');

            delete(testCase.Average('s2'));
            testCase.verifyEqual(grandAverageLabel(ga), 'ga (1 of 2 sources deleted)');

            delete(testCase.Average('s1'));
            testCase.verifyEqual(grandAverageLabel(ga), 'ga (sources deleted)');
        end

        function markingRelabelsOnlyWhatChanged(testCase)
            ga = testCase.grandAverage('ga', {'s1', 's2'});
            tree = FakeTree();
            tree.Nodes = [node('g1', 'ga', ga, true), ...
                node('g2', 'Filter', fullfile(fileparts(ga), 'ga', 'Filter01.mat'), false)];

            markGrandAverageSources(tree);
            testCase.verifyEmpty(tree.Renamed, 'Nothing was deleted, so nothing is relabelled.');

            delete(testCase.Average('s1'));
            markGrandAverageSources(tree);
            testCase.verifyEqual(tree.Renamed, {'g1', 'ga (1 of 2 sources deleted)'});

            markGrandAverageSources(tree);
            testCase.verifyEqual(size(tree.Renamed, 1), 1, 'A label already right is left alone.');
        end

        function theWaveformExportNamesAGrandAverageByItsNameNotItsLabel(testCase)
            ga = testCase.grandAverage('ga', {'s1', 's2'});
            EEG = gaEEG('ga', {testCase.Average('s1'), testCase.Average('s2')});
            save(ga, 'EEG');
            csv = fullfile(testCase.Cache, 'ga.csv');

            exportGrandAveragesCSV(node('g1', 'ga (1 of 2 sources deleted)', ga, true), csv);

            names = unique(ReportFixtures.csvColumn(csv, 'grand_average'));
            testCase.verifyEqual(names, {'ga'});
        end
    end

    methods (Access = private)
        function file = grandAverage(testCase, name, recordings)
        %GRANDAVERAGE  A grand average made from RECORDINGS' Averages, saved
        %   with its record as saveGrandAverage writes one.
            file = fullfile(testCase.Cache, 'GrandAverages', [name '.mat']);
            sources = cellfun(@(r) testCase.Average(r), recordings, 'UniformOutput', false);
            saveEegCache(file, gaEEG(name, sources));
        end
    end
end

% ======================================================================= %
function EEG = dataset(id)
    EEG = struct('id', id, 'data', zeros(2, 4), 'DataFormat', 'AVERAGED', ...
        'times', 1:4, 'etc', struct());
end

function EEG = gaEEG(name, sources)
%GAEEG  A grand average's dataset: one bin, two channels.
    EEG = dataset(name);
    EEG.data = zeros(2, 4, 1);
    EEG.nbchan = 2;
    EEG.trials = 1;
    EEG.chanlocs = struct('labels', {'Cz', 'Pz'});
    EEG.bindesc = struct('label', 'Target', 'n', '2 subjects');
    EEG.etc.GrandAverage = struct('sources', {sources}, 'weighted', false, ...
        'nSubjects', numel(sources), 'kind', 'erp');
end

function n = node(id, name, file, isRoot)
    n = struct('Id', id, 'Name', name, 'UserData', file, 'IsRoot', isRoot);
end
