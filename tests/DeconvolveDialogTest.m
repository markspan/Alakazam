classdef DeconvolveDialogTest < matlab.unittest.TestCase
%DECONVOLVEDIALOGTEST  What the Deconvolve dialog's two tick lists return.
%
%   THE REPORTED BUG: a covariate, once selected, could not be unselected.
%   Both lists were multi-select list boxes, which deselect only with
%   Ctrl+click; a plain click on the one selected item leaves it selected,
%   so "no covariate" was out of reach. They are checkbox trees now, where a
%   plain click toggles, and these cases pin both halves of the fix: that
%   the controls ARE checkbox trees (so a list box cannot quietly come back),
%   and that OK returns exactly what is ticked on screen, "nothing" included,
%   after something had been ticked.
%
%   A programmatic change to the ticks does not run the tree's callback, so
%   these also pin that OK reads the trees themselves rather than a copy the
%   callbacks keep; a copy would be stale here and could be stale for a user.
%
%   The dialog is modal, so a timer does the ticking and presses OK once it
%   is up. Tagged Slow, and skipped where a uifigure cannot be made.
%
%   Run with: runtests('tests/DeconvolveDialogTest.m').
%
%   See also DECONVOLVEDIALOG, DECONVOLVE, RESSDIALOGTEST.

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            for p = {fullfile(root, 'src'), fullfile(root, 'src', 'Support'), ...
                     fullfile(root, 'src', 'Dialogs'), fullfile(root, 'src', 'Transformations'), ...
                     fullfile(root, 'src', 'Transformations', 'Deconvolve'), ...
                     fullfile(root, 'src', 'Transformations', 'DefineBins'), ...
                     fullfile(root, 'tests')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
        end
    end

    methods (Test, TestTags = {'Slow'})
        function bothListsAreTickBoxes(testCase)
            [~, kinds] = testCase.runDialog(@(f) []);

            testCase.verifyEqual(kinds, {'uicheckboxtree', 'uicheckboxtree'}, ...
                ['A multi-select list box cannot be emptied with a plain click, which is ' ...
                 'how a covariate became impossible to unselect.']);
        end

        function aCovariateTickedAndUntickedIsNotReturned(testCase)
        %ACOVARIATETICKEDANDUNTICKEDISNOTRETURNED  The reported case, exactly:
        %   select a covariate, change one's mind, press OK.
            options = testCase.runDialog(@(f) untickAfterTicking(covariateTree(f)));

            testCase.assertNotEmpty(options, 'OK did not return options.');
            testCase.verifyEmpty(options.covariates);
        end

        function aTickedCovariateIsReturned(testCase)
            options = testCase.runDialog(@(f) tick(covariateTree(f), 'rt'));

            testCase.assertNotEmpty(options);
            testCase.verifyEqual(options.covariates, {'rt'});
        end

        function everyCodeTickedIsStoredAsAll(testCase)
        %EVERYCODETICKEDISSTOREDASALL  Not as today's list, so a replay on a
        %   recording with a code this one lacks still models that code.
            options = testCase.runDialog(@(f) []);

            testCase.assertNotEmpty(options);
            testCase.verifyEqual(options.otherEvents, 'all');
        end

        function someCodesTickedAreStoredAsThoseCodes(testCase)
            options = testCase.runDialog(@(f) tick(codeTree(f), 'response'));

            testCase.assertNotEmpty(options);
            testCase.verifyEqual(options.otherEvents, {'response'});
        end

        function noCodeTickedIsStoredAsNone(testCase)
            options = testCase.runDialog(@(f) untickAll(codeTree(f)));

            testCase.assertNotEmpty(options);
            testCase.verifyEmpty(options.otherEvents);
            testCase.verifyTrue(iscell(options.otherEvents), ...
                'None is an empty list, which Deconvolve reads as none, not as the default.');
        end
    end

    methods (Access = private)
        function [options, kinds] = runDialog(testCase, act)
        %RUNDIALOG  Open the dialog on a recording with a covariate and two
        %   unbinned codes, let ACT(fig) change the ticks, press OK.
            try
                probe = uifigure('Visible', 'off');
                delete(probe);
            catch ME
                testCase.assumeFail(['A uifigure could not be created here: ' ME.message]);
            end
            kinds = {};
            timerObj = timer('StartDelay', 6, 'TimerFcn', @(~, ~) drive());
            cleanup = onCleanup(@() cleanupTimer(timerObj));
            start(timerObj);
            options = DeconvolveDialog(DeconvolveDialogTest.recording(), []);
            clear cleanup;

            function drive()
                f = findall(groot, 'Type', 'figure', 'Name', 'Deconvolve');
                if isempty(f)
                    return;
                end
                trees = findall(f, '-isa', 'matlab.ui.container.CheckBoxTree');
                kinds = arrayfun(@(t) char(t.Type), trees, 'UniformOutput', false)';
                act(f(1));
                ok = findall(f, 'Type', 'uibutton', 'Text', 'OK');
                if ~isempty(ok)
                    ok(1).ButtonPushedFcn(ok(1), []);
                end
            end
        end
    end

    methods (Static)
        function EEG = recording()
        %RECORDING  Two bins, a numeric covariate on every event, and two
        %   codes in no bin: 'response' (90 events) and 'probe' (3).
            EEG = UnfoldCovariatesTest.recording();
            template = EEG.event(find(strcmp({EEG.event.type}, 'response'), 1));
            for latency = [5003 11007 17011]
                extra = template;
                extra.type = 'probe';
                extra.latency = latency;
                EEG.event(end + 1) = extra;
            end
            [~, order] = sort([EEG.event.latency]);
            EEG.event = EEG.event(order);
        end
    end
end

% ======================================================================= %
function tree = covariateTree(f)
    tree = treeHolding(f, 'rt');
end

function tree = codeTree(f)
    tree = treeHolding(f, 'response');
end

function tree = treeHolding(f, nodeData)
%TREEHOLDING  Which of the two tick lists offers NODEDATA.
    trees = findall(f, '-isa', 'matlab.ui.container.CheckBoxTree');
    tree = [];
    for k = 1:numel(trees)
        if any(strcmp(cellfun(@char, {trees(k).Children.NodeData}, 'UniformOutput', false), nodeData))
            tree = trees(k);
            return;
        end
    end
end

function tick(tree, nodeData)
%TICK  Leave exactly NODEDATA ticked.
    nodes = tree.Children;
    tree.CheckedNodes = nodes(strcmp(cellfun(@char, {nodes.NodeData}, 'UniformOutput', false), nodeData));
end

function untickAll(tree)
    tree.CheckedNodes = [];
end

function untickAfterTicking(tree)
    tick(tree, 'rt');
    untickAll(tree);
end

function cleanupTimer(t)
    try
        stop(t);
        delete(t);
    catch
        % Already gone.
    end
end
