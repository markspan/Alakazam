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

        function aNameTheDataHasIsOverwrittenInPlace(testCase)
        %ANAMETHEDATAHASISOVERWRITTENINPLACE  "let ECG = -ECG" turns an
        %   inverted ECG the right way up: the same channel, in the same
        %   place, with its position and type, only its values new.
            EEG = makeTestEEG('nbchan', 3, 'labels', {'C3', 'ECG', 'C4'});
            EEG.chanlocs(2).type = 'ECG';

            out = DeriveChannels(EEG, struct('derivations', 'let ECG = -ECG'));

            testCase.assertEqual(out.nbchan, 3);
            testCase.verifyEqual(out.data(2, :, :), -EEG.data(2, :, :));
            testCase.verifyEqual(out.data([1 3], :, :), EEG.data([1 3], :, :));
            testCase.verifyEqual(out.chanlocs, EEG.chanlocs, 'The channel list is untouched.');
        end

        function emptyBracketsRemoveTheChannel(testCase)
            EEG = makeTestEEG('nbchan', 3, 'labels', {'C3', 'ECG', 'C4'});

            out = DeriveChannels(EEG, struct('derivations', 'let ECG = [ ]'));

            testCase.verifyEqual({out.chanlocs.labels}, {'C3', 'C4'});
            testCase.verifyEqual(out.nbchan, 2);
            testCase.verifyEqual(out.data, EEG.data([1 3], :, :));
        end

        function removingAChannelThatIsNotThereIsRefused(testCase)
            EEG = makeTestEEG('nbchan', 2, 'labels', {'C3', 'C4'});

            testCase.verifyError( ...
                @() DeriveChannels(EEG, struct('derivations', 'let ECG = []')), ...
                'Alakazam:Derivations');
        end

        function aChannelDerivedInAnEarlierStepCanBeUsed(testCase)
        %ACHANNELDERIVEDINANEARLIERSTEPCANBEUSED  The reported failure: ECG2
        %   derived from ECG in one step, ECG removed, and then ECG derived
        %   back from ECG2 in another step, which failed with "ECG2 is not a
        %   channel" because every step first removed all derived channels.
            EEG = makeTestEEG('nbchan', 3, 'labels', {'C3', 'ECG', 'C4'});

            copied = DeriveChannels(EEG, struct('derivations', 'let ECG2 = ECG'));
            noEcg = DeriveChannels(copied, struct('derivations', 'let ECG = []'));
            back = DeriveChannels(noEcg, struct('derivations', 'let ECG = ECG2'));

            testCase.verifyEqual({back.chanlocs.labels}, {'C3', 'C4', 'ECG2', 'ECG'});
            testCase.verifyEqual(back.data(4, :, :), EEG.data(2, :, :));
            testCase.verifyEqual(back.data(3, :, :), EEG.data(2, :, :), ...
                'The channel the first step derived is still there.');
        end

        function theLinesRunInOrder(testCase)
        %THELINESRUNINORDER  Each line sees the channels the lines above left:
        %   a copy kept under a new name, the original removed, the copy used.
            EEG = makeTestEEG('nbchan', 2, 'labels', {'C3', 'ECG'});

            out = DeriveChannels(EEG, struct('derivations', ...
                sprintf('let heart = ECG\nlet ECG = []\nlet double = heart * 2')));

            testCase.verifyEqual({out.chanlocs.labels}, {'C3', 'heart', 'double'});
            testCase.verifyEqual(out.data(3, :, :), 2 * EEG.data(2, :, :), 'AbsTol', 1e-12);
            testCase.verifyError(@() DeriveChannels(EEG, struct('derivations', ...
                sprintf('let ECG = []\nlet x = ECG'))), 'Alakazam:Derivations', ...
                'A removed channel is gone for the lines below.');
        end

        function aQuotedNameCanBeOverwrittenOrRemoved(testCase)
            EEG = makeTestEEG('nbchan', 3, 'labels', {'53', 'LEOG', 'EOG-R'});

            out = DeriveChannels(EEG, struct('derivations', ...
                sprintf('let "53" = -"53"\nlet "EOG-R" = []')));

            testCase.verifyEqual({out.chanlocs.labels}, {'53', 'LEOG'});
            testCase.verifyEqual(out.data(1, :, :), -EEG.data(1, :, :));
        end

        function aChannelTheIcaWasComputedOnIsKept(testCase)
        %ACHANNELTHEICAWASCOMPUTEDONISKEPT  Its components would no longer
        %   match the data; any other channel goes, and the decomposition's
        %   channel numbers follow.
            EEG = makeTestEEG('nbchan', 4, 'labels', {'Fz', 'ECG', 'Cz', 'Pz'});
            EEG.icachansind = [1 3 4];

            testCase.verifyError(@() DeriveChannels(EEG, struct('derivations', 'let Cz = []')), ...
                'Alakazam:Derivations');
            out = DeriveChannels(EEG, struct('derivations', 'let ECG = []'));
            testCase.verifyEqual(out.icachansind, [1 2 3]);
            testCase.verifyEqual({out.chanlocs(out.icachansind).labels}, {'Fz', 'Cz', 'Pz'});
        end

        function aQuotedNameIsTheChannelOfThatName(testCase)
        %AQUOTEDNAMEISTHECHANNELOFTHATNAME  BrainVision caps name their
        %   channels by number, as FieldTrip's ERP tutorial recording does:
        %   its vertical EOG is LEOG minus channel 53. A hyphenated label is
        %   reached the same way.
            EEG = makeTestEEG('nbchan', 3, 'labels', {'53', 'LEOG', 'EOG-R'});

            out = DeriveChannels(EEG, struct('derivations', ...
                sprintf('let eogv = LEOG - "53"\nlet eogh = "EOG-R" - LEOG')));

            testCase.verifyEqual(out.data(4, :, :), EEG.data(2, :, :) - EEG.data(1, :, :), 'AbsTol', 1e-12);
            testCase.verifyEqual(out.data(5, :, :), EEG.data(3, :, :) - EEG.data(2, :, :), 'AbsTol', 1e-12);
        end

        function aBareNumberThatNamesAChannelIsRefused(testCase)
        %ABARENUMBERTHATNAMESACHANNELISREFUSED  Read as the number, "LEOG -
        %   53" gives a channel that looks like an EOG and is not; read as the
        %   channel, "/ 2" would halve nothing. Neither is guessed.
            EEG = makeTestEEG('nbchan', 3, 'labels', {'2', '53', 'LEOG'});

            for text = {'let eogv = LEOG - 53', 'let half = LEOG / 2'}
                testCase.verifyError(@() DeriveChannels(EEG, struct('derivations', text{1})), ...
                    'Alakazam:Derivations', text{1});
            end
            out = DeriveChannels(EEG, struct('derivations', 'let half = LEOG / 2.0'));
            testCase.verifyEqual(out.data(4, :, :), EEG.data(3, :, :) / 2, 'AbsTol', 1e-12, ...
                'Written as 2.0 it is the number.');
        end

        function aNumberNamingNoChannelIsANumber(testCase)
            EEG = makeTestEEG('nbchan', 2, 'labels', {'C3', 'C4'});

            out = DeriveChannels(EEG, struct('derivations', 'let mean34 = (C3 + C4) / 2'));

            testCase.verifyEqual(out.data(3, :, :), (EEG.data(1, :, :) + EEG.data(2, :, :)) / 2, ...
                'AbsTol', 1e-12);
        end

        function anUnclosedQuoteIsRefused(testCase)
            EEG = makeTestEEG('nbchan', 2, 'labels', {'53', 'LEOG'});

            testCase.verifyError( ...
                @() DeriveChannels(EEG, struct('derivations', 'let eogv = LEOG - "53')), ...
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

        function aDownstreamMeasureBlockAddsToTheseChannels(testCase)
        %ADOWNSTREAMMEASUREBLOCKADDSTOTHESECHANNELS  Until 2026-10-22 a
        %   documented trap: whichever step defined derivations removed ALL
        %   derived channels first, so a let block in Measure wiped the ones
        %   this node had made. Now it adds to them, and overwrites one only
        %   by naming it again.
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

            % Measure defining its own: added beside LRP.
            both = Measure(derived, struct('windows', {{win}}, ...
                'derivations', 'let other = C3 + C4'));
            testCase.verifyEqual({both.chanlocs.labels}, {'C3', 'C4', 'LRP', 'other'}, ...
                'A Measure block must keep the channels derived above it.');

            % Measure naming LRP again: overwritten, not added twice.
            redefined = Measure(derived, struct('windows', {{win}}, ...
                'derivations', 'let LRP = C4 - C3'));
            testCase.verifyEqual({redefined.chanlocs.labels}, {'C3', 'C4', 'LRP'});
            testCase.verifyEqual(redefined.data(3, :), -derived.data(3, :), 'AbsTol', 1e-12);
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
