classdef DialogFieldsTest < matlab.unittest.TestCase
%DIALOGFIELDSTEST  The generated dialog's fields (+DialogFields) and the
%   dialog built from them (TransformOptionsDialog).
%
%   Three layers. What a plain default becomes, which must not change: every
%   dialog written before fields were objects depends on it. What each field
%   hands back, built into a hidden figure and edited the way a user would
%   (setting a control's value, pressing its button). And the dialog as a
%   whole, driven by a timer while it waits: a field greyed out by its
%   EnabledWhen, a preview left out of the options, a required field that
%   keeps the dialog open.
%
%   Run with: runtests('tests/DialogFieldsTest.m').
%
%   See also TRANSFORMOPTIONSDIALOG, DIALOGFIELDS.FIELD.

    properties (Access = private)
        Figure
    end

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            for p = {fullfile(root, 'src', 'Dialogs'), fullfile(root, 'src', 'Support'), ...
                     fullfile(root, 'src')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
        end
    end

    methods (TestMethodTeardown)
        function closeFigure(testCase)
            if ~isempty(testCase.Figure) && isvalid(testCase.Figure)
                delete(testCase.Figure);
            end
        end
    end

    methods (Test)
        % ---- what a plain default becomes ---------------------------------
        function aPlainDefaultBecomesTheFieldItAlwaysWas(testCase)
            testCase.verifyClass(DialogFields.fromDefault({'a', 'b'}), 'DialogFields.Choice');
            testCase.verifyClass(DialogFields.fromDefault(true), 'DialogFields.Checkbox');
            testCase.verifyClass(DialogFields.fromDefault(3), 'DialogFields.Number');
            testCase.verifyClass(DialogFields.fromDefault('text'), 'DialogFields.Text');
            testCase.verifyClass(DialogFields.fromDefault(multiSelectField({'a', 'b'}, {'a'})), ...
                'DialogFields.MultiSelect');
            field = DialogFields.Channels({'Fz', 'Cz'});
            testCase.verifySameHandle(DialogFields.fromDefault(field), field);
        end

        function aMistakeInAFieldIsNamedWhenItIsMade(testCase)
            testCase.verifyError(@() DialogFields.Choice({'a', 'b'}, 'a', 'Values', {'x'}), ...
                'Alakazam:DialogFields');
            testCase.verifyError(@() DialogFields.Plot('not a function'), 'Alakazam:DialogFields');
            testCase.verifyError(@() DialogFields.Checkbox(true, 'Colour', 'red'), 'Alakazam:DialogFields');
        end

        % ---- what each field hands back -----------------------------------
        function aChoiceShowsOneThingAndStoresAnother(testCase)
            field = DialogFields.Choice({'Spherical spline', 'Inverse distance'}, 'invdist', ...
                'Values', {'spherical', 'invdist'});
            testCase.build(field);

            testCase.verifyEqual(field.value(), 'invdist', 'Chosen by its stored value.');
            chosenByItem = DialogFields.Choice({'Spherical spline', 'Inverse distance'}, ...
                'Spherical spline', 'Values', {'spherical', 'invdist'});
            testCase.build(chosenByItem);
            testCase.verifyEqual(chosenByItem.value(), 'spherical', 'Or by what is shown.');
        end

        function aNumberKeepsToItsLimits(testCase)
            field = DialogFields.Number(5, 'Limits', [0 1]);
            testCase.build(field);

            testCase.verifyEqual(field.value(), 1, 'A stored value outside the limits is brought inside.');
        end

        function aStoredChannelNotInThisDatasetIsDropped(testCase)
        %ASTOREDCHANNELNOTINTHISDATASETISDROPPED  Stored by label, so a
        %   choice made on one montage replays on another; a label this one
        %   lacks is simply not chosen.
            field = DialogFields.Channels(testCase.montage(), {'Cz', 'Iz'});
            testCase.build(field);

            testCase.verifyEqual(field.value(), {'Cz'});
        end

        function scalpEegLeavesThePeripheralsOut(testCase)
            field = DialogFields.Channels(testCase.montage(), {});
            testCase.build(field);

            testCase.press('Scalp EEG');

            testCase.verifyEqual(field.value(), {'Fz', 'Cz', 'Pz'});
        end

        function allAndNoneSelectEverythingAndNothing(testCase)
            field = DialogFields.Channels(testCase.montage(), {'Cz'});
            testCase.build(field);

            testCase.press('All');
            testCase.verifyEqual(field.value(), {'Fz', 'Cz', 'Pz', 'VEOG', 'ECG'});
            testCase.press('None');
            testCase.verifyEqual(field.value(), {});
        end

        function aRequiredChannelListRefusesToBeEmpty(testCase)
            field = DialogFields.Channels(testCase.montage(), {}, 'Required', true);
            testCase.build(field);

            testCase.verifySubstring(field.validate(), 'at least one channel');
        end

        function aSingleChannelIsAName(testCase)
            field = DialogFields.Channels(testCase.montage(), 'Pz', 'Multiple', false);
            testCase.build(field);

            testCase.verifyEqual(field.value(), 'Pz');
        end

        function differenceBinsCanBeChosenOrLeftOut(testCase)
            bindesc = struct('label', {'Related', 'Unrelated', 'N400'}, ...
                'combo', {[], [], struct('bin', {4, 3}, 'coeff', {1, -1})});

            field = DialogFields.Bins(struct('bindesc', bindesc), {});
            testCase.build(field);
            testCase.press('Differences');
            testCase.verifyEqual(field.value(), {'N400'});

            ordinary = DialogFields.Bins(bindesc, {'N400', 'Related'}, 'Differences', false);
            testCase.verifyEqual(ordinary.Labels, {'Related', 'Unrelated'});
        end

        function aTableReadsEveryStoredShapeAndReturnsOne(testCase)
        %ATABLEREADSEVERYSTOREDSHAPEANDRETURNSONE  A JSON round trip hands
        %   rows back as a struct array; the table reads that and a cell of
        %   structs alike, fills a missing field with its column's default,
        %   and always returns a cell of scalar structs.
            columns = {struct('name', 'label', 'label', 'Row'), ...
                struct('name', 'freq', 'label', 'Hz', 'type', 'numeric', 'default', 10), ...
                struct('name', 'kind', 'type', {{'power', 'phase'}})};
            stored = struct('label', {'alpha', 'beta'}, 'freq', {10, 20});

            field = DialogFields.Table(columns, stored);
            testCase.build(field);
            rows = field.value();

            testCase.verifyClass(rows, 'cell');
            testCase.verifyEqual(numel(rows), 2);
            testCase.verifyEqual(rows{2}.freq, 20);
            testCase.verifyEqual(rows{1}.kind, 'power', 'A missing field takes its column''s default.');
        end

        function addAndRemoveChangeTheRows(testCase)
            columns = {struct('name', 'freq', 'type', 'numeric', 'default', 10)};
            field = DialogFields.Table(columns, {}, 'MinRows', 1);
            testCase.build(field);
            testCase.verifySubstring(field.validate(), 'at least 1 row');

            testCase.press('Add row');
            testCase.press('Add row');
            testCase.verifyEqual(cellfun(@(r) r.freq, field.value()), [10 10]);
            testCase.press('Remove row');
            testCase.verifyEqual(numel(field.value()), 1);
            testCase.verifyEmpty(field.validate());
        end

        function aTextAreaIsCheckedByItsOwnValidator(testCase)
            field = DialogFields.TextArea(sprintf('let A = Fz\nlet B = Qq'), ...
                'Validate', @(text) assert(~contains(text, 'Qq'), 'There is no channel Qq.'));
            testCase.build(field);

            testCase.verifyEqual(field.value(), sprintf('let A = Fz\nlet B = Qq'));
            testCase.verifyEqual(field.validate(), 'There is no channel Qq.');
        end

        function aPlotDrawsFromTheValuesAndSurvivesItsOwnMistakes(testCase)
            drawn = [];
            field = DialogFields.Plot(@(ax, values) draw(values));
            testCase.build(field);

            field.refresh(struct('Start', -100));
            testCase.verifyEqual(drawn, -100);
            testCase.verifyFalse(field.hasValue(), 'A preview adds nothing to the options.');

            broken = DialogFields.Plot(@(ax, values) error('no data to draw'));
            testCase.build(broken);
            broken.refresh(struct());
            testCase.verifySubstring(broken.Axes.Title.String, 'no data to draw');

            function draw(values)
                drawn = values.Start;
            end
        end

        % ---- the dialog ---------------------------------------------------
        function theDialogReturnsEveryValueButThePreview(testCase)
            testCase.requireFigures();
            timerObj = timer('StartDelay', 3, 'TimerFcn', @(~, ~) pressButton('Fields', 'OK'));
            cleanup = onCleanup(@() stopTimer(timerObj));
            start(timerObj);

            options = TransformOptionsDialog('title', 'Fields', ...
                {'Method'; 'Method'}, {'a', 'b'}, ...
                {'Count'; 'Count'}, DialogFields.Number(3, 'Integer', true), ...
                {'Channels'; 'Channels'}, DialogFields.Channels(testCase.montage(), {'Fz'}), ...
                {'Preview'; 'Preview'}, DialogFields.Plot(@(ax, v) plot(ax, 1:v.Count)));
            clear cleanup;

            testCase.assertNotEmpty(options);
            testCase.verifyEqual(options.Method, 'a');
            testCase.verifyEqual(options.Count, 3);
            testCase.verifyEqual(options.Channels, {'Fz'});
            testCase.verifyFalse(isfield(options, 'Preview'));
        end

        function aFieldThatDoesNotApplyIsGreyedOutAndNotChecked(testCase)
        %AFIELDTHATDOESNOTAPPLYISGREYEDOUTANDNOTCHECKED  A required list for
        %   a step that is switched off is not required.
            testCase.requireFigures();
            state = struct('enabled', []);
            timerObj = timer('StartDelay', 3, 'TimerFcn', @(~, ~) inspectThenOK());
            cleanup = onCleanup(@() stopTimer(timerObj));
            start(timerObj);

            options = TransformOptionsDialog('title', 'Fields', ...
                {'Use channels'; 'Use'}, false, ...
                {'Channels'; 'Channels'}, DialogFields.Channels(testCase.montage(), {}, ...
                    'Required', true, 'EnabledWhen', @(v) v.Use));
            clear cleanup;

            testCase.assertNotEmpty(options, 'OK should close: the empty list does not apply.');
            testCase.verifyEqual(state.enabled, matlab.lang.OnOffSwitchState('off'));

            function inspectThenOK()
                fig = findall(groot, 'Type', 'figure', 'Name', 'Fields');
                list = findall(fig, 'Type', 'uilistbox');
                state.enabled = list(1).Enable;
                pressButton('Fields', 'OK');
            end
        end

        function aRefusedValueKeepsTheDialogOpen(testCase)
            testCase.requireFigures();
            timerObj = timer('StartDelay', 3, 'TimerFcn', @(~, ~) okThenCancel());
            cleanup = onCleanup(@() stopTimer(timerObj));
            start(timerObj);

            options = TransformOptionsDialog('title', 'Fields', ...
                {'Channels'; 'Channels'}, DialogFields.Channels(testCase.montage(), {}, 'Required', true));
            clear cleanup;

            testCase.verifyEmpty(options, 'OK was refused, so only Cancel closed it.');

            function okThenCancel()
                pressButton('Fields', 'OK');
                pause(0.5);
                fig = findall(groot, 'Type', 'figure', 'Name', 'Fields');
                testCase.verifyNotEmpty(fig, 'The dialog should still be open after a refused OK.');
                pressButton('Fields', 'Cancel');
            end
        end
    end

    methods (Access = private)
        function requireFigures(testCase)
            try
                probe = uifigure('Visible', 'off');
                delete(probe);
            catch err
                testCase.assumeFail(['A uifigure could not be created here: ' err.message]);
            end
        end

        function build(testCase, field)
        %BUILD  Put FIELD into a hidden figure, as the dialog would.
            testCase.requireFigures();
            if isempty(testCase.Figure) || ~isvalid(testCase.Figure)
                testCase.Figure = uifigure('Visible', 'off', 'Position', [100 100 560 400]);
            end
            holder = uigridlayout(testCase.Figure, [1 1]);
            field.build(holder, @() []);
        end

        function press(testCase, text)
        %PRESS  The last-built button with TEXT, as a click would.
            buttons = findall(testCase.Figure, 'Type', 'uibutton', 'Text', text);
            testCase.assertNotEmpty(buttons, sprintf('No "%s" button.', text));
            buttons(1).ButtonPushedFcn(buttons(1), []);
        end
    end

    methods (Static, Access = private)
        function chanlocs = montage()
            chanlocs = struct('labels', {'Fz', 'Cz', 'Pz', 'VEOG', 'ECG'}, ...
                'type', {'EEG', 'EEG', 'EEG', 'EOG', 'ECG'});
        end
    end
end

% ======================================================================= %
function pressButton(figureName, text)
    fig = findall(groot, 'Type', 'figure', 'Name', figureName);
    button = findall(fig, 'Type', 'uibutton', 'Text', text);
    if ~isempty(button)
        button(1).ButtonPushedFcn(button(1), []);
    end
end

function stopTimer(t)
    try
        stop(t);
        delete(t);
    catch
        % Already gone.
    end
end
