classdef TestScopeTest < matlab.unittest.TestCase
%TESTSCOPETEST  The quick/full split itself: that it partitions the suite,
%   and that the classes it was built to exclude are actually excluded.
%
%   WHY THIS IS WORTH A TEST. The split is only useful if "quick" stays
%   quick and "full" stays complete, and both decay silently. A Slow tag
%   mistyped as 'slow' excludes nothing and nobody notices, because the
%   quick run still passes, just slower. A tag on a class that has since
%   become cheap costs coverage on every save, equally quietly.
%
%   These cases only build suites, they do not run them, so the whole
%   class costs a few seconds.
%
%   Run with: runtests('tests/TestScopeTest.m').

    properties (Constant)
        % Tagged after measuring, see runAlakazamTests and the Slow note in
        % each one's own header. Named here so that removing a tag has to
        % be a decision rather than an accident.
        DeliberatelySlow = ["SourceClusterReportTest", "SourceEstimateReportTest", ...
            "QuartoReportKnownGapTest", "ForwardModelCacheTest", "InverseFilterCacheTest"]
    end

    properties
        Full
        Quick
        Slow
    end

    methods (TestClassSetup)
        function buildTheSuites(testCase)
            import matlab.unittest.TestSuite
            import matlab.unittest.selectors.HasTag

            folder = fileparts(mfilename('fullpath'));
            testCase.Full = TestSuite.fromFolder(folder);
            testCase.Quick = testCase.Full.selectIf(~HasTag('Slow'));
            testCase.Slow = testCase.Full.selectIf(HasTag('Slow'));
        end
    end

    methods (Test)
        function quickAndSlowPartitionTheWholeSuite(testCase)
        %QUICKANDSLOWPARTITIONTHEWHOLESUITE  Nothing may fall between them:
        %   a case that is in neither is a case that never runs.
            testCase.verifyEqual(numel(testCase.Quick) + numel(testCase.Slow), ...
                numel(testCase.Full), ...
                'Some cases are in neither the quick nor the slow suite.');
        end

        function theSlowSuiteIsNotEmpty(testCase)
        %THESLOWSUITEISNOTEMPTY  Guards the mistyped tag: 'slow' rather
        %   than 'Slow' selects nothing, and a quick run that silently
        %   includes everything still passes.
            testCase.verifyGreaterThan(numel(testCase.Slow), 0);
        end

        function theQuickSuiteIsStillMostOfTheSuite(testCase)
        %THEQUICKSUITEISSTILLMOSTOFTHESUITE  The other direction. Tagging
        %   is for wall clock, not for putting tests out of the way, and a
        %   quick run that has stopped covering most of the code is not
        %   worth running.
            share = numel(testCase.Quick) / numel(testCase.Full);

            testCase.verifyGreaterThan(share, 0.8, ...
                sprintf(['Only %.0f%% of the suite is in the quick run. Slow is ' ...
                    'for cases that are genuinely expensive, not for ones that ' ...
                    'are inconvenient.'], 100 * share));
        end

        function theMeasuredHeavyClassesAreOutOfTheQuickRun(testCase)
            quickNames = arrayfun(@(t) string(extractBefore(t.Name + "/", "/")), ...
                testCase.Quick);

            for name = TestScopeTest.DeliberatelySlow
                testCase.verifyFalse(any(quickNames == name), ...
                    sprintf(['%s was measured as one of the heaviest classes and ' ...
                        'tagged Slow. It is back in the quick run.'], name));
            end
        end

        function everyDeliberatelySlowClassStillExists(testCase)
        %EVERYDELIBERATELYSLOWCLASSSTILLEXISTS  So that a renamed or
        %   deleted class leaves a name here that means nothing, rather
        %   than a check above that silently passes for the wrong reason.
            folder = fileparts(mfilename('fullpath'));

            for name = TestScopeTest.DeliberatelySlow
                testCase.verifyEqual(exist(fullfile(folder, name + ".m"), 'file'), 2, ...
                    sprintf('%s is named as deliberately slow but no longer exists.', name));
            end
        end

        function theRunnerRefusesAScopeItDoesNotHave(testCase)
            testCase.verifyError(@() runAlakazamTests("everything"), ...
                'MATLAB:validators:mustBeMember');
        end
    end
end
