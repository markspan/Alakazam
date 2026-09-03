classdef Template1005Test < matlab.unittest.TestCase
%TEMPLATE1005TEST  The 10-5 electrode template: that there is one of it.
%
%   Alakazam can reach two copies of the standard 10-5 template, dipfit's and
%   FieldTrip's, and reads whichever is available through a single accessor
%   (TransTools.Template1005File). That is only safe while the two agree.
%   They do, exactly, and this asserts it rather than trusting the comment
%   that says so: a silent divergence would put two different sets of
%   electrode positions into one application, with scalp maps drawn from one
%   and leadfields built from the other.
%
%   Run with: runtests('tests/Template1005Test.m').

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            for p = {fullfile(root, 'src'), fullfile(root, 'src', 'Transformations')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
        end
    end

    methods (Test)
        function theAccessorReturnsAReadableTemplate(testCase)
            file = TransTools.Template1005File('Alakazam:Template1005Test');
            testCase.verifyNotEmpty(file);
            testCase.verifyTrue(logical(exist(file, 'file')), ...
                sprintf('The template accessor returned a path that does not exist: %s', file));
        end

        function fieldtripIsPreferredWhenItIsAvailable(testCase)
        %FIELDTRIPISPREFERREDWHENITISAVAILABLE  The preference is about
        %   keeping the electrodes self-consistent with the head model and
        %   cortical sheet FieldTrip ships beside them, not about accuracy:
        %   the positions are identical either way (see below).
            testCase.assumeNotEmpty(which('ft_defaults'), 'FieldTrip is not installed.');
            file = TransTools.Template1005File('Alakazam:Template1005Test');
            testCase.verifySubstring(lower(file), 'fieldtrip');
        end

        function theTwoCopiesAreNumericallyIdentical(testCase)
        %THETWOCOPIESARENUMERICALLYIDENTICAL  The invariant the fallback
        %   rests on. Measured on the parsed positions rather than on the
        %   files, which differ by a few dozen bytes of header whitespace and
        %   by nothing that matters.
            testCase.assumeNotEmpty(which('ft_defaults'), 'FieldTrip is not installed.');
            dipfitFile = TransTools.Dipfit1005File('Alakazam:Template1005Test');
            ftFile = fullfile(fileparts(which('ft_defaults')), ...
                'template', 'electrode', 'standard_1005.elc');
            testCase.assumeTrue(logical(exist(dipfitFile, 'file')), 'dipfit template missing.');
            testCase.assumeTrue(logical(exist(ftFile, 'file')), 'FieldTrip template missing.');

            a = evalc_sens(dipfitFile);
            b = evalc_sens(ftFile);

            testCase.verifyEqual(a.label, b.label, ...
                'The two 10-5 templates no longer carry the same labels in the same order.');
            displacement = sqrt(sum((a.chanpos - b.chanpos) .^ 2, 2));
            testCase.verifyLessThan(max(displacement), 1e-6, ...
                'The two 10-5 templates no longer agree on electrode positions.');
        end
    end
end

% ======================================================================= %
function sens = evalc_sens(file)
%EVALC_SENS  ft_read_sens, without its narration in the test output.
    evalc('sens = ft_read_sens(file);');
end
