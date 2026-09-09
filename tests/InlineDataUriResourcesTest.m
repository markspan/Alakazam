classdef InlineDataUriResourcesTest < matlab.unittest.TestCase
%INLINEDATAURIRESOURCESTEST  Turning Quarto's data: URIs into inline
%   <style> and <script>, which is what makes a report readable in the
%   app's own viewer.
%
%   WHY THE FUNCTION EXISTS. uihtml does not open a local file directly:
%   MATLAB serves it from its connector over https://127.0.0.1:<port>/,
%   and that server's Content-Security-Policy refuses data: stylesheets and
%   data: scripts while allowing data: images. Quarto's self-contained
%   output puts the entire Bootstrap theme in one data: stylesheet, so the
%   app was rendering every report with no theme at all. Measured in a real
%   uihtml, before and after, on the data quality report:
%
%       live CSS rules   2110 -> 4408
%       body font        Times New Roman -> Source Sans Pro
%       a 2100 px figure drawn at 2100 px -> 569 px, in an 885 px pane
%
%   WHAT THE CASES BELOW ARE GUARDING. Mostly the decoding, because the
%   obvious way to write it is wrong: urldecode is form decoding, where '+'
%   is a space, and a stylesheet is full of '+' in sibling selectors. Then
%   the things that must survive the move: an id, a type="module", UTF-8,
%   and the position in the cascade.
%
%   Run with: runtests('tests/InlineDataUriResourcesTest.m').

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            here = fileparts(mfilename('fullpath'));
            root = fileparts(here);
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'Support')));
        end
    end

    methods (Test)
        function aPercentEncodedStylesheetIsInlined(testCase)
            file = testCase.writePage([ ...
                '<link href="data:text/css,%23a%20%7B%20color%3A%20red%3B%20%7D" ' ...
                'rel="stylesheet">']);

            count = inlineDataUriResources(file);
            html = fileread(file);

            testCase.verifyEqual(count, 1);
            testCase.verifySubstring(html, '#a { color: red; }');
            testCase.verifySubstring(html, '<style>');
            testCase.verifyEmpty(strfind(html, 'data:text/css'), ...
                'The link should be gone, not merely duplicated.'); %#ok<STREMP>
        end

        function aBase64StylesheetIsInlined(testCase)
            css = '#b { color: blue; }';
            uri = ['data:text/css;base64,' ...
                matlab.net.base64encode(unicode2native(css, 'UTF-8'))];
            file = testCase.writePage(['<link href="' uri '" rel="stylesheet">']);

            testCase.verifyEqual(inlineDataUriResources(file), 1);
            testCase.verifySubstring(fileread(file), css);
        end

        function aPlusSignIsNotTurnedIntoASpace(testCase)
        %APLUSSIGNISNOTTURNEDINTOASPACE  The trap this decoder exists to
        %   avoid. urldecode reads '+' as a space, because that is what form
        %   encoding means by it. In CSS, ".a + .b" is the next-sibling
        %   combinator and ".a   .b" is the descendant one, so the mistake
        %   silently changes which elements the rule matches.
            file = testCase.writePage( ...
                '<link href="data:text/css,.a+.b%20%7B%20color%3A%20red%3B%20%7D" rel="stylesheet">');

            inlineDataUriResources(file);

            testCase.verifySubstring(fileread(file), '.a+.b { color: red; }');
        end

        function utf8SurvivesTheRoundTrip(testCase)
        %UTF8SURVIVESTHEROUNDTRIP  Percent encoding is over bytes, so a
        %   non-ASCII character arrives as two of them and has to be decoded
        %   as UTF-8, then written back as UTF-8 whatever the platform
        %   default is.
            file = testCase.writePage( ...
                '<link href="data:text/css,%23u%3A%3Aafter%7Bcontent%3A%22%C3%A9%22%7D" rel="stylesheet">');

            inlineDataUriResources(file);
            html = fileread(file, 'Encoding', 'UTF-8');

            testCase.verifySubstring(html, ['content:"' char(233) '"']);
        end

        function aModuleScriptKeepsItsType(testCase)
        %AMODULESCRIPTKEEPSITSTYPE  Quarto's own scripts are type="module",
        %   which is not decoration: a module has its own scope and runs
        %   deferred. Dropping the attribute would put its declarations in
        %   the global scope and run it earlier.
            js = 'window.__x = 1;';
            uri = ['data:application/javascript;base64,' ...
                matlab.net.base64encode(unicode2native(js, 'UTF-8'))];
            file = testCase.writePage(['<script src="' uri '" type="module"></script>']);

            testCase.verifyEqual(inlineDataUriResources(file), 1);
            html = fileread(file);

            testCase.verifySubstring(html, '<script type="module">');
            testCase.verifySubstring(html, js);
        end

        function theStylesheetIdIsCarriedOver(testCase)
            file = testCase.writePage([ ...
                '<link href="data:text/css,%23a%7B%7D" rel="stylesheet" ' ...
                'id="quarto-bootstrap" data-mode="light">']);

            inlineDataUriResources(file);

            testCase.verifySubstring(fileread(file), '<style id="quarto-bootstrap">');
        end

        function theInlinedRuleKeepsItsPlaceInTheCascade(testCase)
        %THEINLINEDRULEKEEPSITSPLACEINTHECASCADE  Two rules of equal
        %   specificity are decided by order, so a stylesheet that moves up
        %   or down the head changes what wins.
            file = testCase.writePage([ ...
                '<style>#a { color: green; }</style>' newline ...
                '<link href="data:text/css,%23a%20%7B%20color%3A%20red%3B%20%7D" rel="stylesheet">' newline ...
                '<style>/* last */</style>']);

            inlineDataUriResources(file);
            html = fileread(file);

            testCase.verifyLessThan(strfind(html, 'color: green'), ...
                strfind(html, 'color: red'));
            testCase.verifyLessThan(strfind(html, 'color: red'), ...
                strfind(html, '/* last */'));
        end

        function dataImagesAreLeftAlone(testCase)
        %DATAIMAGESARELEFTALONE  They load under the policy, they are most
        %   of the file, and decoding one only means encoding it again.
            img = '<img src="data:image/png;base64,iVBORw0KGgo=">';
            file = testCase.writePage(img);

            testCase.verifyEqual(inlineDataUriResources(file), 0);
            testCase.verifySubstring(fileread(file), img);
        end

        function ordinaryLinksAndScriptsAreLeftAlone(testCase)
            markup = ['<link href="https://example.org/a.css" rel="stylesheet">' newline ...
                '<script src="https://example.org/a.js"></script>'];
            file = testCase.writePage(markup);

            testCase.verifyEqual(inlineDataUriResources(file), 0);
            testCase.verifySubstring(fileread(file), markup);
        end

        function aStylesheetCarryingAClosingTagIsLeftAlone(testCase)
        %ASTYLESHEETCARRYINGACLOSINGTAGISLEFTALONE  '</style' inside the
        %   text would close the element early. Escaping it is only valid
        %   inside a CSS string, so the link stays: a report that renders in
        %   a browser but not in the app beats one that renders wrongly in
        %   both.
            file = testCase.writePage( ...
                '<link href="data:text/css,%23a%7Bcontent%3A%22%3C%2Fstyle%3E%22%7D" rel="stylesheet">');

            testCase.verifyEqual(inlineDataUriResources(file), 0);
            testCase.verifySubstring(fileread(file), 'data:text/css');
        end

        function aFileWithNothingToInlineIsNotRewritten(testCase)
            file = testCase.writePage('<p>nothing here</p>');
            before = dir(file);
            pause(0.01);

            testCase.verifyEqual(inlineDataUriResources(file), 0);

            after = dir(file);
            testCase.verifyEqual(after.datenum, before.datenum, ...
                'A file with nothing to change should not have been touched.');
        end

        function aMissingFileIsAnError(testCase)
            testCase.verifyError(@() inlineDataUriResources('no_such_file.html'), ...
                'Alakazam:inlineDataUriResources:noFile');
        end

        function everyStylesheetAndScriptInOnePageIsInlined(testCase)
            file = testCase.writePage([ ...
                '<link href="data:text/css,%23a%7B%7D" rel="stylesheet">' newline ...
                '<link href="data:text/css,%23b%7B%7D" rel="stylesheet">' newline ...
                '<script src="data:application/javascript;base64,dmFyIHggPSAxOw==" type="module"></script>']);

            testCase.verifyEqual(inlineDataUriResources(file), 3);
        end

        function theRendererCallsIt(testCase)
        %THERENDERERCALLSIT  Weaker than an end-to-end render, which needs
        %   quarto and R, but it still fails if the call is dropped.
            root = fileparts(fileparts(mfilename('fullpath')));
            source = fileread(fullfile(root, 'src', 'IO', 'renderQuartoReport.m'));

            testCase.verifySubstring(source, 'inlineDataUriResources(expectedHtml)');
        end
    end

    methods (Access = private)
        function file = writePage(testCase, headMarkup)
        %WRITEPAGE  A minimal page carrying HEADMARKUP, in a temp folder.
            folder = testCase.applyFixture( ...
                matlab.unittest.fixtures.TemporaryFolderFixture()).Folder;
            file = fullfile(folder, 'page.html');

            fid = fopen(file, 'w', 'n', 'UTF-8');
            testCase.assertGreaterThan(fid, 0);
            closer = onCleanup(@() fclose(fid)); %#ok<NASGU>
            fprintf(fid, '%s', ['<!DOCTYPE html><html><head>' newline ...
                headMarkup newline '</head><body><p>body</p></body></html>']);
        end
    end
end
