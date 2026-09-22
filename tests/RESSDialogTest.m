classdef RESSDialogTest < matlab.unittest.TestCase
%RESSDIALOGTEST  What the RESS dialog proposes, keeps and returns.
%
%   A first run proposes one row per frequency the bin labels name, pooling
%   the bins that share one: the RIFT design's "RIFT 60Hz" and "RIFT 60Hz
%   peripheral" build a single 60 Hz filter. A stored run is kept as it was.
%   Either way OK returns options RESS can apply.
%
%   The dialog is modal, so a timer presses OK once it is up. Tagged Slow,
%   and skipped where a uifigure cannot be made.
%
%   Run with: runtests('tests/RESSDialogTest.m').
%
%   See also RESSDIALOG, RESS, RESSTEST.

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            for p = {fullfile(root, 'src'), fullfile(root, 'src', 'Support'), fullfile(root, 'src', 'Dialogs'), ...
                     fullfile(root, 'src', 'Transformations'), fullfile(root, 'src', 'Transformations', 'RESS'), ...
                     fullfile(root, 'tests')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
        end
    end

    methods (Test, TestTags = {'Slow'})
        function aFirstRunPoolsTheBinsThatShareAFrequency(testCase)
            options = testCase.runDialog(RESSTest.recording(), []);

            testCase.assertNotEmpty(options, 'OK did not return options.');
            rows = options.rows;
            testCase.verifyEqual(cellfun(@(r) r.label, rows, 'UniformOutput', false), ...
                {'RESS60Hz', 'RESS64Hz', 'RESS30Hz'});
            testCase.verifyEqual(rows{1}.bins, 'RIFT 60Hz, RIFT 60Hz peripheral');
            testCase.verifyEqual(cellfun(@(r) r.freq, rows), [60 64 30]);
            testCase.verifyFalse(options.includeMastoids);
            testCase.verifyEqual(options.shrinkage, 0.01, 'AbsTol', 1e-12);
            testCase.verifyEmpty(options.timeStart);
        end

        function aStoredRunIsKept(testCase)
            stored = RESSTest.options();
            stored.includeMastoids = true;
            stored.timeStart = 100;
            stored.timeStop = 2500;

            options = testCase.runDialog(RESSTest.recording(), stored);

            testCase.assertNotEmpty(options);
            testCase.verifyEqual(numel(options.rows), 2);
            testCase.verifyEqual(options.rows{2}.bins, 'RIFT 64Hz');
            testCase.verifyTrue(options.includeMastoids);
            testCase.verifyEqual([options.timeStart options.timeStop], [100 2500]);
            out = RESS(RESSTest.recording(), options);
            testCase.verifyEqual(out.etc.alz.ress(2).label, 'RESS64Hz', 'What OK returns, RESS applies.');
        end
    end

    methods (Access = private)
        function options = runDialog(testCase, EEG, stored)
            try
                probe = uifigure('Visible', 'off');
                delete(probe);
            catch ME
                testCase.assumeFail(['A uifigure could not be created here: ' ME.message]);
            end
            timerObj = timer('StartDelay', 6, 'TimerFcn', @(~, ~) pressOK());
            cleanup = onCleanup(@() cleanupTimer(timerObj));
            start(timerObj);
            options = RESSDialog(EEG, stored);
            clear cleanup;
        end
    end
end

function pressOK()
    f = findall(groot, 'Type', 'figure', 'Name', 'RESS');
    ok = findall(f, 'Type', 'uibutton', 'Text', 'OK');
    if ~isempty(ok)
        ok(1).ButtonPushedFcn(ok(1), []);
    end
end

function cleanupTimer(t)
    try
        stop(t);
        delete(t);
    catch
        % Already gone.
    end
end
