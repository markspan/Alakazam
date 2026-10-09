classdef DeconvolveDialogTest < matlab.unittest.TestCase
%DECONVOLVEDIALOGTEST  What the Deconvolve dialog returns: the formulas, the
%   event codes in no bin, and the result chosen.
%
%   THE FORMULAS are a table, one row per bin, and OK returns what the table
%   shows: 'y ~ 1' for every bin by default, a formula typed for a bin
%   (tidied the way the fit reads it), a stored formula shown again, and the
%   covariates of options stored before formulas existed shown as the
%   formulas they meant. A formula the fit would refuse is refused at OK.
%
%   THE EVENT CODES were a multi-select list box, which deselects only with
%   Ctrl+click, so "none" was out of reach (the reported symptom was a
%   covariate that could not be unselected). They are a checkbox tree now,
%   where a plain click toggles, and these cases pin that the control IS one
%   (so a list box cannot quietly come back) and that OK returns exactly
%   what is ticked, "nothing" included.
%
%   A programmatic change to a control does not run its callback, so these
%   also pin that OK reads the controls themselves rather than a copy the
%   callbacks keep; a copy would be stale here and could be stale for a user.
%
%   EVENTS LOCKED TOGETHER. A code in no bin kept at a near-constant lag to a
%   bin is warned about in the model and in an alert (manual issue M10). The
%   recording here gives its responses a reaction-time spread, so the other
%   cases are not interrupted by that alert; the two cases about the warning
%   use a recording whose responses come exactly 600 ms after every Frequent
%   event instead.
%
%   The dialog is modal, so a timer changes the controls and presses OK once
%   it is up, and Cancel if OK refused. Tagged Slow, and skipped where a
%   uifigure cannot be made.
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
        function theEventCodesAreATickList(testCase)
            [~, kinds] = testCase.runDialog(@(f) []);

            testCase.verifyEqual(kinds, {'uicheckboxtree'}, ...
                ['A multi-select list box cannot be emptied with a plain click, which is ' ...
                 'how a choice became impossible to undo.']);
        end

        % ---- the formulas ----------------------------------------------- %
        function everyBinIsItsOwnWaveformByDefault(testCase)
            options = testCase.runDialog(@(f) []);

            testCase.assertNotEmpty(options, 'OK did not return options.');
            testCase.verifyEqual({options.formulas.bin}, {'Frequent', 'Rare'});
            testCase.verifyEqual({options.formulas.formula}, {'y ~ 1', 'y ~ 1'});
            testCase.verifyFalse(isfield(options, 'covariates'), ...
                'The formulas say it all; a second way to add terms is only read, not written.');
        end

        function aFormulaTypedForABinIsReturned(testCase)
            options = testCase.runDialog(@(f) setFormula(f, 'Rare', '1 + rt'));

            testCase.assertNotEmpty(options);
            testCase.verifyEqual({options.formulas.formula}, {'y ~ 1', 'y ~ 1 + rt'}, ...
                'Written without "y ~", it is stored as the fit reads it.');
        end

        function aStoredFormulaIsShownAgain(testCase)
            stored = struct('formulas', struct('bin', {'Rare'}, 'formula', {'y ~ 1 + rt'}));
            options = testCase.runDialog(@(f) [], stored);

            testCase.assertNotEmpty(options);
            testCase.verifyEqual({options.formulas.formula}, {'y ~ 1', 'y ~ 1 + rt'});
        end

        function olderCovariatesAreShownAsTheFormulasTheyMeant(testCase)
        %OLDERCOVARIATESARESHOWNASTHEFORMULASTHEYMEANT  Options stored before
        %   formulas existed list covariates; each bin whose events carry one
        %   shows it as a term, and OK stores that as its formula.
            options = testCase.runDialog(@(f) [], struct('covariates', {{'rt'}}));

            testCase.assertNotEmpty(options);
            testCase.verifyEqual({options.formulas.formula}, {'y ~ 1 + rt', 'y ~ 1 + rt'});
        end

        function aFormulaNamingNoFieldIsRefusedAtOK(testCase)
            options = testCase.runDialog(@(f) setFormula(f, 'Rare', 'y ~ 1 + reaction'));

            testCase.verifyEmpty(options, ...
                'OK refused (the events have no "reaction"), so the dialog was cancelled.');
        end

        % ---- the event codes in no bin ------------------------------------ %
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

        function aCodeLockedToABinIsWarnedAbout(testCase)
        %ACODELOCKEDTOABINISWARNEDABOUT  The fixture's 'response' comes
        %   exactly 600 ms after every Frequent event, which leaves the fit
        %   next to nothing to tell the two apart by (manual issue M10). The
        %   model says so, and names the remedy.
            shown = {};
            testCase.runDialog(@(f) record(f), [], DeconvolveDialogTest.recording('locked'));

            testCase.verifyTrue(any(contains(shown, 'Warning: "response", in no bin, follows "Frequent"')), ...
                'The model should warn that "response" is locked to "Frequent".');

            function record(f)
                shown = modelText(f);
            end
        end

        function untickingTheLockedCodeClearsTheWarning(testCase)
            shown = {};
            testCase.runDialog(@(f) untickAndRecord(f), [], DeconvolveDialogTest.recording('locked'));

            testCase.verifyFalse(any(contains(shown, 'Warning:')), ...
                'With "response" no longer modelled there is no pair left to warn about.');

            function untickAndRecord(f)
                tree = codeTree(f);
                tick(tree, 'probe');
                tree.CheckedNodesChangedFcn(tree, []);   % as a click would
                shown = modelText(f);
            end
        end

        % ---- the result: waveforms, trials or terms ---------------------- %
        function theResultIsOneWaveformPerBinByDefault(testCase)
            options = testCase.runDialog(@(f) []);

            testCase.assertNotEmpty(options);
            testCase.verifyEqual(options.output, 'average');
        end

        function overlapCorrectedTrialsCanBeChosen(testCase)
            options = testCase.runDialog(@(f) choose(f, 'output', 'trials'));

            testCase.assertNotEmpty(options);
            testCase.verifyEqual(options.output, 'trials');
        end

        function aStoredChoiceOfTrialsIsShownAgain(testCase)
            options = testCase.runDialog(@(f) [], struct('output', 'trials'));

            testCase.assertNotEmpty(options);
            testCase.verifyEqual(options.output, 'trials', ...
                'OK on an unchanged dialog keeps the stored choice.');
        end

        function theSolverIterationsAreASetting(testCase)
            untouched = testCase.runDialog(@(f) []);
            raised = testCase.runDialog(@(f) setNumber(f, 'solverIterations', 1500));
            replayed = testCase.runDialog(@(f) [], struct('solverIterations', 900));

            testCase.assertNotEmpty(untouched);
            testCase.verifyEqual(untouched.solverIterations, 400, 'The toolbox''s own default.');
            testCase.verifyEqual(raised.solverIterations, 1500);
            testCase.verifyEqual(replayed.solverIterations, 900);
        end

        function theValuesToEvaluateAtOpenOnlyForTheTerms(testCase)
            enabled = {};
            testCase.runDialog(@(f) record(f));

            testCase.verifyEqual(enabled, {'off', 'on'});

            function record(f)
                field = findall(f, 'Type', 'uieditfield', 'Tag', 'evaluateAt');
                enabled{end + 1} = char(field.Enable);
                choose(f, 'output', 'terms');
                enabled{end + 1} = char(field.Enable);
            end
        end

        function theTermsAreReturnedWithTheirValues(testCase)
            options = testCase.runDialog(@(f) termsAt(f, 'rt = 300 500'));

            testCase.assertNotEmpty(options);
            testCase.verifyEqual(options.output, 'terms');
            testCase.verifyEqual(options.evaluateAt, 'rt = 300 500');
        end

        % ---- the toolbox's defaults, each a choice ----------------------- %
        function theToolboxsDefaultsComeFirst(testCase)
        %THETOOLBOXSDEFAULTSCOMEFIRST  On first use: the scan on every
        %   channel, the terms with the other terms at their mean value, and
        %   the betas as fitted, as Unfold does each.
            options = testCase.runDialog(@(f) []);

            testCase.assertNotEmpty(options);
            testCase.verifyEqual(options.artifactChannels, 'all');
            testCase.verifyEqual(options.marginal, 'MEM');
            testCase.verifyEmpty(options.baselineMs, 'No baseline until it is ticked.');
            testCase.verifyEqual(options.missingValues, 'median', 'uf_imputeMissing''s own default.');
        end

        function theScanTheMarginalAndTheBaselineAreChoices(testCase)
            options = testCase.runDialog(@(f) chooseAll(f));

            testCase.assertNotEmpty(options);
            testCase.verifyEqual(options.artifactChannels, 'scalp');
            testCase.verifyEqual(options.marginal, 'AME');
            testCase.verifyEqual(options.baselineMs, [-200 0], 'The pre-event window it offers.');

            function chooseAll(f)
                choose(f, 'artifactChannels', 'scalp');
                choose(f, 'output', 'terms');
                choose(f, 'marginal', 'AME');
                box = findall(f, 'Type', 'uicheckbox', 'Text', 'Baseline-correct the result');
                box(1).Value = true;
                box(1).ValueChangedFcn(box(1), []);
            end
        end

        function storedChoicesAreShownAgain(testCase)
            stored = struct('artifactChannels', 'scalp', 'marginal', 'AME', 'baselineMs', [-100 0], ...
                'missingValues', 'drop');
            options = testCase.runDialog(@(f) [], stored);

            testCase.assertNotEmpty(options);
            testCase.verifyEqual(options.artifactChannels, 'scalp');
            testCase.verifyEqual(options.marginal, 'AME');
            testCase.verifyEqual(options.baselineMs, [-100 0]);
            testCase.verifyEqual(options.missingValues, 'drop');
        end

        function olderStoredOptionsAreShownAsTheyRun(testCase)
        %OLDERSTOREDOPTIONSARESHOWNASTHEYRUN  A set stored before these were
        %   choices replays with the scalp-only scan, 'AME' and the pre-event
        %   baseline (Deconvolve), so the dialog shows those, and OK keeps them.
            options = testCase.runDialog(@(f) [], struct('output', 'average'));

            testCase.assertNotEmpty(options);
            testCase.verifyEqual(options.artifactChannels, 'scalp');
            testCase.verifyEqual(options.marginal, 'AME');
            testCase.verifyEqual(options.baselineMs, [-200 0]);
            testCase.verifyEqual(options.missingValues, 'refuse');
        end

        function aMissingNumberIsFilledInOrRefusedAsChosen(testCase)
        %AMISSINGNUMBERISFILLEDINORREFUSEDASCHOSEN  One Rare event has no
        %   rt. With the median (the default) OK accepts a formula using rt;
        %   with Refused it refuses, as the fit would.
            EEG = DeconvolveDialogTest.recording('gap');

            filled = testCase.runDialog(@(f) setFormula(f, 'Rare', 'y ~ 1 + rt'), [], EEG);
            refused = testCase.runDialog(@(f) refuseWithRt(f), [], EEG);

            testCase.verifyNotEmpty(filled);
            testCase.verifyEqual(filled.missingValues, 'median');
            testCase.verifyEmpty(refused, 'OK refuses what the fit would refuse.');

            function refuseWithRt(f)
                setFormula(f, 'Rare', 'y ~ 1 + rt');
                choose(f, 'missingValues', 'refuse');
            end
        end

        function theMarginalOpensOnlyForTheTerms(testCase)
            enabled = {};
            testCase.runDialog(@(f) record(f));

            testCase.verifyEqual(enabled, {'off', 'on'});

            function record(f)
                dropdown = findall(f, 'Type', 'uidropdown', 'Tag', 'marginal');
                enabled{end + 1} = char(dropdown.Enable);
                choose(f, 'output', 'terms');
                enabled{end + 1} = char(dropdown.Enable);
            end
        end

        function valuesForATermNoFormulaHasAreRefusedAtOK(testCase)
            options = testCase.runDialog(@(f) termsAt(f, 'constantField = 7'));

            testCase.verifyEmpty(options, ...
                'No formula has constantField, so there is nothing to evaluate at 7.');
        end
    end

    methods (Access = private)
        function [options, kinds] = runDialog(testCase, act, stored, EEG)
        %RUNDIALOG  Open the dialog on EEG (default: a recording with a
        %   numeric event field and two unbinned codes, see recording),
        %   seeded from STORED (default none), let ACT(fig) change the
        %   controls, press OK (and Cancel if OK refused).
            if nargin < 3
                stored = [];
            end
            if nargin < 4
                EEG = DeconvolveDialogTest.recording();
            end
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
            options = DeconvolveDialog(EEG, stored);
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
                % OK refused (an alert, the dialog still up): Cancel, so the
                % test ends with no options rather than waiting forever.
                if isvalid(f(1))
                    cancel = findall(f, 'Type', 'uibutton', 'Text', 'Cancel');
                    cancel(1).ButtonPushedFcn(cancel(1), []);
                end
            end
        end
    end

    methods (Static)
        function EEG = recording(variant)
        %RECORDING  Two bins, a numeric field (rt) on every event, and two
        %   codes in no bin: 'response' (90 events) and 'probe' (3).
        %   The responses come 400 to 800 ms after their Frequent event, as
        %   reaction times vary. RECORDING('locked') leaves them exactly
        %   600 ms after it, as UnfoldBinsTest builds them, which the dialog
        %   warns about.
            EEG = UnfoldCovariatesTest.recording();
            if nargin > 0 && strcmp(variant, 'gap')
                % RECORDING('gap'): one Rare event without its rt.
                rare = find(arrayfun(@(e) isequal(e.bini, 2), EEG.event), 1);
                EEG.event(rare).rt = NaN;
            end
            if nargin < 1 || ~strcmp(variant, 'locked')
                % Its own stream, so the jitter is the same on every run and
                % the global generator other tests seed is left alone.
                stream = RandStream('mt19937ar', 'Seed', 9);
                for k = find(strcmp({EEG.event.type}, 'response'))
                    EEG.event(k).latency = EEG.event(k).latency + randi(stream, [-20 20]);
                end
            end
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

