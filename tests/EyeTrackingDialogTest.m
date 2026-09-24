classdef EyeTrackingDialogTest < matlab.unittest.TestCase
%EYETRACKINGDIALOGTEST  What the eye-tracking dialog previews and returns.
%
%   The dialog reads the .asc when it opens, so these cases open it on the
%   same two-clock session EyeTrackingTest joins, wait for the read to
%   finish, check what the preview says, change what a user would change,
%   and press OK. The preview matters as much as the options: it is where a
%   wrong keyword shows itself, as an eye track with no triggers, before any
%   join is attempted.
%
%   Needs EYE-EEG (the dialog parses with it); tagged Slow and External, and
%   skipped where a uifigure cannot be made.
%
%   Run with: runtests('tests/EyeTrackingDialogTest.m').
%
%   See also EYETRACKINGDIALOG, EYETRACKINGTEST.

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            for p = {fullfile(root, 'src'), fullfile(root, 'src', 'Support'), ...
                     fullfile(root, 'src', 'Dialogs'), fullfile(root, 'src', 'Transformations'), ...
                     fullfile(root, 'src', 'Transformations', 'EyeTracking'), ...
                     fullfile(root, 'tests')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
        end
    end

    methods (Test, TestTags = {'Slow', 'External'})
        function theStoredKeywordFindsTheTriggersAndTheAnchors(testCase)
            [options, preview] = testCase.runDialog(struct('keyword', 'MYKEYWORD'), @(f) []);

            testCase.assertNotEmpty(options, 'OK did not return options.');
            text = strjoin(preview, ' ');
            testCase.verifySubstring(text, 'Eye track: 32 trigger(s)');
            testCase.verifySubstring(text, 'Anchored on the first 100 and the last 200');
            testCase.verifyEqual(options.keyword, 'MYKEYWORD');
            testCase.verifyEqual(options.columns, 'all', ...
                'Every column ticked is kept as the word, so a replay gets every column.');
            testCase.verifyEmpty(options.startEvent, 'Blank means chosen per recording.');
        end

        function aWrongKeywordShowsAsNoTriggersBeforeAnyJoin(testCase)
            [~, preview] = testCase.runDialog(struct('keyword', 'WRONGWORD'), @(f) []);

            text = strjoin(preview, ' ');
            testCase.verifySubstring(text, 'Eye track: 0 trigger(s)');
            testCase.verifySubstring(text, 'keyword is probably not the one');
        end

        function someColumnsAreStoredByName(testCase)
            options = testCase.runDialog(struct('keyword', 'MYKEYWORD'), ...
                @(f) tickOnly(f, {'L_GAZE_X', 'L_GAZE_Y'}));

            testCase.assertNotEmpty(options);
            testCase.verifyEqual(options.columns, {'L_GAZE_X', 'L_GAZE_Y'});
        end

        function aTypedAnchorIsKept(testCase)
            options = testCase.runDialog(struct('keyword', 'MYKEYWORD'), ...
                @(f) setText(f, 'startEvent', '3'));

            testCase.assertNotEmpty(options);
            testCase.verifyEqual(options.startEvent, 3);
            testCase.verifyEmpty(options.endEvent);
        end
    end

    methods (Access = private)
        function [options, preview] = runDialog(testCase, stored, act)
            testCase.assumeTrue(EyeEeg.isAvailable(), 'EYE-EEG is not installed.');
            try
                probe = uifigure('Visible', 'off');
                delete(probe);
            catch ME
                testCase.assumeFail(['A uifigure could not be created here: ' ME.message]);
            end
            folder = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture()).Folder;
            EEG = EyeTrackingTest.session(folder);
            ascFile = fullfile(folder, [EyeTrackingTest.Base '.asc']);

            preview = {};
            % Polled rather than a fixed delay: the dialog reads the file as
            % it opens, and pressing OK before that finishes tests nothing.
            timerObj = timer('ExecutionMode', 'fixedSpacing', 'Period', 2, 'StartDelay', 3, ...
                'TimerFcn', @(t, ~) drive(t));
            cleanup = onCleanup(@() cleanupTimer(timerObj));
            start(timerObj);
            options = EyeTrackingDialog(EEG, ascFile, stored);
            clear cleanup;

            function drive(t)
                f = findall(groot, 'Type', 'figure', 'Name', 'Eye tracking');
                if isempty(f)
                    return;
                end
                box = findall(f(1), 'Tag', 'preview');
                if isempty(box) || startsWith(box(1).Value{1}, 'Reading')
                    return;   % still reading the file
                end
                stop(t);
                act(f(1));
                preview = box(1).Value;
                ok = findall(f(1), 'Type', 'uibutton', 'Text', 'OK');
                ok(1).ButtonPushedFcn(ok(1), []);
            end
        end
    end
end

% ======================================================================= %
function tickOnly(f, names)
    tree = findall(f, '-isa', 'matlab.ui.container.CheckBoxTree');
    nodes = tree(1).Children;
    keep = ismember(cellfun(@char, {nodes.NodeData}, 'UniformOutput', false), names);
    tree(1).CheckedNodes = nodes(keep);
end

function setText(f, tag, value)
    field = findall(f, 'Tag', tag);
    field(1).Value = value;
end

function cleanupTimer(t)
    try
        stop(t);
        delete(t);
    catch
        % Already gone.
    end
end
