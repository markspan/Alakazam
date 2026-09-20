classdef SpectralMeasureDialogTest < matlab.unittest.TestCase
%SPECTRALMEASUREDIALOGTEST  The coherence estimator the SpectralMeasure dialog offers
%   and returns.
%
%   A first run offers the frame-averaged estimator (the estimator of record). A
%   stored run keeps the estimator it was made with, and one saved before the method
%   existed has only the older crossf.enabled flag, meaning newcrossf when on and the
%   single window when off: recalculating such a node, through this dialog, must not
%   silently move it to a different estimator.
%
%   The dialog is modal, so a timer presses OK once it is up. Tagged Slow (each case
%   waits for the window to appear), and skipped where a uifigure cannot be made.
%
%   Run with: runtests('tests/SpectralMeasureDialogTest.m').
%
%   See also SPECTRALMEASUREDIALOG, SPECTRALMEASURE.

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            for p = {fullfile(root, 'src'), fullfile(root, 'src', 'Support'), fullfile(root, 'src', 'Dialogs'), ...
                     fullfile(root, 'src', 'Transformations', 'SpectralMeasure'), ...
                     fullfile(root, 'src', 'Transformations', 'Measure'), fullfile(root, 'src', 'Transformations')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
        end
    end

    methods (Test, TestTags = {'Slow'})
        function aFirstRunOffersTheFrameAveragedEstimator(testCase)
            crossf = testCase.runDialog([]);

            testCase.verifyEqual(crossf.Method, 'frames');
            testCase.verifyFalse(crossf.enabled);
        end

        function anOlderRunWithTheFlagOnKeepsNewcrossf(testCase)
            crossf = testCase.runDialog(testCase.stored(struct('enabled', true), ''));

            testCase.verifyEqual(crossf.Method, 'newcrossf');
            testCase.verifyTrue(crossf.enabled);
        end

        function anOlderRunWithTheFlagOffKeepsTheSingleWindow(testCase)
            crossf = testCase.runDialog(testCase.stored(struct('enabled', false), ''));

            testCase.verifyEqual(crossf.Method, 'window');
        end

        function anExplicitStoredMethodIsKept(testCase)
            crossf = testCase.runDialog(testCase.stored(struct('enabled', false), 'frames'));

            testCase.verifyEqual(crossf.Method, 'frames');
        end
    end

    methods (Access = private)
        function crossf = runDialog(testCase, stored)
            try
                probe = uifigure('Visible', 'off');
                delete(probe);
            catch ME
                testCase.assumeFail(['A uifigure could not be created here: ' ME.message]);
            end
            timerObj = timer('StartDelay', 4, 'TimerFcn', @(~, ~) pressOK());
            cleanup = onCleanup(@() cleanupTimer(timerObj));
            start(timerObj);
            [~, ~, ~, ~, ~, ~, ~, crossf] = SpectralMeasureDialog( ...
                struct('labels', {'Oz', 'Photodiode'}), stored);
            clear cleanup;
        end

        function s = stored(~, crossf, method)
            s = struct('rows', {{struct('label', 'a', 'freq', '60', 'channels', '')}}, 'crossf', crossf);
            if ~isempty(method)
                s.coherenceMethod = method;
            end
        end
    end
end

function pressOK()
    f = findall(groot, 'Type', 'figure', 'Name', 'SpectralMeasure');
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
