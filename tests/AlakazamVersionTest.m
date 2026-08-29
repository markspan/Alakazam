classdef AlakazamVersionTest < matlab.unittest.TestCase
%ALAKAZAMVERSIONTEST  Unit tests for src/alakazamVersion.m.
%
%   The version used to be a hand-typed constant, and was found a release
%   behind the repository's own tags the first time anything checked. It is
%   now derived: from the VERSION file a release package carries, from
%   `git describe` in a checkout, or from that constant as a last resort.
%
%   WHAT THESE TESTS CANNOT REACH. Which of the three sources answers
%   depends on where the code is running, and the packaged branch needs a
%   VERSION file at the repository root that no test should create there.
%   So these pin the contract -- every field present, the version shaped
%   like this repository's own tags, the source named honestly -- and the
%   fallback constant's own shape, which is the part that silently rots.
%
%   Run with: runtests('tests/AlakazamVersionTest.m').

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'Support')));
        end
    end

    methods (Test)
        function theStructIsComplete(testCase)
            info = alakazamVersion();

            for field = {'Name', 'Version', 'VersionSource', 'Tagline', ...
                    'Author', 'Email', 'Repository', 'Issues', 'Releases', 'License'}
                testCase.assertTrue(isfield(info, field{1}), ...
                    sprintf('alakazamVersion should return a %s.', field{1}));
                testCase.verifyNotEmpty(strtrim(info.(field{1})), ...
                    sprintf('%s should not be blank.', field{1}));
            end
        end

        function theVersionLooksLikeATag(testCase)
        %THEVERSIONLOOKSLIKEATAG  Capital-V and a digit: this repository's
        %   own convention, and what the release workflow triggers on. Both
        %   derived sources check this before accepting a value, so a
        %   VERSION file holding something else, or a `git describe` that
        %   returned a bare hash, falls through rather than being displayed.
            info = alakazamVersion();

            testCase.verifyNotEmpty(regexp(info.Version, '^[vV]\d', 'once'), ...
                sprintf('"%s" does not look like a version tag.', info.Version));
        end

        function theSourceIsOneOfTheThree(testCase)
        %THESOURCEISONEOFTHETHREE  Shown in the About box, so it has to name
        %   a real provenance rather than an internal state.
            info = alakazamVersion();

            testCase.verifyTrue(ismember(info.VersionSource, ...
                {'release package', 'git checkout', 'built in'}), ...
                sprintf('Unexpected version source "%s".', info.VersionSource));
        end

        function repeatedCallsAgree(testCase)
        %REPEATEDCALLSAGREE  The result is cached in a persistent, since
        %   resolving it shells out to git. A cache that returned something
        %   different on a later call would be worse than no cache.
            first = alakazamVersion();
            second = alakazamVersion();

            testCase.verifyEqual(second.Version, first.Version);
            testCase.verifyEqual(second.VersionSource, first.VersionSource);
        end

        function theFallbackConstantIsStillAValidTag(testCase)
        %THEFALLBACKCONSTANTISSTILLAVALIDTAG  Read out of the source,
        %   because it is unreachable in a checkout: git answers first, so
        %   nothing else would ever notice this being emptied or mistyped.
        %   It is what an analyst sees if they run an unpacked copy that is
        %   neither a release nor a repository.
            root = fileparts(fileparts(mfilename('fullpath')));
            source = fileread(fullfile(root, 'src', 'alakazamVersion.m'));

            token = regexp(source, 'VERSION_FALLBACK\s*=\s*''([^'']*)''', 'tokens', 'once');
            testCase.assertNotEmpty(token, 'VERSION_FALLBACK has gone missing.');
            testCase.verifyNotEmpty(regexp(token{1}, '^[vV]\d', 'once'), ...
                sprintf('The fallback "%s" is not shaped like a tag.', token{1}));
        end

        function theReleaseWorkflowStampsTheVersion(testCase)
        %THERELEASEWORKFLOWSTAMPSTHEVERSION  The packaged branch only works
        %   if the workflow actually writes the file, and a release package
        %   is not something a test can build. Checking that the step is
        %   still there is the next best thing, and catches it being
        %   dropped in an unrelated edit to the workflow.
            root = fileparts(fileparts(mfilename('fullpath')));
            workflow = fileread(fullfile(root, '.github', 'workflows', 'release.yml'));

            testCase.verifySubstring(workflow, '/VERSION"', ...
                'The workflow no longer writes a VERSION stamp into the package.');
        end
    end
end
