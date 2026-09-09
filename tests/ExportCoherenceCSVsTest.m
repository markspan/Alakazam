classdef ExportCoherenceCSVsTest < matlab.unittest.TestCase
%EXPORTCOHERENCECSVSTEST  The RIFT figure, as data rather than a screenshot.
%
%   Until this exporter, a CoherenceMap result could be looked at in the app
%   and nowhere else: exportGrandAveragesCSV skips it explicitly because
%   "its real content is the .ersp / .coherence map", and nothing else wrote
%   it. So the figure a tagging paper is built on could only leave Alakazam
%   as a screenshot.
%
%   THE FIXTURE HAS A KNOWN ANSWER. Coherence is built as a bump at a known
%   frequency, in a known time window, strongest at known channels, so
%   every claim the exporter makes can be checked rather than merely
%   observed: the tag it finds, the channels it picks, the values it
%   writes, and the row counts that decide whether this is a 1 MB file or a
%   37 MB one.
%
%   Run with: runtests('tests/ExportCoherenceCSVsTest.m').
%
%   See also EXPORTCOHERENCECSVS, COHERENCEMAP.

    properties (Constant)
        TagHz = 60      % the planted tagging frequency
        Strong = [2 5]  % the channels given the largest response
    end

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            for p = {fullfile(root, 'src', 'IO'), fullfile(root, 'src', 'Support'), ...
                     fullfile(root, 'src', 'Transformations')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
        end
    end

    methods (Test)
        function theTagIsFoundInTheDataNotAssumed(testCase)
        %THETAGISFOUNDINTHEDATANOTASSUMED  The tag column must carry the
        %   planted frequency. Reading it off the map is what keeps it from
        %   drifting away from a number typed somewhere else.
            [trace, ~] = testCase.exportFixture();
            tags = unique(trace.tag_hz);

            testCase.verifyEqual(numel(tags), 1, 'One bin, so one tag.');
            testCase.verifyEqual(tags(1), testCase.TagHz, 'AbsTol', 1e-9);
        end

        function theTraceCoversEveryChannel(testCase)
        %THETRACECOVERSEVERYCHANNEL  The point of splitting the files: the
        %   cheap one holds all channels, so no channel is invisible.
            [trace, ~] = testCase.exportFixture();
            testCase.verifyEqual(numel(unique(trace.channel)), 6);
        end

        function theMapIsRestrictedToTheStrongestChannels(testCase)
        %THEMAPISRESTRICTEDTOTHESTRONGESTCHANNELS  The expensive file is the
        %   one that has to be scoped, and by response is what a figure does.
            [~, map] = testCase.exportFixture(struct('MaxChannels', 2));
            channels = unique(map.channel);

            testCase.verifyEqual(numel(channels), 2);
            testCase.verifyEqual(sort(channels), {'E2'; 'E5'}, ...
                'The two planted strong channels should have been picked.');
        end

        function anExplicitChannelListOverridesTheData(testCase)
        %ANEXPLICITCHANNELLISTOVERRIDESTHEDATA  An analyst who names their
        %   montage is never overruled by which channel happened to respond.
            [~, map] = testCase.exportFixture(struct('Channels', {{'E1'}}));
            testCase.verifyEqual(unique(map.channel), {'E1'});
        end

        function theValuesAreTheMapsOwn(testCase)
        %THEVALUESARETHEMAPSOWN  Not merely the right shape: the number in
        %   the file has to be the number in the array.
            [eeg, entry] = testCase.fixture();
            folder = testCase.tempFolder();
            exportCoherenceCSVs(entry, fullfile(folder, 'x'), struct('Channels', {{'E2'}}));

            map = readtable(fullfile(folder, 'x_coherence_map.csv'), ...
                'TextType', 'string', 'VariableNamingRule', 'preserve');
            fIdx = find(abs(eeg.cohFreqs - testCase.TagHz) < 1e-9, 1);
            tIdx = 3;
            expected = eeg.coherence(2, fIdx, tIdx, 1);

            row = map(abs(map.frequency_hz - testCase.TagHz) < 1e-9 & ...
                      abs(map.time_ms - eeg.cohTimes(tIdx)) < 1e-9, :);
            testCase.assertEqual(height(row), 1, 'That cell should appear exactly once.');
            testCase.verifyEqual(row.coherence(1), expected, 'AbsTol', 1e-9);
        end

        function theRowCountsAreWhatTheDesignPromises(testCase)
        %THEROWCOUNTSAREWHATTHEDESIGNPROMISES  The whole reason for two
        %   files. Trace is channels x times x bins; map is only the chosen
        %   channels x frequencies x times x bins. If these ever converge,
        %   the split has quietly stopped working and the file is heading
        %   back towards 37 MB a subject.
            [eeg, entry] = testCase.fixture();
            folder = testCase.tempFolder();
            exportCoherenceCSVs(entry, fullfile(folder, 'x'), struct('MaxChannels', 2));

            [nChan, nFreq, nTime, nBin] = size(eeg.coherence);
            trace = readtable(fullfile(folder, 'x_coherence_trace.csv'), ...
                'VariableNamingRule', 'preserve');
            map = readtable(fullfile(folder, 'x_coherence_map.csv'), ...
                'VariableNamingRule', 'preserve');

            testCase.verifyEqual(height(trace), nChan * nTime * nBin);
            testCase.verifyEqual(height(map), 2 * nFreq * nTime * nBin);
            testCase.verifyLessThan(height(map), nChan * nFreq * nTime * nBin, ...
                'The map must be smaller than the unscoped one it replaces.');
        end

        function anEntryWithNoMapContributesNothing(testCase)
        %ANENTRYWITHNOMAPCONTRIBUTESNOTHING  A workspace holds all kinds of
        %   results; only the ones carrying a map belong in these files.
            [~, entry] = testCase.fixture();
            bare = entry;
            bare.EEG = rmfield(bare.EEG, 'coherence');
            folder = testCase.tempFolder();

            exportCoherenceCSVs(bare, fullfile(folder, 'x'));

            trace = readtable(fullfile(folder, 'x_coherence_trace.csv'), ...
                'VariableNamingRule', 'preserve');
            testCase.verifyEqual(height(trace), 0, ...
                'Only the header should have been written.');
        end
    end

    methods (Access = private)
        function folder = tempFolder(testCase)
            folder = testCase.applyFixture( ...
                matlab.unittest.fixtures.TemporaryFolderFixture()).Folder;
        end

        function [eeg, entry] = fixture(testCase)
        %FIXTURE  A coherence map with a planted tag, window and topography.
            nChan = 6;
            freqs = 55:1:65;
            times = linspace(-200, 800, 9);
            nFreq = numel(freqs);
            nTime = numel(times);

            coh = 0.05 * ones(nChan, nFreq, nTime);
            fIdx = find(freqs == testCase.TagHz, 1);
            inWindow = times > 0 & times < 600;
            for c = 1:nChan
                strength = 0.2;
                if any(c == testCase.Strong)
                    strength = 0.8;
                end
                coh(c, fIdx, inWindow) = strength;
            end

            eeg = struct();
            eeg.coherence = coh;
            eeg.cohFreqs = freqs;
            eeg.cohTimes = times;
            eeg.chanlocs = struct('labels', ...
                arrayfun(@(k) sprintf('E%d', k), 1:nChan, 'UniformOutput', false));
            eeg.bindesc = struct('label', {'Tagged'}, 'index', {1});

            entry = struct('subject', 'sub01', 'datasetType', 'subject', ...
                'group', '', 'person', 'p01', 'session', '', 'EEG', eeg);
        end

        function [trace, map] = exportFixture(testCase, opts)
            if nargin < 2
                opts = struct();
            end
            [~, entry] = testCase.fixture();
            folder = testCase.tempFolder();
            exportCoherenceCSVs(entry, fullfile(folder, 'x'), opts);

            trace = readtable(fullfile(folder, 'x_coherence_trace.csv'), ...
                'TextType', 'string', 'VariableNamingRule', 'preserve');
            map = readtable(fullfile(folder, 'x_coherence_map.csv'), ...
                'TextType', 'string', 'VariableNamingRule', 'preserve');
            trace.channel = cellstr(trace.channel);
            map.channel = cellstr(map.channel);
        end
    end
end