function text = modelText(f)
%MODELTEXT  Every line of the dialog's read-only text areas: the model and
%   the reference of fields a formula can use.
    areas = findall(f, 'Type', 'uitextarea');
    text = {};
    for k = 1:numel(areas)
        text = [text; cellstr(areas(k).Value(:))]; %#ok<AGROW>
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

function choose(f, tag, value)
%CHOOSE  Set the dropdown tagged TAG to the item whose data is VALUE, and
%   run its callback as a user's choice would.
    dropdown = findall(f, 'Type', 'uidropdown', 'Tag', tag);
    dropdown(1).Value = value;
    if ~isempty(dropdown(1).ValueChangedFcn)
        dropdown(1).ValueChangedFcn(dropdown(1), []);
    end
end

function setNumber(f, tag, value)
%SETNUMBER  Type VALUE into the numeric field tagged TAG.
    field = findall(f, 'Type', 'uinumericeditfield', 'Tag', tag);
    if isempty(field)
        field = findall(f, 'Tag', tag);
    end
    field(1).Value = value;
end

function setFormula(f, bin, formula)
%SETFORMULA  Type FORMULA into BIN's row of the formula table.
    table = findall(f, 'Type', 'uitable', 'Tag', 'formulas');
    row = strcmp(table(1).Data(:, 1), bin);
    table(1).Data{row, 2} = formula;
end

function termsAt(f, values)
%TERMSAT  Rare fitted with rt, the result the terms, evaluated at VALUES.
    setFormula(f, 'Rare', 'y ~ 1 + rt');
    choose(f, 'output', 'terms');
    field = findall(f, 'Type', 'uieditfield', 'Tag', 'evaluateAt');
    field(1).Value = values;
end

function cleanupTimer(t)
    try
        stop(t);
        delete(t);
    catch
        % Already gone.
    end
end
