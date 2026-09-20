classdef SpectralMeasureChannelsTest < matlab.unittest.TestCase
%SPECTRALMEASURECHANNELSTEST  Which electrodes the report's coherence figures
%   follow.
%
%   The rows of a Spectral Measure name their channels, and the result stores
%   the labels of the specs it computed (a pool "{Pz POz}" is stored as
%   "{Pz+POz}"). spectralMeasureChannels turns those into the plain electrode
%   names the coherence export is narrowed to, and returns {} when there is
%   nothing to follow.
%
%   Run with: runtests('tests/SpectralMeasureChannelsTest.m').
%
%   See also SPECTRALMEASURECHANNELS, EXPORTCOHERENCECSVS.

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'Reports')));
        end
    end

    methods (Test)
        function twoRowsOnTheSameChannelGiveThatChannelOnce(testCase)
            entries = testCase.entryWith({ ...
                row('RIFT 60', {'Oz'}, 'PhotoDiode'), row('RIFT 64', {'Oz'}, 'PhotoDiode')});

            testCase.verifyEqual(spectralMeasureChannels(entries), {'Oz'});
        end

        function aPoolContributesItsMembers(testCase)
        %   The coherence map is per electrode, so a pool has nothing of its
        %   own to draw.
            entries = testCase.entryWith({ ...
                row('A', {'{Pz+POz+CPz}', 'Cz'}, 'PhotoDiode')});

            testCase.verifyEqual(spectralMeasureChannels(entries), {'Pz', 'POz', 'CPz', 'Cz'});
        end

        function aRowWithoutAReferenceIsIgnored(testCase)
        %   No reference, no coherence: its channels say nothing about which
        %   electrodes the coherence figures should show.
            entries = testCase.entryWith({ ...
                row('A', {'Oz'}, 'PhotoDiode'), row('B', {'Fz', 'Cz'}, '')});

            testCase.verifyEqual(spectralMeasureChannels(entries), {'Oz'});
        end

        function everyChannelRowNamesEveryChannel(testCase)
        %   A row left on "all channels" stores them all, so its union is the
        %   whole montage (see namingTheWholeMontageNarrowsNothing for what
        %   the report makes of that).
            entries = testCase.entryWith({ ...
                row('A', {'Fz', 'Cz', 'Oz'}, 'PhotoDiode')});

            testCase.verifyEqual(spectralMeasureChannels(entries), {'Fz', 'Cz', 'Oz'});
        end

        function entriesAreCombinedInTheOrderFirstMet(testCase)
            first = testCase.entryWith({row('A', {'Oz', 'Pz'}, 'PhotoDiode')});
            second = testCase.entryWith({row('A', {'Pz', 'Cz'}, 'PhotoDiode')});

            testCase.verifyEqual(spectralMeasureChannels([first second]), {'Oz', 'Pz', 'Cz'});
        end

        function namingTheWholeMontageNarrowsNothing(testCase)
        %   A row left on "all channels" stores every electrode. Following
        %   that would draw sixty-four coloured lines as if each had been
        %   picked, so it is read as "no restriction".
            entries = testCase.entryWith({row('A', {'Fz', 'Cz', 'Oz'}, 'PhotoDiode')});
            montage = testCase.montageOf({'Fz', 'Cz', 'Oz'});

            testCase.verifyEmpty(spectralMeasureChannels(entries, montage));
        end

        function namingPartOfTheMontageNarrowsIt(testCase)
            entries = testCase.entryWith({row('A', {'Oz'}, 'PhotoDiode')});
            montage = testCase.montageOf({'Fz', 'Cz', 'oz'});

            testCase.verifyEqual(spectralMeasureChannels(entries, montage), {'Oz'});
        end

        function namesNoMapHasNarrowNothing(testCase)
        %   The named electrode is in none of the maps, so the export falls
        %   back to the whole montage and the report must not claim otherwise.
            entries = testCase.entryWith({row('A', {'Oz'}, 'PhotoDiode')});
            montage = testCase.montageOf({'Fz', 'Cz', 'Pz'});

            testCase.verifyEmpty(spectralMeasureChannels(entries, montage));
        end

        function nothingToFollowGivesNothing(testCase)
            bare = struct('subject', 's', 'datasetType', 'subject', 'group', '', ...
                'person', 'p', 'session', '', 'EEG', struct());
            noRows = testCase.entryWith({});

            testCase.verifyEmpty(spectralMeasureChannels(bare));
            testCase.verifyEmpty(spectralMeasureChannels(noRows));
        end
    end

    methods (Access = private)
        function montage = montageOf(~, labels)
            montage = struct('subject', 's', 'datasetType', 'subject', 'group', '', ...
                'person', 'p', 'session', '', ...
                'EEG', struct('chanlocs', struct('labels', labels)));
        end

        function entry = entryWith(~, rows)
            entry = struct('subject', 's', 'datasetType', 'subject', 'group', '', ...
                'person', 'p', 'session', '', 'EEG', struct('spectralMeasures', {rows}));
        end
    end
end

function m = row(label, channels, refChannel)
%ROW  A stored Spectral Measure row with just the fields the function reads.
    m = struct('label', label, 'freq', 60, 'channels', {channels}, 'refChannel', refChannel);
end
