classdef InterpolateTest < matlab.unittest.TestCase
%INTERPOLATETEST  Unit tests for
%   src/Transformations/Interpolate/Interpolate.m.
%
%   The actual reconstruction math is entirely EEGLAB's own pop_interp and
%   is not tested here. What's genuinely Alakazam's own and worth testing
%   without EEGLAB at all: the two validation checks, and the "none of the
%   stored bad channels are in this dataset" no-op shortcut (badIdx empty
%   -> EEG returned unchanged, pop_interp never called).
%
%   The two DataType/DataFormat tests DO have to reach pop_interp, so they
%   carry their own assumeTrue and skip -- not fail -- without EEGLAB.
%
%   Run with: runtests('tests/InterpolateTest.m').

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            for p = {fullfile(root, 'src', 'Transformations', 'Interpolate'), ...
                     fullfile(root, 'src', 'Transformations'), ...
                     fullfile(root, 'src', 'Support'), ...
                     fullfile(root, 'tests', 'fixtures')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
        end
    end

    methods (Test)
        function rejectsNoChanlocs(testCase)
            EEG = struct('data', zeros(2, 100), 'srate', 250);
            opts = struct('channels', {{'Ch1'}});
            testCase.verifyError(@() Interpolate(EEG, opts), 'Alakazam:Interpolate');
        end

        function rejectsChanlocsWithNoScalpPositions(testCase)
            EEG = testCase.positionedFixture(false); % chanlocs present, but no real positions
            opts = struct('channels', {{'Ch1'}});
            testCase.verifyError(@() Interpolate(EEG, opts), 'Alakazam:Interpolate');
        end

        function noOpWhenNoneOfTheStoredChannelsMatch(testCase)
        %NOOPWHENNONEOFTHESTOREDCHANNELSMATCH  A stored bad-channel label
        %   not present in this dataset resolves to an empty badIdx --
        %   Interpolate should return the dataset unchanged (pop_interp
        %   never reached), not error.
            EEG = testCase.positionedFixture(true);
            opts = struct('channels', {{'NoSuchChannel'}});

            [result, ~] = Interpolate(EEG, opts);

            testCase.verifyEqual(result, EEG);
        end

        function worksOnADatasetThatNeverHadDataTypeSet(testCase)
        %WORKSONADATASETTHATNEVERHADDATATYPESET  Interpolate restores
        %   Alakazam's own DataType/DataFormat after pop_interp (which
        %   rebuilds the struct through eeg_checkset and drops them). It used
        %   to read them straight off the input, so a dataset that never had
        %   them -- one loaded with pop_loadset outside the app, as the Luck
        %   validation harness does -- died on "Unrecognized field name
        %   DataType" instead of interpolating.
            testCase.assumeTrue(exist('eeg_interp', 'file') == 2, ...
                'EEGLAB (eeg_interp) is not on the path.');

            EEG = testCase.positionedScalpFixture();
            EEG.data   = EEG.data(:, :, 1);      % continuous: one 2-D sweep
            EEG.trials = 1;
            testCase.assertFalse(isfield(EEG, 'DataType'), ...
                'The fixture must arrive without the field for this to test anything.');

            result = Interpolate(EEG, struct('channels', {{'Cz'}}, 'method', 'spherical'));

            testCase.verifyEqual(result.DataType, 'TIMEDOMAIN');
            testCase.verifyEqual(result.DataFormat, 'CONTINUOUS', ...
                'Two-dimensional data is continuous, not epoched.');
            testCase.verifyFalse(isequal(result.data(2, :), EEG.data(2, :)), ...
                'Cz should actually have been rebuilt.');
        end

        function anEpochedDatasetWithoutDataFormatIsNotCalledContinuous(testCase)
        %ANEPOCHEDDATASETWITHOUTDATAFORMATISNOTCALLEDCONTINUOUS  The
        %   fallback reads the data shape rather than assuming continuous,
        %   so a 3-D dataset is not mislabelled -- which would make the next
        %   transform in the chain reject it.
            testCase.assumeTrue(exist('eeg_interp', 'file') == 2, ...
                'EEGLAB (eeg_interp) is not on the path.');

            EEG = testCase.positionedScalpFixture();   % 2 trials, 3-D
            testCase.assertEqual(size(EEG.data, 3), 2);

            result = Interpolate(EEG, struct('channels', {{'Cz'}}, 'method', 'spherical'));

            testCase.verifyEqual(result.DataFormat, 'EPOCHED');
        end
    end

    methods (Access = private)
        function EEG = positionedFixture(~, withPositions)
        %POSITIONEDFIXTURE  A minimal 2-channel EEG. WITHPOSITIONS false
        %   gives chanlocs with no usable scalp coordinates at all (X/theta
        %   all empty), matching anyHasPosition's own definition of "nothing
        %   to interpolate from". Small enough that pop_interp is never
        %   reached, so it needs no chaninfo -- unlike
        %   positionedScalpFixture below.
            EEG = struct();
            EEG.data  = zeros(2, 100);
            EEG.srate = 250;
            if withPositions
                EEG.chanlocs = struct('labels', {'Ch1', 'Ch2'}, ...
                    'X', {1, 2}, 'theta', {10, 20});
            else
                EEG.chanlocs = struct('labels', {'Ch1', 'Ch2'}, ...
                    'X', {[], []}, 'theta', {[], []});
            end
        end

        function EEG = positionedScalpFixture(~)
        %POSITIONEDSCALPFIXTURE  Four positioned scalp channels in a full,
        %   EEGLAB-valid struct (pop_interp reads EEG.chaninfo, so the
        %   struct has to be a real one), with Alakazam's own DataType and
        %   DataFormat REMOVED -- which is the point of these two tests.
        %   Same construction ArtefactDetectChannelScopeTest uses.
            EEG = makeTestEEG('nbchan', 4, 'labels', {'Fz', 'Cz', 'Pz', 'Oz'}, ...
                'trials', 2);

            base = eeg_emptyset();
            fn = fieldnames(EEG);
            for k = 1:numel(fn)
                base.(fn{k}) = EEG.(fn{k});
            end
            EEG = base;
            EEG.setname = 'fixture';
            EEG.xmin = EEG.times(1) / 1000;
            EEG.xmax = EEG.times(end) / 1000;
            EEG = TransTools.FillChanlocs(EEG, 'Alakazam:InterpolateTest', ...
                TransTools.Template1005File('Alakazam:InterpolateTest'));

            EEG = rmfield(EEG, {'DataType', 'DataFormat'});
        end
    end
end
