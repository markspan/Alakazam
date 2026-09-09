classdef BuildHelpPageTest < matlab.unittest.TestCase
%BUILDHELPPAGETEST  Help can build its own page when a clone does not have
%   one, and says something useful when it cannot.
%
%   WHY THIS EXISTS. src/AlakazamHelp.html is about 5 MB of embedded
%   screenshots regenerated from README.MD, so it is gitignored and a fresh
%   clone has none. The Help button used to answer that by printing three
%   npm commands, which asks an analyst to leave the application and find a
%   terminal in order to read the documentation.
%
%   THE FAILURES MATTER MORE THAN THE SUCCESS HERE. Building needs Node,
%   which most analysts running this will not have, so the paths that must
%   be right are the ones that end in a message rather than a page. Each is
%   reached with a real directory rather than a mock: an empty folder for
%   "no builder", a script that exits non-zero for "the build failed", one
%   that exits zero and writes nothing for "reported success but produced
%   nothing".
%
%   The success case is guarded on Node actually being present, since a
%   machine without it is exactly the case the failures above cover.
%
%   Run with: runtests('tests/BuildHelpPageTest.m').
%
%   See also BUILDHELPPAGEINTO, ALAKAZAM.ONHELP, ALAKAZAM.OFFERREADMEINSTEAD.

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'Support')));
        end
    end

    methods (Test)
        function noBuilderIsReportedByName(testCase)
        %NOBUILDERISREPORTEDBYNAME  A copy missing src/help entirely. The
        %   message names the path, since that is the only thing that tells
        %   the reader what is actually wrong.
            folder = testCase.tempFolder();
            [ok, message] = buildHelpPageInto(folder, fullfile(folder, 'out.html'));

            testCase.verifyFalse(ok);
            testCase.verifySubstring(message, 'build.mjs');
        end

        function aFailedBuildReportsWhatTheBuilderSaid(testCase)
        %AFAILEDBUILDREPORTSWHATTHEBUILDERSAID  Not merely "it failed": the
        %   builder's own output is the only thing that says why.
            testCase.assumeTrue(testCase.hasNode(), 'Node is not available.');
            folder = testCase.helpFolderWithScript( ...
                'console.error("marked is not installed"); process.exit(1);');

            [ok, message] = buildHelpPageInto(folder, fullfile(folder, 'out.html'));

            testCase.verifyFalse(ok);
            testCase.verifySubstring(message, 'could not be built');
        end

        function aBuilderThatWritesNothingIsNotASuccess(testCase)
        %ABUILDERTHATWRITESNOTHINGISNOTASUCCESS  Exit status 0 is not proof
        %   of a page. Trusting it would copy a stale file, or fail later in
        %   the viewer with nothing pointing back at the build.
            testCase.assumeTrue(testCase.hasNode(), 'Node is not available.');
            folder = testCase.helpFolderWithScript('process.exit(0);');

            [ok, message] = buildHelpPageInto(folder, fullfile(folder, 'out.html'));

            testCase.verifyFalse(ok);
            testCase.verifySubstring(message, 'wrote no page');
        end

        function aSuccessfulBuildIsCopiedToTheTarget(testCase)
        %ASUCCESSFULBUILDISCOPIEDTOTHETARGET  The copy out of dist/ is the
        %   deploy step build.mjs leaves manual, and the whole point is that
        %   nobody had to run it.
            testCase.assumeTrue(testCase.hasNode(), 'Node is not available.');
            folder = testCase.helpFolderWithScript( ...
                ['import fs from "fs";' newline ...
                 'fs.mkdirSync("dist", { recursive: true });' newline ...
                 'fs.writeFileSync("dist/AlakazamHelp.html", "<html>built</html>");']);
            target = fullfile(testCase.tempFolder(), 'AlakazamHelp.html');

            [ok, message] = buildHelpPageInto(folder, target);

            testCase.verifyTrue(ok, message);
            testCase.verifyEqual(exist(target, 'file'), 2, ...
                'The built page should have been copied to the target.');
            testCase.verifySubstring(fileread(target), 'built');
        end

        function theRealBuilderProducesTheRealPage(testCase)
        %THEREALBUILDERPRODUCESTHEREALPAGE  Against src/help itself, into a
        %   temporary target so the working copy is untouched. This is the
        %   one case that would notice the repository's own build breaking.
            testCase.assumeTrue(testCase.hasNode(), 'Node is not available.');
            root = fileparts(fileparts(mfilename('fullpath')));
            helpDir = fullfile(root, 'src', 'help');
            testCase.assumeTrue(exist(fullfile(helpDir, 'node_modules'), 'dir') == 7, ...
                'node_modules is not installed, and a test must not reach the network.');

            target = fullfile(testCase.tempFolder(), 'AlakazamHelp.html');
            [ok, message] = buildHelpPageInto(helpDir, target);

            testCase.verifyTrue(ok, message);
            page = fileread(target);
            testCase.verifySubstring(page, '<!doctype html>');
            testCase.verifyEmpty(strfind(page, 'GNU GENERAL PUBLIC LICENSE'), ...
                'The help page must link to the licence, not quote it.'); %#ok<STRIFCND>
        end
    end

    methods (Access = private)
        function folder = tempFolder(testCase)
            folder = testCase.applyFixture( ...
                matlab.unittest.fixtures.TemporaryFolderFixture()).Folder;
        end

        function folder = helpFolderWithScript(testCase, javascript)
        %HELPFOLDERWITHSCRIPT  A folder holding a build.mjs that does
        %   whatever JAVASCRIPT says, so each branch is reached through the
        %   real shell-out rather than around it.
        %
        %   The script is an ES MODULE, since that is what the .mjs
        %   extension means to node: require() is undefined there, and a
        %   fixture using it fails to run at all, which looks exactly like
        %   the build-failed case it was meant to contrast with. Relative
        %   paths work because runIn cds into this folder first.
            folder = testCase.tempFolder();
            fid = fopen(fullfile(folder, 'build.mjs'), 'w');
            closeFile = onCleanup(@() fclose(fid)); %#ok<NASGU>
            fprintf(fid, '%s\n', javascript);
        end

        function tf = hasNode(~)
            [status, ~] = system('node --version');
            tf = status == 0;
        end
    end
end
