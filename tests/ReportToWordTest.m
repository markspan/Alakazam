classdef ReportToWordTest < matlab.unittest.TestCase
%REPORTTOWORDTEST  The Word copy of a rendered report.
%
%   THE POINT OF THE INTEGRATION CASE AT THE BOTTOM is the whole reason
%   this function converts the finished HTML rather than asking quarto to
%   render the .qmd again. Rendered to Word by quarto, these reports lose
%   their results tables: the cells arrive as one run of text, so a header
%   row reads "windowmeasurechannelbin...". Making the emission
%   format-aware, which is the documented cure, changed nothing on gt 1.3.0
%   with knitr 1.50. Reading the finished HTML, where the tables are
%   ordinary HTML tables, is what works. That property is worth a test,
%   because it is the only reason for the design.
%
%   The cases above it need no pandoc: they cover the paths, the reuse and
%   the three ways this can decline, all of which are message-not-throw.
%
%   Run with: runtests('tests/ReportToWordTest.m').

    properties (Constant)
        % A 1x1 PNG, so the integration case can check that an image
        % survives without carrying a fixture file around.
        TinyPng = ['iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAA' ...
            'DUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==']
    end

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            here = fileparts(mfilename('fullpath'));
            root = fileparts(here);
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'IO')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'Support')));
        end
    end

    methods (Test)
        function anExistingWordCopyIsReused(testCase)
        %ANEXISTINGWORDCOPYISREUSED  Also pins where the file goes: beside
        %   the report, same stem. The pandoc path given here does not
        %   exist, so if the answer comes back without an error, nothing
        %   was converted.
        %
        %   The report is backdated rather than simply written first. dir
        %   cannot separate two files written 50 ms apart (measured), so
        %   without this the two land on the same timestamp, which
        %   isUpToDate now reads as stale.
            folder = testCase.tempFolder();
            html = testCase.writeFile(folder, 'report.html', '<p>x</p>');
            docx = testCase.writeFile(folder, 'report.docx', 'pretend');
            testCase.backdate(html, hours(1));

            [made, errorMessage] = reportToWord(html, "PandocExe", 'no_such_pandoc.exe');

            testCase.verifyEqual(made, docx);
            testCase.verifyEmpty(errorMessage);
        end

        function aStaleWordCopyIsRebuilt(testCase)
        %ASTALEWORDCOPYISREBUILT  The other half. Here the rebuild is made
        %   to fail on purpose, since a real one needs pandoc: what is
        %   being checked is that it was attempted at all.
            folder = testCase.tempFolder();
            docx = testCase.writeFile(folder, 'report.docx', 'stale');
            html = testCase.writeFile(folder, 'report.html', '<p>newer</p>');
            testCase.backdate(docx, hours(1));

            [made, errorMessage] = reportToWord(html, "PandocExe", 'no_such_pandoc.exe');

            testCase.verifyEmpty(made);
            testCase.verifyNotEmpty(errorMessage);
        end

        function forceIgnoresAnUpToDateCopy(testCase)
            folder = testCase.tempFolder();
            html = testCase.writeFile(folder, 'report.html', '<p>x</p>');
            testCase.writeFile(folder, 'report.docx', 'pretend');
            testCase.backdate(html, hours(1));   % so the copy is genuinely current

            [made, errorMessage] = reportToWord(html, ...
                "PandocExe", 'no_such_pandoc.exe', "Force", true);

            testCase.verifyEmpty(made, 'Force should have converted rather than reused.');
            testCase.verifyNotEmpty(errorMessage);
        end

        function aMissingReportIsAMessageNotAnError(testCase)
        %AMISSINGREPORTISAMESSAGENOTANERROR  The caller shows the message in
        %   an alert; an exception would come up as a stack trace instead.
            folder = testCase.tempFolder();

            [made, errorMessage] = reportToWord(fullfile(folder, 'nothing.html'));

            testCase.verifyEmpty(made);
            testCase.verifySubstring(errorMessage, 'no report file');
        end

        function aMissingPandocIsAMessageNotAnError(testCase)
            folder = testCase.tempFolder();
            html = testCase.writeFile(folder, 'report.html', '<p>x</p>');

            [made, errorMessage] = reportToWord(html, "PandocExe", 'no_such_pandoc.exe');

            testCase.verifyEmpty(made);
            testCase.verifyNotEmpty(errorMessage);
        end

        function theViewOffersIt(testCase)
        %THEVIEWOFFERSIT  Weaker than driving the app, which needs a
        %   workspace and a rendered report, but it fails if either end is
        %   dropped.
            root = fileparts(fileparts(mfilename('fullpath')));
            source = fileread(fullfile(root, 'src', 'Views', 'ReportView.m'));

            testCase.verifySubstring(source, '"Open in Word"');
            testCase.verifySubstring(source, 'reportToWord(this.EEG.ReportHtmlFile)');
            testCase.verifySubstring(source, 'ancestor(this.Grid, "figure")', ...
                ['Dialogs must be owned by the ancestor figure: this.Figure is the ' ...
                 'uitab, and the view can be in a window of its own.']);
        end
    end

    methods (Test, TestTags = {'Slow', 'External'})
        function theTablesSurviveTheConversion(testCase)
        %THETABLESSURVIVETHECONVERSION  The property the whole design rests
        %   on: an HTML table has to come out as a real Word table, not as
        %   the text that was inside it.
            testCase.assumeNotEmpty(pandocExe(), ...
                'Pandoc is not installed, so the conversion cannot be exercised.');

            folder = testCase.tempFolder();
            html = testCase.writeFile(folder, 'report.html', testCase.sampleHtml());

            [docxFile, errorMessage] = reportToWord(html);
            testCase.assertNotEmpty(docxFile, ...
                sprintf('pandoc did not produce a Word file: %s', errorMessage));

            document = testCase.documentXmlOf(docxFile, folder);

            tables = regexp(document, '<w:tbl>.*?</w:tbl>', 'match');
            testCase.assertNotEmpty(tables, 'The Word file has no table in it at all.');

            inTable = strjoin(cellfun(@(c) c{1}, ...
                regexp(tables{1}, '<w:t[^>]*>(.*?)</w:t>', 'tokens'), ...
                'UniformOutput', false), ' ');

            testCase.verifySubstring(inTable, 'dependability', ...
                'The header row is not inside the table.');
            testCase.verifySubstring(inTable, '0.93', ...
                'The data row is not inside the table.');
        end

        function theFiguresSurviveTheConversion(testCase)
            testCase.assumeNotEmpty(pandocExe(), ...
                'Pandoc is not installed, so the conversion cannot be exercised.');

            folder = testCase.tempFolder();
            html = testCase.writeFile(folder, 'report.html', testCase.sampleHtml());

            docxFile = reportToWord(html);
            testCase.assertNotEmpty(docxFile);

            extracted = fullfile(folder, 'unzipped');
            unzip(docxFile, extracted);
            media = dir(fullfile(extracted, 'word', 'media', '*'));
            media = media(~[media.isdir]);

            testCase.verifyNotEmpty(media, ...
                'The image in the report did not make it into the Word file.');
        end
    end

    methods (Access = private)
        function folder = tempFolder(testCase)
            folder = testCase.applyFixture( ...
                matlab.unittest.fixtures.TemporaryFolderFixture()).Folder;
        end

        function backdate(testCase, file, howLong)
        %BACKDATE  Move a file's modified time back by HOWLONG.
        %   Timestamps are set rather than waited for: dir cannot separate
        %   two files written 50 ms apart on this platform, and a pause
        %   long enough to be sure would be a second of suite time per
        %   case, for a fact that can simply be stated.
            millis = java.lang.System.currentTimeMillis() - ...
                int64(milliseconds(howLong));
            changed = java.io.File(file).setLastModified(millis);

            testCase.assertTrue(logical(changed), ...
                sprintf('Could not set the modified time of %s.', file));
        end

        function path = writeFile(testCase, folder, name, contents)
            path = fullfile(folder, name);
            fid = fopen(path, 'w', 'n', 'UTF-8');
            testCase.assertGreaterThan(fid, 0);
            closer = onCleanup(@() fclose(fid)); %#ok<NASGU>
            fprintf(fid, '%s', contents);
        end

        function html = sampleHtml(testCase)
        %SAMPLEHTML  A table and an image, in the shape a report has them:
        %   an ordinary HTML table, and a figure as a data: URI.
            html = [ ...
                '<!DOCTYPE html><html><head><title>t</title></head><body>' ...
                '<h1>Report</h1>' ...
                '<table><thead><tr><th>window</th><th>dependability</th></tr></thead>' ...
                '<tbody><tr><td>N400</td><td>0.93</td></tr></tbody></table>' ...
                '<p><img src="data:image/png;base64,' ReportToWordTest.TinyPng '"></p>' ...
                '</body></html>'];
        end

        function document = documentXmlOf(testCase, docxFile, folder)
            extracted = fullfile(folder, 'unzipped_doc');
            unzip(docxFile, extracted);
            xml = fullfile(extracted, 'word', 'document.xml');
            testCase.assertEqual(exist(xml, 'file'), 2, ...
                'The .docx has no word/document.xml, so it is not a Word file.');
            document = fileread(xml);
        end
    end
end
