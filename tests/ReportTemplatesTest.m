classdef ReportTemplatesTest < matlab.unittest.TestCase
%REPORTTEMPLATESTEST  The report templates in src/Reports/rscripts and the
%   MATLAB that asks for them, held to each other.
%
%   The R and the Quarto fragments the report generators emit live in files
%   now (see ReportDoc.template), which buys an editor that knows the
%   language and a parser that can check it, and costs one thing: a name in
%   a MATLAB string has to match a file on disk. A typo there is a hard
%   error at generation time, which any report test would catch, but a
%   template that nothing asks for any more is invisible: it just sits there
%   looking current. Both directions are checked here.
%
%   THE R PARSE CASE IS THE POINT OF THE EXERCISE. Before this, the only
%   check on the generated R was a Quarto render, which needs R and Quarto
%   installed and renders a whole document. A .R template can be handed
%   straight to R's own parser, one file at a time, so a syntax error names
%   the file it is in. It still needs R, so it skips cleanly without one
%   (assumeTrue, not a failure), exactly as the render tests do.
%
%   Deliberately not checked: that a .qmd fragment parses. It is markdown
%   with fences and __TOKEN__ placeholders, so no parser takes it as it
%   stands; QuartoReportRSyntaxTest covers those by parsing the chunks of
%   the assembled document instead.
%
%   Run with: runtests('tests/ReportTemplatesTest.m').
%
%   See also REPORTDOC.TEMPLATE, QUARTOREPORTRSYNTAXTEST.

    properties (Constant)
        Root = fileparts(fileparts(mfilename('fullpath')))
    end

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            for p = {fullfile(ReportTemplatesTest.Root, 'src'), ...
                     fullfile(ReportTemplatesTest.Root, 'src', 'Reports'), ...
                     fullfile(ReportTemplatesTest.Root, 'tests')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
        end
    end

    methods (Test)
        function everyTemplateAskedForExists(testCase)
            [asked, where] = ReportTemplatesTest.referenced();
            testCase.assertNotEmpty(asked, 'No ReportDoc.template call was found at all, which cannot be right.');
            for k = 1:numel(asked)
                file = fullfile(ReportTemplatesTest.templateDir(), asked{k});
                testCase.verifyTrue(isfile(file), sprintf( ...
                    '%s asks for the template "%s", which is not in src/Reports/rscripts.', where{k}, asked{k}));
            end
        end

        function everyTemplateIsAskedFor(testCase)
            asked = ReportTemplatesTest.referenced();
            for f = ReportTemplatesTest.templateFiles()
                testCase.verifyTrue(any(strcmp(asked, f{1})), sprintf( ...
                    ['The template "%s" is in src/Reports/rscripts but nothing asks for it. Either a ' ...
                     'generator stopped using it, in which case it should go, or the name was ' ...
                     'changed on one side only.'], f{1}));
            end
        end

        function aTemplateLoadsAsTheLinesItHolds(testCase)
            name = 'apa-helpers.R';
            file = fullfile(ReportTemplatesTest.templateDir(), name);
            % CollapseDelimiters must be off: these templates have blank
            % lines, and collapsing them would make the expectation shorter
            % than the file and the test pass for the wrong reason.
            expected = strsplit(strrep(fileread(file), sprintf('\r\n'), newline), newline, ...
                'CollapseDelimiters', false);
            if isempty(expected{end})
                expected = expected(1:end - 1);
            end

            lines = ReportDoc.template(name);

            testCase.verifyEqual(lines, expected, 'Nothing is added to or taken from the file.');
            testCase.verifyTrue(iscell(lines) && all(cellfun(@ischar, lines)));
        end

        function aMissingTemplateSaysWhichAndWhere(testCase)
            message = '';
            try
                ReportDoc.template('no-such-template.R');
            catch err
                testCase.verifyEqual(err.identifier, 'Alakazam:ReportDoc:missingTemplate');
                message = err.message;
            end
            testCase.assertNotEmpty(message, 'A missing template has to be refused, not read as empty.');
            testCase.verifySubstring(message, 'no-such-template.R');
            testCase.verifySubstring(message, 'rscripts');
        end

        function blocksAreSplicedWhereTheySit(testCase)
            flat = ReportDoc.lines({'a', {'b', 'c'}, 'd', {{'e'}}});

            testCase.verifyEqual(flat, {'a', 'b', 'c', 'd', 'e'});
            testCase.verifyError(@() ReportDoc.lines({'a', 7}), 'Alakazam:ReportDoc:badLine');
        end
    end

    methods (Test, TestTags = {'External'})
        function everyRTemplateParsesAsR(testCase)
            rscript = ReportFixtures.rscriptExe();
            testCase.assumeTrue(~isempty(rscript), 'R is not installed.');
            folder = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture()).Folder;
            for f = ReportTemplatesTest.templateFiles()
                if ~endsWith(f{1}, '.R')   % .Rpart is a fragment; see this file's header
                    continue;
                end
                file = fullfile(ReportTemplatesTest.templateDir(), f{1});
                copy = fullfile(folder, 'template.R');
                copyfile(file, copy);
                cmd = sprintf('"%s" -e "invisible(parse(\\"%s\\"))"', rscript, ...
                    strrep(copy, '\', '/'));
                [status, out] = system(cmd);
                testCase.verifyEqual(status, 0, sprintf( ...
                    'R could not parse the template "%s":\n%s', f{1}, out));
            end
        end
    end

    methods (Static)
        function d = templateDir()
            d = fullfile(ReportTemplatesTest.Root, 'src', 'Reports', 'rscripts');
        end

        function names = templateFiles()
        %TEMPLATEFILES  Every template on disk, as a cell row. The folder's
        %   own README is documentation, not a template.
            d = [dir(fullfile(ReportTemplatesTest.templateDir(), '*.R')); ...
                 dir(fullfile(ReportTemplatesTest.templateDir(), '*.Rpart')); ...
                 dir(fullfile(ReportTemplatesTest.templateDir(), '*.qmd'))];
            d = d(~[d.isdir]);
            names = reshape({d.name}, 1, []);
        end

        function [asked, where] = referenced()
        %REFERENCED  Every name a ReportDoc.template call asks for, and the
        %   file that asks, read from the source rather than by running it:
        %   a template used only by one branch of one section would never be
        %   reached by a test that generated reports instead.
            asked = {};
            where = {};
            files = dir(fullfile(ReportTemplatesTest.Root, 'src', 'Reports', '**', '*.m'));
            for k = 1:numel(files)
                text = fileread(fullfile(files(k).folder, files(k).name));
                hits = regexp(text, 'ReportDoc\.template\(''([^'']+)''\)', 'tokens');
                for h = 1:numel(hits)
                    asked{end + 1} = hits{h}{1}; %#ok<AGROW>
                    where{end + 1} = files(k).name; %#ok<AGROW>
                end
            end
            [asked, idx] = unique(asked, 'stable');
            where = where(idx);
        end
    end
end
