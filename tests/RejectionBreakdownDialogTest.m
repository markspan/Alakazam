classdef RejectionBreakdownDialogTest < matlab.unittest.TestCase
%REJECTIONBREAKDOWNDIALOGTEST  The table a node's "Rejection breakdown..."
%   opens: one row per detector, the total, and the summary above them.
%
%   It used to be a uialert of sprintf-padded columns, which a proportional
%   font misaligns and which the manual's screenshot tool could not capture.
%   These cases pin that the counts in the table are the ones ArtefactDetect
%   recorded (the report is built by running it, not by hand), that the
%   total is its own labelled row, and that the tree's action opens this
%   dialog rather than an alert.
%
%   Makes uifigures, so it is tagged Slow and skipped where one cannot be
%   made.
%
%   Run with: runtests('tests/RejectionBreakdownDialogTest.m').
%
%   See also REJECTIONBREAKDOWNDIALOG, ARTEFACTDETECTBREAKDOWNTEST.

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            for p = {fullfile(root, 'src', 'Dialogs'), fullfile(root, 'src', 'Support'), ...
                     fullfile(root, 'src', 'Transformations'), ...
                     fullfile(root, 'src', 'Transformations', 'ArtefactDetect'), ...
                     fullfile(root, 'tests', 'fixtures')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
        end
    end

    methods (Test, TestTags = {'Slow'})
        function oneRowPerDetectorThenTheTotal(testCase)
            report = twoDetectorReport();

            rows = testCase.tableRows(report);

            testCase.verifyEqual(rows(:, 1)', {'Absolute threshold', 'Sample-to-sample', 'Any detector'});
            testCase.verifyEqual(rows{1, 2}, report.epochs(1));
            testCase.verifyEqual(rows{2, 2}, report.epochs(2));
            testCase.verifyEqual(rows{1, 3}, report.onlyThis(1));
            testCase.verifyEqual(rows{2, 3}, report.onlyThis(2));
            testCase.verifyEqual(rows{2, 4}, report.channelEpochs(2));
            testCase.verifyEqual(rows{3, 2}, report.totalEpochs, ...
                'The total is the epochs any detector rejected, not the sum of the column.');
        end

        function theCountsOverlapAsRecorded(testCase)
        %THECOUNTSOVERLAPASRECORDED  The planted spike trips both detectors
        %   and the planted jump only one, so the column sums to more than
        %   the total. The table must show that, not tidy it away.
            report = twoDetectorReport();

            rows = testCase.tableRows(report);

            testCase.verifyEqual([rows{1:2, 2}], [1 2]);
            testCase.verifyEqual([rows{1:2, 3}], [0 1]);
            testCase.verifyEqual(rows{3, 2}, 2);
        end

        function theSummaryNamesTheNodeAndTheTotal(testCase)
            report = twoDetectorReport();

            fig = testCase.openDialog(report, 'ArtefactDetect (1)');
            texts = {findall(fig, 'Type', 'uilabel').Text};

            testCase.verifyTrue(any(contains(texts, '"ArtefactDetect (1)": 2 of 4 epoch(s) rejected')), ...
                strjoin(texts, ' | '));
        end

        function noDetectorsTickedSaysSo(testCase)
            EEG = makeTestEEG('nbchan', 2, 'trials', 3);
            out = ArtefactDetect(EEG, detectorOpts({}));

            fig = testCase.openDialog(out.etc.alz.artefactDetectors, 'Untested');
            rows = findall(fig, 'Tag', 'breakdownTable').Data;
            texts = {findall(fig, 'Type', 'uilabel').Text};

            testCase.verifyEqual(rows(:, 1)', {'Any detector'});
            testCase.verifyEqual(rows{1, 2}, 0);
            testCase.verifyTrue(any(contains(texts, 'nothing was tested')), strjoin(texts, ' | '));
        end

        function theTreeActionOpensTheDialog(testCase)
        %THETREEACTIONOPENSTHEDIALOG  The context-menu action must hand the
        %   report to the dialog. Read from the source: running it needs the
        %   whole application and a node on disk.
            root = fileparts(fileparts(mfilename('fullpath')));
            source = fileread(fullfile(root, 'src', '@Alakazam', 'onRejectionBreakdown.m'));

            testCase.verifyTrue(contains(source, 'RejectionBreakdownDialog('), ...
                'onRejectionBreakdown should open RejectionBreakdownDialog.');
            testCase.verifyFalse(contains(source, 'breakdownText'), ...
                'The padded-text alert should be gone.');
        end
    end

    methods (Access = private)
        function fig = openDialog(testCase, report, name)
            try
                probe = uifigure('Visible', 'off');
                delete(probe);
            catch ME
                testCase.assumeFail(['A uifigure could not be created here: ' ME.message]);
            end
            fig = RejectionBreakdownDialog(report, name);
            testCase.addTeardown(@() delete(fig(isvalid(fig))));
        end

        function rows = tableRows(testCase, report)
            fig = testCase.openDialog(report, 'ArtefactDetect');
            t = findall(fig, 'Tag', 'breakdownTable');
            testCase.assertNumElements(t, 1, 'The dialog should hold one breakdown table.');
            rows = t.Data;
        end
    end
end

% ======================================================================= %
function report = twoDetectorReport()
%TWODETECTORREPORT  A report ArtefactDetect itself wrote: a 500 uV spike in
%   trial 2 trips both detectors; a 160 uV jump inside the absolute limits
%   in trial 3 trips only sample-to-sample.
    EEG = makeTestEEG('nbchan', 2, 'trials', 4);
    EEG.data(1, 5, 2) = 500;
    EEG.data(2, 9, 3) = 80;
    EEG.data(2, 10, 3) = -80;
    out = ArtefactDetect(EEG, detectorOpts({'Absolute threshold', 'Sample-to-sample'}));
    report = out.etc.alz.artefactDetectors;
end

function o = detectorOpts(methods)
    o = struct('Method', {methods}, 'Minimum', -100, 'Maximum', 100, ...
        'Threshold', 100, 'Window', 200, 'Step', 50, ...
        'TestStart', 0, 'TestStop', 0, ...
        'Channels', 'All channels', 'Scope', 'Whole epoch');
end
