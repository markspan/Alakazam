classdef MarkdownRenderTest < matlab.unittest.TestCase
%MARKDOWNRENDERTEST  The pandoc lookup and the language-reference viewer
%   behind the DefineBins dialog's "Syntax..." button.
%
%   There is deliberately no Markdown parser of our own to test. An earlier
%   version of this feature shipped one as a fallback; it was removed
%   because a hand-written converter is a parser to keep correct forever, in
%   a project about EEG. Rendering is pandoc's job, and when pandoc is
%   absent the analyst is offered the Markdown file itself.
%
%   What can be checked without a display, and is: that the lookup answers
%   honestly on any machine, that the viewer refuses a missing document
%   clearly, and -- the one that would actually break in use -- that the
%   path the button computes points at a file that exists.
%
%   Run with: runtests('tests/MarkdownRenderTest.m').

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'Support')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'Dialogs')));
        end
    end

    methods (Test)
        function theLookupAnswersOnAnyMachine(testCase)
        %THELOOKUPANSWERSONANYMACHINE  Either a real executable or an empty
        %   string, never an error and never a path to something absent.
        %   Which one it is depends on the machine, so that is not asserted.
            exe = pandocExe();

            testCase.verifyTrue(ischar(exe) || isstring(exe));
            if ~isempty(exe)
                testCase.verifyEqual(exist(char(exe), 'file'), 2, ...
                    sprintf('pandocExe returned "%s", which is not a file.', exe));
            end
        end

        function theLookupIsStable(testCase)
        %THELOOKUPISSTABLE  Cached for the session, since a miss costs two
        %   shell-outs and the answer cannot change while the app runs.
            testCase.verifyEqual(pandocExe(), pandocExe());
        end

        function aMissingDocumentIsRefusedClearly(testCase)
            testCase.verifyError(@() MarkdownDialog('T', 'no-such-document.md'), ...
                'Alakazam:MarkdownDialog:missing');
        end

        % ---- what would actually break -------------------------------------
        function theSyntaxButtonPointsAtARealFile(testCase)
        %THESYNTAXBUTTONPOINTSATAREALFILE  The button builds the reference's
        %   path from the dialog's own location, two fileparts up and back
        %   down. Move either file and that silently points at nothing --
        %   which would only show as a failure when somebody clicked it.
            root = fileparts(fileparts(mfilename('fullpath')));
            src = fileread(fullfile(root, 'src', 'Dialogs', 'DefineBinsDialog.m'));

            testCase.verifySubstring(src, 'MarkdownDialog(', ...
                'The Syntax button no longer opens the reference viewer.');
            testCase.verifySubstring(src, 'bin_language.md');

            % The path the button computes: src/Dialogs/.. -> src, then down.
            testCase.verifyEqual(exist(fullfile(root, 'src', 'Transformations', ...
                'DefineBins', 'bin_language.md'), 'file'), 2, ...
                'The language reference is not where the Syntax button looks for it.');
        end

        function theReferenceIsWorthOpening(testCase)
        %THEREFERENCEISWORTHOPENING  A button that opened an empty or stub
        %   document would pass every check above.
            root = fileparts(fileparts(mfilename('fullpath')));
            md = fileread(fullfile(root, 'src', 'Transformations', ...
                'DefineBins', 'bin_language.md'));

            testCase.verifyGreaterThan(numel(md), 5000);
            testCase.verifySubstring(md, '# The bin-definition language');
        end
    end
end
