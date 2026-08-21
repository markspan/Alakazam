classdef InterpolateTest < matlab.unittest.TestCase
%INTERPOLATETEST  Unit tests for
%   src/Transformations/Interpolate/Interpolate.m.
%
%   The actual reconstruction math is entirely EEGLAB's own pop_interp,
%   not tested here (see the class-level assumeTrue guard, which skips
%   -- not fails -- the one test that needs it if EEGLAB is unavailable).
%   What's genuinely Alakazam's own and worth testing without EEGLAB at
%   all: the two validation checks, and the "none of the stored bad
%   channels are in this dataset" no-op shortcut (badIdx empty -> EEG
%   returned unchanged, pop_interp never called).
%
%   Run with: runtests('tests/InterpolateTest.m').

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'Transformations', 'Interpolate')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'Transformations')));
        end
    end

    methods (Test)
        function rejectsNoChanlocs(testCase)
            EEG = struct('data', zeros(2, 100), 'srate', 250);
            opts = struct('channels', {{'Ch1'}});
            testCase.verifyError(@() Interpolate(EEG, opts), 'Alakazam:Interpolate');
        end

        function rejectsChanlocsWithNoScalpPositions(testCase)
            EEG = positionedFixture(false); % chanlocs present, but no real positions
            opts = struct('channels', {{'Ch1'}});
            testCase.verifyError(@() Interpolate(EEG, opts), 'Alakazam:Interpolate');
        end

        function noOpWhenNoneOfTheStoredChannelsMatch(testCase)
        %NOOPWHENNONEOFTHESTOREDCHANNELSMATCH  A stored bad-channel label
        %   not present in this dataset resolves to an empty badIdx --
        %   Interpolate should return the dataset unchanged (pop_interp
        %   never reached), not error.
            EEG = positionedFixture(true);
            opts = struct('channels', {{'NoSuchChannel'}});

            [result, ~] = Interpolate(EEG, opts);

            testCase.verifyEqual(result, EEG);
        end
    end
end

function EEG = positionedFixture(withPositions)
%POSITIONEDFIXTURE  A minimal 2-channel EEG. WITHPOSITIONS false gives
%   chanlocs with no usable scalp coordinates at all (X/theta all empty),
%   matching anyHasPosition's own definition of "nothing to interpolate
%   from".
    EEG = struct();
    EEG.data  = zeros(2, 100);
    EEG.srate = 250;
    if withPositions
        EEG.chanlocs = struct('labels', {'Ch1', 'Ch2'}, 'X', {1, 2}, 'theta', {10, 20});
    else
        EEG.chanlocs = struct('labels', {'Ch1', 'Ch2'}, 'X', {[], []}, 'theta', {[], []});
    end
end
