classdef EnsureTfceMexTest < matlab.unittest.TestCase
%ENSURETFCEMEXTEST  That TransTools.EnsureTfceMex's cached answer stays
%   true, rather than merely staying TRUE.
%
%   EnsureTfceMex caches whether the compiled kernel is usable, because a
%   failed build must not be retried on every permutation. But what makes
%   the kernel usable is src/mex/bin being on the path, and the cache does
%   not hold the path entry, only the memory of having added it. Those two
%   come apart in a full-suite run: matlab.unittest's PathFixture restores a
%   path snapshot when a test class tears down, and the snapshot predates
%   the addpath, so a later class inherits a cached TRUE with no kernel
%   behind it. TransTools.TfceScore then trusts the flag, as its own header
%   says it deliberately does, and dies on "Undefined function
%   'alakazam_tfce' for input arguments of type 'int32'" inside a
%   permutation. That is a crash, not the documented fallback to
%   FieldTrip's own TFCE, and it is invisible to any test that runs the
%   class on its own.
%
%   Observed as SourceClusterStatsTest/theWholePipelineRunsOnRealSubjects
%   passing alone and erroring in a full-suite run. The path removal is
%   done here directly, in one process, because reproducing it through the
%   fixtures would need a guaranteed ordering between two test classes that
%   the framework does not offer.
%
%   Run with: runtests('tests/EnsureTfceMexTest.m').
%
%   See also TRANSTOOLS.ENSURETFCEMEX, TRANSTOOLS.ENSUREGIFTIREADER,
%   SOURCECLUSTERMEXTEST.

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            for p = {fullfile(root, 'src'), fullfile(root, 'src', 'Transformations')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
        end
    end

    methods (Test)
        function theCachedAnswerSurvivesLosingItsPathEntry(testCase)
        %THECACHEDANSWERSURVIVESLOSINGITSPATHENTRY  Succeed once, lose the
        %   folder, ask again: the second answer has to be backed by a
        %   kernel that can actually be called, not by the memory of one.
            binDir = fullfile(fileparts(fileparts(mfilename('fullpath'))), ...
                'src', 'mex', 'bin');
            testCase.assumeTrue(TransTools.EnsureTfceMex(), 'No compiled TFCE kernel.');
            testCase.assertNotEmpty(which('alakazam_tfce'), ...
                'A successful EnsureTfceMex must leave the kernel on the path.');
            testCase.addTeardown(@() addpath(binDir));

            % What another class's PathFixture teardown does, without the
            % other class.
            rmpath(binDir);
            testCase.assertEqual(exist('alakazam_tfce', 'file'), 0, ...
                'The kernel must really be gone, or this test proves nothing.');

            testCase.verifyTrue(TransTools.EnsureTfceMex(), ...
                'The kernel is still built, so the answer is still yes.');
            testCase.verifyNotEqual(exist('alakazam_tfce', 'file'), 0, ...
                'Saying yes means having put the kernel back on the path.');

            % Callable, not merely visible: the failure being guarded
            % against is an undefined-function error at the call site, so
            % the call is what gets made. An isolated point is its own
            % component of extent 1, so TFCE reduces to
            % (1/(H+1)) * 1^E * v^(H+1), the same hand-checkable case
            % SourceClusterMexTest pins the exponent convention with.
            score = alakazam_tfce([0; 2], zeros(0, 2, 'int32'), 0.5, 2);
            testCase.verifyEqual(score, [0; (1 / 3) * 2^3], 'AbsTol', 1e-12);
        end
    end
end
