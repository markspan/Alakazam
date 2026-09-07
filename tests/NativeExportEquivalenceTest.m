classdef NativeExportEquivalenceTest < matlab.unittest.TestCase
%NATIVEEXPORTEQUIVALENCETEST  A native call emitted by the analysis-script
%   export must produce exactly what the transformation it replaces does.
%
%   WHY THIS FILE IS THE POINT OF THE FEATURE. Emitting library calls into
%   an exported script is attractive precisely because the script can then
%   be run without Alakazam, which is also what makes it dangerous: a
%   reviewer runs it, gets numbers that differ, and has been handed a
%   document that looks authoritative. "It produced a script" is no
%   evidence at all that the script reproduces the analysis.
%
%   So every transformation the exporter is allowed to spell natively gets
%   a case here that runs BOTH and compares the data. A native emission
%   without a case in this file is not a translation, it is a guess.
%
%   Run with: runtests('tests/NativeExportEquivalenceTest.m').
%
%   See also EXPORTANALYSISSCRIPT, EXPORTANALYSISSCRIPTTEST.

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'Transformations', 'Resample')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'Transformations')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'IO')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'Support')));
        end

        function requireEeglab(testCase)
            testCase.assumeTrue(exist('pop_resample', 'file') == 2, ...
                'EEGLAB is not on the path, so the native call cannot be run.');
        end
    end

    methods (Test)
        function resampleMatchesPopResample(testCase)
        %RESAMPLEMATCHESPOPRESAMPLE  The one native emission currently made.
        %   Resample.m is pop_resample(input, options.NewRate) and nothing
        %   else, so the emitted line should be the identical call. This
        %   runs both and compares the samples, not the shape.
            rng(4);
            EEG = struct();
            EEG.data = randn(3, 500);
            EEG.srate = 500;
            EEG.nbchan = 3;
            EEG.pnts = 500;
            EEG.trials = 1;
            EEG.times = (0:499) / 500 * 1000;
            EEG.chanlocs = struct('labels', {'Cz', 'Pz', 'Oz'});
            EEG.event = [];
            EEG.setname = 'fixture';
            EEG.xmin = 0;
            EEG.xmax = 499 / 500;
            EEG.DataFormat = 'CONTINUOUS';

            viaTransform = Resample(EEG, struct('NewRate', 250));
            viaNative = pop_resample(EEG, 250);

            testCase.verifyEqual(size(viaNative.data), size(viaTransform.data), ...
                'The native call produced a different number of samples.');
            testCase.verifyEqual(viaNative.data, viaTransform.data, 'AbsTol', 1e-12, ...
                'The native call produced different sample values.');
            testCase.verifyEqual(viaNative.srate, viaTransform.srate);
        end

        function everyNativeEmissionHasAnEquivalenceCase(testCase)
        %EVERYNATIVEEMISSIONHASANEQUIVALENCECASE  The guard on this file's
        %   own completeness.
        %
        %   Reads the exporter's switch and asserts that each transformation
        %   it is willing to spell natively is named by a test here. Adding
        %   a native emission without adding a case makes THIS case fail,
        %   which is the only way the requirement stays true as the
        %   exporter grows.
            root = fileparts(fileparts(mfilename('fullpath')));
            src = fileread(fullfile(root, 'src', 'IO', 'exportAnalysisScript.m'));

            body = extractBetween(src, 'function call = nativeCall(', ...
                'function params = paramsFor(');
            testCase.assertNotEmpty(body, 'nativeCall could not be located.');

            emitted = regexp(body{1}, '^\s*case\s+''(\w+)''', 'tokens', 'lineanchors');
            emitted = cellfun(@(c) c{1}, emitted, 'UniformOutput', false);

            covered = {'Resample'};
            missing = setdiff(emitted, covered);
            testCase.verifyEmpty(missing, sprintf( ...
                ['These transformations are emitted as native calls but have no ' ...
                 'equivalence case here: %s. A native emission nothing compares ' ...
                 'against is a guess.'], strjoin(missing, ', ')));
        end
    end
end
