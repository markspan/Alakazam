classdef InferDataFormatTest < matlab.unittest.TestCase
%INFERDATAFORMATTEST  Unit tests for src/Support/inferDataFormat.m.
%
%   THE BUG THIS PINS. loadSETFile.m used to hard-code DataFormat =
%   'CONTINUOUS' for every .set file, regardless of its actual shape. An
%   already-epoched .set dropped into the data directory (from another
%   EEGLAB pipeline, or an Alakazam result re-exported via onExportSet) was
%   then routed to SignalView, built only for 2-D continuous data --
%   SignalView's own y = y.' on the 3-D result threw "TRANSPOSE does not
%   support N-D arrays", reported directly. inferDataFormat replaces that
%   hard-coded assumption in loadSETFile.m/loadMATFile.m with a shape-based
%   derivation.
%
%   Run with: runtests('tests/InferDataFormatTest.m').
%
%   See also LOADSETFILE, LOADMATFILE.

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'Support')));
        end
    end

    methods (Test)
        function twoDimensionalDataWithNoEpochFieldIsContinuous(testCase)
            EEG = struct('data', zeros(4, 100));
            testCase.verifyEqual(inferDataFormat(EEG), 'CONTINUOUS');
        end

        function twoDimensionalDataWithAnEmptyEpochFieldIsStillContinuous(testCase)
        %TWODIMENSIONALDATAWITHANEMPTYEPOCHFIELDISSTILLCONTINUOUS  A
        %   present-but-empty .epoch (EEGLAB's own convention for
        %   continuous data that happens to carry the field) must not be
        %   mistaken for pop_epoch's marker.
            EEG = struct('data', zeros(4, 100), 'epoch', struct('event', {}), 'trials', 1);
            testCase.verifyEqual(inferDataFormat(EEG), 'CONTINUOUS');
        end

        function threeDimensionalMultiTrialDataIsEpoched(testCase)
            EEG = struct('data', zeros(4, 100, 30), 'trials', 30);
            testCase.verifyEqual(inferDataFormat(EEG), 'EPOCHED');
        end

        function singleTrialEpochedDataIsAveraged(testCase)
        %SINGLETRIALEPOCHEDDATAISAVERAGED  A trials==1 epoched/averaged
        %   result -- channels x time x 1 is impossible to represent as a
        %   genuinely 3-D MATLAB array in the first place (zeros(4,100,1)
        %   squeezes its own trailing singleton dimension away, confirmed
        %   directly: ndims(zeros(4,100,1)) is 2, not 3), which is exactly
        %   why the non-empty .epoch marker, not shape, is what has to
        %   catch this case -- matching Average.m's own real output,
        %   which carries its source epoched dataset's .epoch forward
        %   unchanged (stale trial count and all) rather than clearing it.
            EEG = struct('data', zeros(4, 100), 'trials', 1, ...
                'epoch', struct('event', {1}));
            testCase.verifyEqual(inferDataFormat(EEG), 'AVERAGED');
        end

        function squeezedMultiTrialEpochedDataIsStillEpoched(testCase)
        %SQUEEZEDMULTITRIALEPOCHEDDATAISSTILLEPOCHED  Same idea, but
        %   trials > 1 -- the .epoch marker alone must be enough to reach
        %   the trials-count branch at all.
            EEG = struct('data', zeros(4, 100), 'trials', 30, ...
                'epoch', struct('event', {1}));
            testCase.verifyEqual(inferDataFormat(EEG), 'EPOCHED');
        end

        function threeDimensionalDataWithNoTrialsFieldDefaultsToAveraged(testCase)
        %THREEDIMENSIONALDATAWITHNOTRIALSFIELDDEFAULTSTOAVERAGED  Shape
        %   alone says epoched, but with no .trials field to count, the
        %   conservative reading (not "more than one trial") wins.
            EEG = struct('data', zeros(4, 100, 5));
            testCase.verifyEqual(inferDataFormat(EEG), 'AVERAGED');
        end
    end
end
