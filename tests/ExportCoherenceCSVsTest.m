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
        WrongHz = 58    % a neighbouring frequency most channels are noisy at
    end

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            for p = {fullfile(root, 'src', 'Reports'), fullfile(root, 'src', 'Support'), ...
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

        function theTagPrefersTheReferencesOwnPowerOverNoisyChannelAverage(testCase)
        %THETAGPREFERSTHEREFERENCESOWNPOWEROVERNOISYCHANNELAVERAGE  Reported
        %   directly: with several RIFT/SSVEP conditions tagged at
        %   different true frequencies, averaging coherence over every EEG
        %   channel picked the same wrong frequency for two different
        %   conditions. This fixture reproduces that shape -- most
        %   channels carry a small bump at a WRONG frequency (noise/a
        %   neighbouring tag) and only one at the TRUE one, so the
        %   channel-averaged read-out this test pins as wrong would land
        %   on the wrong frequency -- and checks that cohRefPower (the
        %   reference's own clean spectrum) overrides it.
            [~, entry] = testCase.fixtureWithMisleadingChannelAverage();
            folder = testCase.tempFolder();
            exportCoherenceCSVs(entry, fullfile(folder, 'x'));

            trace = readtable(fullfile(folder, 'x_coherence_trace.csv'), ...
                'VariableNamingRule', 'preserve');
            tags = unique(trace.tag_hz);

            testCase.assertEqual(numel(tags), 1, 'One bin, so one tag.');
            testCase.verifyEqual(tags(1), testCase.TagHz, 'AbsTol', 1e-9, ...
                sprintf(['The exporter read off the channel-averaged coherence (which peaks ' ...
                'at %g Hz here) instead of the reference''s own power (which correctly ' ...
                'peaks at %g Hz).'], testCase.WrongHz, testCase.TagHz));
        end

        function anOlderResultWithNoRefPowerStillFallsBackCorrectly(testCase)
        %ANOLDERRESULTWITHNOREFPOWERSTILLFALLSBACKCORRECTLY  cohRefPower
        %   did not always exist; a cached result computed before it did
        %   must still render, using the channel-averaged read-out exactly
        %   as before.
            [~, entry] = testCase.fixtureWithMisleadingChannelAverage();
            entry.EEG = rmfield(entry.EEG, 'cohRefPower');
            folder = testCase.tempFolder();
            exportCoherenceCSVs(entry, fullfile(folder, 'x'));

            trace = readtable(fullfile(folder, 'x_coherence_trace.csv'), ...
                'VariableNamingRule', 'preserve');
            tags = unique(trace.tag_hz);

            testCase.assertEqual(numel(tags), 1, 'One bin, so one tag.');
            testCase.verifyEqual(tags(1), testCase.WrongHz, 'AbsTol', 1e-9, ...
                'Without cohRefPower the exporter should fall back to the channel average.');
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
        %ANEXPLICITCHANNELLISTOVERRIDESTHEDATA  A user who names their
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

        function theTraceCarriesTheTrialCountBehindEachCondition(testCase)
        %THETRACECARRIESTHETRIALCOUNTBEHINDEACHCONDITION  The coherence of N
        %   independent trials is 1/N by chance, so a coherence is
        %   uninterpretable without the N beside it.
            [~, entry] = testCase.fixture();
            entry.EEG.bindesc = struct('label', {'Tagged'}, 'index', {1}, 'trials', {1:14});
            folder = testCase.tempFolder();
            exportCoherenceCSVs(entry, fullfile(folder, 'x'));

            trace = readtable(fullfile(folder, 'x_coherence_trace.csv'), ...
                'VariableNamingRule', 'preserve', 'TreatAsMissing', 'NA');
            testCase.verifyEqual(unique(trace.n_trials), 14);
        end

        function aDatasetThatDoesNotSayHowManyTrialsIsMissingNotZero(testCase)
            [trace, ~] = testCase.exportFixture();
            testCase.verifyTrue(all(isnan(trace.n_trials)), ...
                'Without bindesc.trials the count is unknown, and unknown is not zero.');
        end

        function theReferenceFileHoldsTheSpectrumTheBandAndThePeak(testCase)
        %THEREFERENCEFILEHOLDSTHESPECTRUMTHEBANDANDTHEPEAK  A 30 Hz reference
        %   peak under a 55 to 65 Hz band: exactly the SSVEP-among-RIFT case
        %   the file exists to expose.
            [~, entry] = testCase.fixture();
            entry.EEG.bindesc = struct('label', {'Tagged'}, 'index', {1}, 'trials', {1:20});
            specFreqs = 0:0.25:150;
            spec = 1e-3 * ones(numel(specFreqs), 1);
            spec(specFreqs == 30) = 9;
            entry.EEG.cohRefSpectrum = single(spec);
            entry.EEG.cohRefSpecFreqs = specFreqs;
            entry.EEG.cohRefPeakHz = 29.94;
            folder = testCase.tempFolder();

            [~, ~, ~, referenceFile] = exportCoherenceCSVs(entry, fullfile(folder, 'x'));

            ref = readtable(referenceFile, 'VariableNamingRule', 'preserve');
            testCase.verifyEqual(height(ref), numel(specFreqs));
            testCase.verifyEqual(unique(ref.band_lo_hz), 55);
            testCase.verifyEqual(unique(ref.band_hi_hz), 65);
            testCase.verifyEqual(unique(ref.peak_hz), 29.94, 'AbsTol', 1e-9);
            testCase.verifyEqual(unique(ref.n_trials), 20);
            testCase.verifyEqual(ref.amplitude(ref.frequency_hz == 30), 9, 'AbsTol', 1e-6);
        end

        function theReferenceFileIsHeaderOnlyForAnOlderResult(testCase)
        %   A result computed before the spectrum was stored has nothing to
        %   write, and the file must still exist with its columns so the
        %   report can tell "not stored" from "no such file".
            [~, entry] = testCase.fixture();
            folder = testCase.tempFolder();

            [~, ~, ~, referenceFile] = exportCoherenceCSVs(entry, fullfile(folder, 'x'));

            testCase.assertTrue(isfile(referenceFile));
            ref = readtable(referenceFile, 'VariableNamingRule', 'preserve');
            testCase.verifyEqual(height(ref), 0);
            testCase.verifyTrue(all(ismember({'bin', 'n_trials', 'band_lo_hz', 'band_hi_hz', ...
                'peak_hz', 'frequency_hz', 'amplitude'}, ref.Properties.VariableNames)));
        end

        function aConditionWithNoCoherenceGivesNoTraceRowsButKeepsItsReferenceSpectrum(testCase)
        %   A single-trial condition has no coherence (see ComputeCoherenceMap)
        %   but its reference spectrum is still true and still worth showing.
            entry = testCase.twoConditionEntry();
            entry.EEG.coherence(:, :, :, 2) = NaN;
            folder = testCase.tempFolder();

            [traceFile, ~, ~, referenceFile] = exportCoherenceCSVs(entry, fullfile(folder, 'x'));

            trace = readtable(traceFile, 'TextType', 'string', 'VariableNamingRule', 'preserve');
            ref = readtable(referenceFile, 'TextType', 'string', 'VariableNamingRule', 'preserve');
            testCase.verifyEqual(unique(trace.bin), "A");
            testCase.verifyEqual(sort(unique(ref.bin)), ["A"; "B"]);
        end

        function eachConditionGetsItsOwnStrongestChannelsByDefault(testCase)
            entry = testCase.twoConditionEntry();
            folder = testCase.tempFolder();
            [~, mapFile] = exportCoherenceCSVs(entry, fullfile(folder, 'x'), struct('MaxChannels', 2));

            map = readtable(mapFile, 'TextType', 'string', 'VariableNamingRule', 'preserve');
            testCase.verifyEqual(sort(unique(map.channel(map.bin == "A"))), ["E2"; "E5"]);
            testCase.verifyEqual(sort(unique(map.channel(map.bin == "B"))), ["E1"; "E3"]);
        end

        function pooledSelectionUsesTheSameChannelsForEveryCondition(testCase)
        %   Channels picked from the average over all conditions cannot depend
        %   on which condition happened to win, which is what a test that
        %   follows needs (Arora et al., 2026). Peaks at the tag, by channel:
        %   A: E2 .9, E5 .8; B: E1 .9, E3 .8, E2 .5. Pooled means: E2 .7,
        %   E1 .5, E3 .45, E5 .45, so the pooled pair is E1 and E2.
            entry = testCase.twoConditionEntry();
            folder = testCase.tempFolder();
            [~, mapFile] = exportCoherenceCSVs(entry, fullfile(folder, 'x'), ...
                struct('MaxChannels', 2, 'SelectBy', 'pooled'));

            map = readtable(mapFile, 'TextType', 'string', 'VariableNamingRule', 'preserve');
            testCase.verifyEqual(sort(unique(map.channel(map.bin == "A"))), ["E1"; "E2"]);
            testCase.verifyEqual(sort(unique(map.channel(map.bin == "B"))), ["E1"; "E2"]);
        end

        function onlyTheNamedChannelsReachTheTraceAndTheMap(testCase)
        %ONLYTHENAMEDCHANNELSREACHTHETRACEANDTHEMAP  The report follows the
        %   electrodes the Spectral Measure rows name, so a user who
        %   measured Oz does not get the whole montage. Matched without regard
        %   to case, as the rows themselves are.
            [trace, map] = testCase.exportFixture(struct('OnlyChannels', {{'e2', 'E4'}}));

            testCase.verifyEqual(sort(unique(trace.channel)), {'E2'; 'E4'});
            testCase.verifyEqual(sort(unique(map.channel)), {'E2'; 'E4'});
            testCase.verifyEqual(height(trace), 2 * 9, ...
                'Two channels at nine time points, and nothing for the other four.');
        end

        function theMapIsChosenAmongTheNamedChannelsAlone(testCase)
        %THEMAPISCHOSENAMONGTHENAMEDCHANNELSALONE  E2 and E5 respond most, but
        %   they were not named. Asking for two map channels among E1, E3 and
        %   E4 must give two of those, never the strong ones and never fewer.
            [~, map] = testCase.exportFixture( ...
                struct('OnlyChannels', {{'E1', 'E3', 'E4'}}, 'MaxChannels', 2));
            channels = unique(map.channel);

            testCase.verifyEqual(numel(channels), 2);
            testCase.verifyTrue(all(ismember(channels, {'E1', 'E3', 'E4'})), ...
                'A channel that was not named was written to the map.');
        end

        function aDatasetWithNoneOfTheNamedChannelsIsWrittenWhole(testCase)
        %ADATASETWITHNONEOFTHENAMEDCHANNELSISWRITTENWHOLE  A montage that
        %   differs from the user's must not silently drop a subject.
            [trace, ~] = testCase.exportFixture(struct('OnlyChannels', {{'Oz'}}));

            testCase.verifyEqual(numel(unique(trace.channel)), 6);
        end

        function namingChannelsDoesNotMoveTheTag(testCase)
        %NAMINGCHANNELSDOESNOTMOVETHETAG  Without a reference spectrum the tag
        %   is read off the coherence averaged over every channel. Naming one
        %   electrode must not change which frequency that is: here E1 alone
        %   peaks at the tag (60 Hz) while the montage as a whole peaks at
        %   58 Hz, and the condition must stay tagged at 58 Hz.
            [~, entry] = testCase.fixtureWithMisleadingChannelAverage();
            entry.EEG = rmfield(entry.EEG, 'cohRefPower');
            folder = testCase.tempFolder();
            exportCoherenceCSVs(entry, fullfile(folder, 'x'), struct('OnlyChannels', {{'E1'}}));

            trace = readtable(fullfile(folder, 'x_coherence_trace.csv'), ...
                'VariableNamingRule', 'preserve');
            testCase.verifyEqual(unique(trace.tag_hz), testCase.WrongHz, 'AbsTol', 1e-9);
        end

        function anUnknownSelectionRuleIsRefused(testCase)
            [~, entry] = testCase.fixture();
            folder = testCase.tempFolder();
            testCase.verifyError(@() exportCoherenceCSVs(entry, fullfile(folder, 'x'), ...
                struct('SelectBy', 'best')), 'Alakazam:exportCoherenceCSVs');
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

        function [eeg, entry] = fixtureWithMisleadingChannelAverage(testCase)
        %FIXTUREWITHMISLEADINGCHANNELAVERAGE  Five of six channels carry a
        %   modest coherence bump at WrongHz (58 Hz) and a near-nothing one
        %   at TagHz (60 Hz); the sixth is the other way round but far
        %   stronger. Averaged over all six channels, WrongHz still wins
        %   ((5*0.3 + 0.05)/6 vs. (5*0.05 + 0.9)/6) -- the exact shape a
        %   real weak/noisy tagging response produces when most electrodes
        %   barely track the flicker at all. cohRefPower, in contrast, is a
        %   clean, sharp peak at TagHz alone, the shape a photodiode's own
        %   spectrum gives regardless of how any EEG channel responded.
            nChan = 6;
            freqs = 55:1:65;
            times = linspace(-200, 800, 9);
            nFreq = numel(freqs);
            nTime = numel(times);
            wrongIdx = find(freqs == testCase.WrongHz, 1);
            tagIdx = find(freqs == testCase.TagHz, 1);
            inWindow = times > 0 & times < 600;

            coh = 0.05 * ones(nChan, nFreq, nTime);
            for c = 1:nChan
                if c == 1
                    coh(c, tagIdx, inWindow) = 0.9;
                else
                    coh(c, wrongIdx, inWindow) = 0.3;
                end
            end

            refPower = 1e-6 * ones(nFreq, nTime, 1);
            refPower(tagIdx, inWindow, 1) = 1;

            eeg = struct();
            eeg.coherence = coh;
            eeg.cohFreqs = freqs;
            eeg.cohTimes = times;
            eeg.cohRefPower = refPower;
            eeg.chanlocs = struct('labels', ...
                arrayfun(@(k) sprintf('E%d', k), 1:nChan, 'UniformOutput', false));
            eeg.bindesc = struct('label', {'Tagged'}, 'index', {1});

            entry = struct('subject', 'sub01', 'datasetType', 'subject', ...
                'group', '', 'person', 'p01', 'session', '', 'EEG', eeg);
        end

        function entry = twoConditionEntry(testCase)
        %TWOCONDITIONENTRY  Two conditions, A and B, tagged at 60 Hz, whose
        %   strongest channels differ. Peak coherence at the tag by channel
        %   (E1..E6): A = .1 .9 .1 .1 .8 .1; B = .9 .5 .8 .1 .1 .1.
            nChan = 6;
            freqs = 55:1:65;
            times = linspace(-200, 800, 9);
            fIdx = find(freqs == testCase.TagHz, 1);
            inWindow = times > 0 & times < 600;
            peakA = [.1 .9 .1 .1 .8 .1];
            peakB = [.9 .5 .8 .1 .1 .1];

            coh = 0.05 * ones(nChan, numel(freqs), numel(times), 2);
            for c = 1:nChan
                coh(c, fIdx, inWindow, 1) = peakA(c);
                coh(c, fIdx, inWindow, 2) = peakB(c);
            end
            refPower = 1e-6 * ones(numel(freqs), numel(times), 2);
            refPower(fIdx, inWindow, :) = 1;

            eeg = struct();
            eeg.coherence = coh;
            eeg.cohFreqs = freqs;
            eeg.cohTimes = times;
            eeg.cohRefPower = refPower;
            eeg.chanlocs = struct('labels', ...
                arrayfun(@(k) sprintf('E%d', k), 1:nChan, 'UniformOutput', false));
            eeg.bindesc = struct('label', {'A', 'B'}, 'index', {1, 2}, 'trials', {1:20, 1:20});

            specFreqs = 0:0.25:150;
            eeg.cohRefSpectrum = single(1e-3 * ones(numel(specFreqs), 2));
            eeg.cohRefSpecFreqs = specFreqs;
            eeg.cohRefPeakHz = [60 60];

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
                'TextType', 'string', 'VariableNamingRule', 'preserve', 'TreatAsMissing', 'NA');
            map = readtable(fullfile(folder, 'x_coherence_map.csv'), ...
                'TextType', 'string', 'VariableNamingRule', 'preserve', 'TreatAsMissing', 'NA');
            trace.channel = cellstr(trace.channel);
            map.channel = cellstr(map.channel);
        end
    end
end
