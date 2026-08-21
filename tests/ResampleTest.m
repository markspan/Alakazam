classdef ResampleTest < matlab.unittest.TestCase
%RESAMPLETEST  Unit tests for src/Transformations/Resample/Resample.m.
%
%   The actual resampling math is entirely EEGLAB's own pop_resample; the
%   one test that needs it (actualResamplingChangesSrateAndData) is
%   guarded by assumeTrue, which skips -- not fails -- if EEGLAB is
%   unavailable. Everything else here is Alakazam's own validation and
%   no-op-shortcut logic, needing no EEGLAB at all.
%
%   Run with: runtests('tests/ResampleTest.m').

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'Transformations', 'Resample')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'Transformations')));
        end
    end

    methods (Test)
        function rejectsNoData(testCase)
            EEG = struct('data', [], 'DataFormat', 'CONTINUOUS', 'srate', 250);
            opts = struct('NewRate', 125);
            testCase.verifyError(@() Resample(EEG, opts), 'Alakazam:Resample');
        end

        function rejectsNonContinuousData(testCase)
            EEG = continuousFixture();
            EEG.DataFormat = 'EPOCHED';
            opts = struct('NewRate', 125);
            testCase.verifyError(@() Resample(EEG, opts), 'Alakazam:Resample');
        end

        function rejectsNonPositiveRate(testCase)
            EEG = continuousFixture();
            opts = struct('NewRate', -10);
            testCase.verifyError(@() Resample(EEG, opts), 'Alakazam:Resample');
        end

        function rejectsNonNumericRate(testCase)
            EEG = continuousFixture();
            opts = struct('NewRate', 'fast');
            testCase.verifyError(@() Resample(EEG, opts), 'Alakazam:Resample');
        end

        function noOpWhenRateAlreadyMatches(testCase)
            EEG = continuousFixture();
            opts = struct('NewRate', EEG.srate);

            [result, ~] = Resample(EEG, opts);

            testCase.verifyEqual(result, EEG);
        end
    end
end

function EEG = continuousFixture()
    EEG = struct();
    EEG.data       = zeros(2, 500);
    EEG.srate      = 250;
    EEG.DataFormat = 'CONTINUOUS';
    EEG.times      = (0:499) / 250;
end
