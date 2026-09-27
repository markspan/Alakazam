classdef BuildHelpPageTest < matlab.unittest.TestCase
%BUILDHELPPAGETEST  Help shows the manual, prepared by buildHelpPageInto.
%
%   The help page is the manual (manual/), not in version control, so a
%   fresh clone has none until it is prepared: copied from a rendered
%   manual/manual.html when that is current (a release ships one), or
%   rendered with Quarto first when it is missing or older than its sources.
%
%   THE FAILURES MATTER AS MUCH AS THE SUCCESS: most machines running this
%   have no Quarto on the PATH, so the paths that end in a message must be
%   right. Each is reached with a real folder, and Quarto is replaced by a
%   locator returning '' (absent) or a small script standing in for it
%   (present), so no case depends on the machine.
%
%   Every prepared page must also work in the app's viewer: no stylesheet
%   or script left as a data: URI (the viewer's policy refuses them), and
%   the bridge that hands outside links to MATLAB.
%
%   Run with: runtests('tests/BuildHelpPageTest.m').
%
%   See also BUILDHELPPAGEINTO, ALAKAZAM.ONHELP, ALAKAZAM.OFFERMANUALINSTEAD.

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'Support')));
        end
    end

    methods (Test)
        function noManualIsReportedByName(testCase)
            folder = testCase.tempFolder();
            target = fullfile(testCase.tempFolder(), 'AlakazamHelp.html');

            [ok, message] = buildHelpPageInto(folder, target, @() '');

            testCase.verifyFalse(ok);
            testCase.verifySubstring(message, 'manual is missing');
            testCase.verifyFalse(isfile(target));
        end

        function aCurrentRenderedManualIsUsedWithoutQuarto(testCase)
        %ACURRENTRENDEREDMANUALISUSEDWITHOUTQUARTO  A release ships the
        %   rendered manual, so preparing Help there needs no Quarto.
            folder = testCase.manualFolder(true);
            target = fullfile(testCase.tempFolder(), 'AlakazamHelp.html');

            [ok, message] = buildHelpPageInto(folder, target, @() testCase.fail());

            testCase.verifyTrue(ok, message);
            testCase.verifyTrue(isfile(target));
        end

        function thePageWorksInTheViewer(testCase)
        %THEPAGEWORKSINTHEVIEWER  Stylesheets and scripts come out inline,
        %   and outside links are handed to MATLAB.
            folder = testCase.manualFolder(true);
            target = fullfile(testCase.tempFolder(), 'AlakazamHelp.html');

            testCase.assertTrue(buildHelpPageInto(folder, target, @() ''));
            page = fileread(target);

            testCase.verifyFalse(contains(page, 'href="data:text/css'), ...
                'A data: stylesheet is refused by the viewer and must be inlined.');
            testCase.verifyTrue(contains(page, 'body { color: navy; }'));
            testCase.verifyTrue(contains(page, 'alzHelpBridge'));
            testCase.verifyTrue(contains(page, 'sendEventToMATLAB(''openUrl'''));
        end

        function noRenderedManualAndNoQuartoSaysWhatIsMissing(testCase)
            folder = testCase.manualFolder(false);
            target = fullfile(testCase.tempFolder(), 'AlakazamHelp.html');

            [ok, message] = buildHelpPageInto(folder, target, @() '');

            testCase.verifyFalse(ok);
            testCase.verifySubstring(message, 'Quarto');
            testCase.verifyFalse(isfile(target));
        end

        function anOlderRenderIsUsedWithANoteWhenQuartoIsAbsent(testCase)
            folder = testCase.manualFolder(true);
            testCase.touchNewer(fullfile(folder, 'manual.qmd'), fullfile(folder, 'manual.html'));
            target = fullfile(testCase.tempFolder(), 'AlakazamHelp.html');

            [ok, message] = buildHelpPageInto(folder, target, @() '');

            testCase.verifyTrue(ok);
            testCase.verifySubstring(message, 'older copy');
        end

        function aMissingRenderIsMadeWithQuarto(testCase)
            folder = testCase.manualFolder(false);
            target = fullfile(testCase.tempFolder(), 'AlakazamHelp.html');

            [ok, message] = buildHelpPageInto(folder, target, @() testCase.fakeQuarto(0));

            testCase.verifyTrue(ok, message);
            testCase.verifyTrue(contains(fileread(target), 'rendered by the stand-in'));
        end

        function aFailedRenderReportsWhatQuartoSaid(testCase)
            folder = testCase.manualFolder(false);
            target = fullfile(testCase.tempFolder(), 'AlakazamHelp.html');

            [ok, message] = buildHelpPageInto(folder, target, @() testCase.fakeQuarto(1));

            testCase.verifyFalse(ok);
            testCase.verifySubstring(message, 'could not be rendered');
            testCase.verifySubstring(message, 'stand-in failure');
        end
    end

    methods (Access = private)
        function folder = tempFolder(testCase)
            folder = tempname();
            mkdir(folder);
            testCase.addTeardown(@() rmdir(folder, 's'));
        end

        function folder = manualFolder(testCase, rendered)
        %MANUALFOLDER  A manual/ with a source and, when RENDERED, an HTML
        %   render carrying a data: stylesheet as Quarto writes one.
            folder = testCase.tempFolder();
            writeText(fullfile(folder, 'manual.qmd'), '# A manual');
            if rendered
                css = matlab.net.base64encode(uint8('body { color: navy; }'));
                html = ['<html><head><link rel="stylesheet" href="data:text/css;base64,' ...
                    css '"></head><body><p>The manual.</p></body></html>'];
                pause(1.1);   % a render is newer than its sources
                writeText(fullfile(folder, 'manual.html'), html);
            end
        end

        function touchNewer(~, file, than)
        %TOUCHNEWER  Rewrite FILE so it is newer than THAN.
            pause(1.1);
            writeText(file, [fileread(file) ' ']);
            assert(dir(file).datenum > dir(than).datenum);
        end

        function exe = fakeQuarto(testCase, exitCode)
        %FAKEQUARTO  A script standing in for quarto: with EXITCODE 0 it
        %   writes manual.html in the folder it is run from; otherwise it
        %   prints a failure and exits with that code.
            folder = testCase.tempFolder();
            if ispc
                exe = fullfile(folder, 'quarto.bat');
                if exitCode == 0
                    body = ['@echo off' newline ...
                        'echo ^<html^>^<body^>rendered by the stand-in^</body^>^</html^> > manual.html' newline];
                else
                    body = ['@echo off' newline 'echo stand-in failure' newline ...
                        sprintf('exit /b %d', exitCode) newline];
                end
            else
                exe = fullfile(folder, 'quarto.sh');
                if exitCode == 0
                    body = ['#!/bin/sh' newline ...
                        'echo "<html><body>rendered by the stand-in</body></html>" > manual.html' newline];
                else
                    body = ['#!/bin/sh' newline 'echo stand-in failure' newline ...
                        sprintf('exit %d', exitCode) newline];
                end
            end
            writeText(exe, body);
            if ~ispc
                system(sprintf('chmod +x "%s"', exe));
            end
        end
    end
end

% ======================================================================= %
function writeText(file, text)
    fid = fopen(file, 'w', 'n', 'UTF-8');
    fprintf(fid, '%s', text);
    fclose(fid);
end
