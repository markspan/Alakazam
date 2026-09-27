classdef ClusterStatsDialogSelectionTest < matlab.unittest.TestCase
%CLUSTERSTATSDIALOGSELECTIONTEST  Which subjects the cluster dialog starts
%   with selected.
%
%   A recording taken out of the study under Grouping ("In study" unticked)
%   is documented as absent from every statistic. The cluster dialog used to
%   start with every candidate selected, excluded ones included, so a test
%   run with the defaults quietly used them. Now it starts with only the
%   recordings in the study selected; an excluded one stays in the list,
%   marked by its label, to be added deliberately.
%
%   The dialog is modal, so a timer reads the selection once it is up and
%   presses Cancel. Tagged Slow, and skipped where a uifigure cannot be made.
%
%   Run with: runtests('tests/ClusterStatsDialogSelectionTest.m').
%
%   See also CLUSTERSTATSDIALOG, ALAKAZAM.FINDGRANDAVERAGECANDIDATES.

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            for p = {fullfile(root, 'src'), fullfile(root, 'src', 'Support'), ...
                     fullfile(root, 'src', 'Dialogs'), fullfile(root, 'src', 'Transformations')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
        end
    end

    methods (Test, TestTags = {'Slow'})
        function onlyRecordingsInTheStudyStartSelected(testCase)
            files = {'a.mat', 'b.mat', 'c.mat'};

            selected = testCase.selectionAtStart(files, [true false true]);

            testCase.verifyEqual(sort(selected), {'a.mat', 'c.mat'}, ...
                'The recording taken out of the study should not start selected.');
        end

        function withoutInclusionEverySubjectStartsSelected(testCase)
            files = {'a.mat', 'b.mat', 'c.mat'};

            selected = testCase.selectionAtStart(files, []);

            testCase.verifyEqual(sort(selected), files);
        end
    end

    methods (Access = private)
        function selected = selectionAtStart(testCase, files, included)
        %SELECTIONATSTART  Open the dialog on FILES, read the subject list's
        %   selection once it is up, and cancel.
            try
                probe = uifigure('Visible', 'off');
                delete(probe);
            catch ME
                testCase.assumeFail(['A uifigure could not be created here: ' ME.message]);
            end
            labels = strcat(files, ': Average (A, B)');
            selected = {};
            timerObj = timer('StartDelay', 6, 'TimerFcn', @(~, ~) drive());
            cleanup = onCleanup(@() cleanupTimer(timerObj));
            start(timerObj);
            if isempty(included)
                ClusterStatsDialog(files, labels, {'A', 'B'}, {'', '', ''});
            else
                ClusterStatsDialog(files, labels, {'A', 'B'}, {'', '', ''}, 'scalp', [], included);
            end
            clear cleanup;

            function drive()
                f = findall(groot, 'Type', 'figure', 'Name', 'Cluster Statistics');
                if isempty(f)
                    return;
                end
                lists = findall(f(1), 'Type', 'uilistbox');
                for k = 1:numel(lists)
                    if isequal(lists(k).ItemsData, files)
                        selected = lists(k).Value;
                    end
                end
                cancel = findall(f(1), 'Type', 'uibutton', 'Text', 'Cancel');
                cancel(1).ButtonPushedFcn(cancel(1), []);
            end
        end
    end
end

% ======================================================================= %
function cleanupTimer(t)
    try
        stop(t);
        delete(t);
    catch
        % Already gone.
    end
end
