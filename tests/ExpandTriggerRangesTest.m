classdef ExpandTriggerRangesTest < matlab.unittest.TestCase
%EXPANDTRIGGERRANGESTEST  Unit tests for
%   src/Transformations/Photodiode/expandTriggerRanges.m, the Triggers
%   field's "40:43" shorthand (PhotodiodeDialog).
%
%   Run with: runtests('tests/ExpandTriggerRangesTest.m').

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'Transformations', 'Photodiode')));
        end
    end

    methods (Test)
        function aPlainRangeExpands(testCase)
            testCase.verifyEqual(expandTriggerRanges({'40:43'}), {'40', '41', '42', '43'});
        end

        function aSteppedRangeExpands(testCase)
            testCase.verifyEqual(expandTriggerRanges({'40:2:48'}), {'40', '42', '44', '46', '48'});
        end

        function nonRangeTokensPassThroughUnchanged(testCase)
        %NONRANGETOKENSPASSTHROUGHUNCHANGED  A bare code and a string type,
        %   the two other shapes the Triggers field actually holds day to
        %   day, must survive untouched.
            testCase.verifyEqual(expandTriggerRanges({'s106', '106'}), {'s106', '106'});
        end

        function aRangeMixedWithOrdinaryTokensExpandsInPlace(testCase)
            testCase.verifyEqual(expandTriggerRanges({'s106', '40:43', '106'}), ...
                {'s106', '40', '41', '42', '43', '106'});
        end

        function aZeroStepIsLeftLiteral(testCase)
        %AZEROSTEPISLEFTLITERAL  "40:0:43" describes no motion at all;
        %   a:0:b would otherwise divide the codes list by nothing.
            testCase.verifyEqual(expandTriggerRanges({'40:0:43'}), {'40:0:43'});
        end

        function aDescendingRangeWithNoStepIsLeftLiteral(testCase)
        %ADESCENDINGRANGEWITHNOSTEPISLEFTLITERAL  "43:40" with an implicit
        %   step of +1 counts down past its own end and produces nothing;
        %   left as typed rather than silently vanishing from the list.
            testCase.verifyEqual(expandTriggerRanges({'43:40'}), {'43:40'});
        end

        function anImplausiblyWideRangeIsLeftLiteral(testCase)
        %ANIMPLAUSIBLYWIDERANGEISLEFTLITERAL  "4:34000" is a typo for
        %   something, not a real trigger list; expanding it would hang the
        %   dialog rebuilding its preview over 34000 synthetic codes.
            result = expandTriggerRanges({'4:34000'});
            testCase.verifyEqual(result, {'4:34000'});
        end

        function notEvalIsUsedToParseIt(testCase)
        %NOTEVALISUSEDTOPARSEIT  A guard against reintroducing eval: a token
        %   that would be dangerous if evaluated, but is not a plain integer
        %   range, must come back untouched rather than executed.
            result = expandTriggerRanges({'system(''echo pwned'')'});
            testCase.verifyEqual(result, {'system(''echo pwned'')'});
        end
    end
end
