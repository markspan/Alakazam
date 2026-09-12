classdef DeriveChannelsTest < matlab.unittest.TestCase
%DERIVECHANNELSTEST  Unit tests for
%   src/Transformations/DeriveChannels/DeriveChannels.m.
%
%   The expression grammar itself is TransTools.ApplyDerivations' and is
%   exercised through MeasureTest and MergeLetDefinitionsTest as well. What
%   is tested here is what the TRANSFORMATION adds: that it runs at any
%   pipeline stage, that a derived channel survives into the steps below it,
%   that replay is idempotent, and the one interaction that would otherwise
%   surprise someone (a downstream Measure with its own let block).
%
%   Run with: runtests('tests/DeriveChannelsTest.m').

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            for p = {fullfile(root, 'src', 'Transformations', 'DeriveChannels'), ...
                     fullfile(root, 'src', 'Transformations', 'Measure'), ...
                     fullfile(root, 'src', 'Transformations'), ...
                     fullfile(root, 'src', 'Support'), ...
                     fullfile(root, 'tests', 'fixtures')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
        end
    end

    methods (Test)
        function derivesADifferenceBetweenElectrodes(testCase)
        %DERIVESADIFFERENCEBETWEENELECTRODES  The motivating case: an LRP is
        %   C3 minus C4, which is a channel operation, not a bin operation.
            EEG = makeTestEEG('nbchan', 3, 'labels', {'C3', 'C4', 'Cz'});

            out = DeriveChannels(EEG, struct('derivations', 'let LRP = C3 - C4'));

            testCase.assertEqual(out.nbchan, 4);
            testCase.verifyEqual(out.chanlocs(end).labels, 'LRP');
            testCase.verifyEqual(out.data(4, :, :), ...
                EEG.data(1, :, :) - EEG.data(2, :, :), 'AbsTol', 1e-12);
        end

        function theDerivedChannelIsMarkedAndHasNoPosition(testCase)
        %THEDERIVEDCHANNELISMARKEDANDHASNOPOSITION  Both matter downstream:
        %   the mark is what makes replay idempotent, and the absent
        %   position is what keeps a difference wave off the scalp map.
            EEG = makeTestEEG('nbchan', 2, 'labels', {'C3', 'C4'});
            out = DeriveChannels(EEG, struct('derivations', 'let LRP = C3 - C4'));

            testCase.verifyEqual(out.chanlocs(end).type, 'derived');

            % Every field but the label and the type is left empty, whichever
            % coordinate fields this montage happens to carry. Asserting on a
            % specific one (X, theta, ...) would only test the fixture.
            derivedChan = out.chanlocs(end);
            for f = setdiff(fieldnames(derivedChan)', {'labels', 'type'})
                testCase.verifyEmpty(derivedChan.(f{1}), sprintf( ...
                    'A derived channel has no place on the head, so "%s" must be empty.', f{1}));
            end
        end

        function itLeavesTheDataFormatAlone(testCase)
        %ITLEAVESTHEDATAFORMATALONE  The arithmetic is elementwise, so this
        %   is not a reshaping step and must not claim to be one; the next
        %   transformation's format guard has to still see the truth.
            for fmt = {'CONTINUOUS', 'EPOCHED'}
                EEG = makeTestEEG('nbchan', 2, 'labels', {'C3', 'C4'}, ...
                    'DataFormat', fmt{1});
                out = DeriveChannels(EEG, struct('derivations', 'let d = C3 - C4'));
                testCase.verifyEqual(out.DataFormat, fmt{1});
                testCase.verifyEqual(out.DataType, EEG.DataType);
            end
        end

        function itWorksOnContinuousTwoDimensionalData(testCase)
        %ITWORKSONCONTINUOUSTWODIMENSIONALDATA  Deriving before epoching is
        %   legitimate: it is how you epoch, baseline or reject on the
        %   derived channel itself.
            EEG = makeTestEEG('nbchan', 2, 'labels', {'C3', 'C4'}, ...
                'trials', 1, 'DataFormat', 'CONTINUOUS');
            EEG.data = EEG.data(:, :, 1);

            out = DeriveChannels(EEG, struct('derivations', 'let d = C3 - C4'));

            testCase.verifyEqual(size(out.data), [3 size(EEG.data, 2)]);
            testCase.verifyEqual(out.data(3, :), EEG.data(1, :) - EEG.data(2, :), ...
                'AbsTol', 1e-12);
        end

        function replayingItTwiceDoesNotAccumulateChannels(testCase)
        %REPLAYINGITTWICEDOESNOTACCUMULATECHANNELS  Recalculate and template
        %   replay both re-run a node on its own output's parent; running the
        %   same block again must replace, not stack up duplicates.
            EEG = makeTestEEG('nbchan', 2, 'labels', {'C3', 'C4'});
            opts = struct('derivations', 'let LRP = C3 - C4');

            once  = DeriveChannels(EEG, opts);
            twice = DeriveChannels(once, opts);

            testCase.verifyEqual(twice.nbchan, once.nbchan);
            testCase.verifyEqual(nnz(strcmpi({twice.chanlocs.labels}, 'LRP')), 1);
            testCase.verifyEqual(twice.data, once.data, 'AbsTol', 1e-12);
        end

        function anEmptyBlockIsANoOpRatherThanAnError(testCase)
        %ANEMPTYBLOCKISANOOPRATHERTHANANERROR  So a stored block that has
        %   been commented out still replays instead of stopping the branch.
            EEG = makeTestEEG('nbchan', 2, 'labels', {'C3', 'C4'});

            for text = {'', '% let LRP = C3 - C4', sprintf('\n\n')}
                out = DeriveChannels(EEG, struct('derivations', text{1}));
                testCase.verifyEqual(out.nbchan, EEG.nbchan);
                testCase.verifyEqual(out.data, EEG.data);
            end
        end

        function anUnknownChannelIsRefusedWithItsOwnErrorId(testCase)
            EEG = makeTestEEG('nbchan', 2, 'labels', {'C3', 'C4'});

            testCase.verifyError( ...
                @() DeriveChannels(EEG, struct('derivations', 'let d = C3 - NoSuchChannel')), ...
                'Alakazam:Derivations');
        end

        function aNameThatClashesWithARealChannelIsRefused(testCase)
            EEG = makeTestEEG('nbchan', 2, 'labels', {'C3', 'C4'});

            testCase.verifyError( ...
                @() DeriveChannels(EEG, struct('derivations', 'let C4 = C3 - C4')), ...
                'Alakazam:Derivations');
        end

        function aDatasetWithNoChannelListIsRefused(testCase)
            testCase.verifyError( ...
                @() DeriveChannels(struct('data', zeros(2, 10)), ...
                    struct('derivations', 'let d = C3 - C4')), ...
                'Alakazam:DeriveChannels');
        end

        function aDerivedChannelCanBeMeasured(testCase)
        %ADERIVEDCHANNELCANBEMEASURED  The point of making this a node: the
        %   channel exists in the data, so Measure scores it like any other
        %   without needing a let block of its own.
            EEG = makeTestEEG('nbchan', 2, 'labels', {'C3', 'C4'});
            EEG.data = mean(EEG.data, 3);
            EEG.trials = 1;
            EEG.DataFormat = 'Averaged';

            derived = DeriveChannels(EEG, struct('derivations', 'let LRP = C3 - C4'));
            win = struct('label', 'W', 'start', EEG.times(1), 'stop', EEG.times(end), ...
                'measure', 'Mean Amplitude', 'polarity', 'Positive', 'width', [], ...
                'localPoints', 0, 'fraction', [], 'areaMode', 'signed', ...
                'baseline', [], 'refChannel', '', 'channels', {{'LRP'}});
            m = Measure(derived, struct('windows', {{win}}, 'derivations', ''));

            expected = mean(derived.data(end, :), 2);
            testCase.verifyEqual(m.measurements{1}.amplitude, expected, 'AbsTol', 1e-10);
        end

        function aDownstreamMeasureBlockReplacesTheseChannels(testCase)
        %ADOWNSTREAMMEASUREBLOCKREPLACESTHESECHANNELS  A documented trap,
        %   pinned so it stays a known property rather than a surprise.
        %   Whichever step defines derivations replaces ALL derived channels,
        %   which is what makes replay idempotent. So use one place or the
        %   other: derive in this node and leave Measure's field blank.
            EEG = makeTestEEG('nbchan', 2, 'labels', {'C3', 'C4'});
            EEG.data = mean(EEG.data, 3);
            EEG.trials = 1;
            EEG.DataFormat = 'Averaged';
            derived = DeriveChannels(EEG, struct('derivations', 'let LRP = C3 - C4'));

            win = struct('label', 'W', 'start', EEG.times(1), 'stop', EEG.times(end), ...
                'measure', 'Mean Amplitude', 'polarity', 'Positive', 'width', [], ...
                'localPoints', 0, 'fraction', [], 'areaMode', 'signed', ...
                'baseline', [], 'refChannel', '', 'channels', {{'C3'}});

            % Measure's field blank: this node's channel survives.
            kept = Measure(derived, struct('windows', {{win}}, 'derivations', ''));
            testCase.verifyTrue(any(strcmpi({kept.chanlocs.labels}, 'LRP')), ...
                'A blank Measure block must leave upstream derived channels alone.');

            % Measure defining its own: LRP is replaced by Measure's channel.
            replaced = Measure(derived, struct('windows', {{win}}, ...
                'derivations', 'let other = C3 + C4'));
            testCase.verifyFalse(any(strcmpi({replaced.chanlocs.labels}, 'LRP')), ...
                'A non-blank Measure block replaces every derived channel.');
            testCase.verifyTrue(any(strcmpi({replaced.chanlocs.labels}, 'other')));
        end

        function itIsRegisteredForTheRibbon(testCase)
        %ITISREGISTEREDFORTHERIBBON  A transformation with no valid .json is
        %   invisible in the app however well its function works.
            root = fileparts(fileparts(mfilename('fullpath')));
            jsonFile = fullfile(root, 'src', 'Transformations', 'DeriveChannels', ...
                'DeriveChannels.json');
            testCase.assertTrue(isfile(jsonFile));

            meta = jsondecode(fileread(jsonFile));
            testCase.verifyEqual(meta.Entry, 'DeriveChannels.m');
            testCase.verifyEqual(meta.Section, '1. Preprocessing');
            testCase.verifyNotEmpty(meta.Name);
            testCase.verifyNotEmpty(meta.Description);
            testCase.verifyTrue(isfile(fullfile(fileparts(jsonFile), meta.Icon)), ...
                'The icon named in the registry entry has to exist.');
        end
    end
end
