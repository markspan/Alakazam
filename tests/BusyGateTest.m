classdef BusyGateTest < matlab.unittest.TestCase
%BUSYGATETEST  Unit tests for src/Support/busyGate.m and the
%   TransTools.BusyGate wrapper transformations reach it through.
%
%   The behaviour under test exists because a transformation invoked
%   interactively opens its own options dialog INSIDE the feval the app
%   wrapped in a busy indicator. On a local MATLAB the two windows merely
%   coexist; in MATLAB Online the modal progress dialog covers the settings
%   and has to be dismissed by hand before anything can be entered. The
%   indicator therefore has to step aside while a dialog is up.
%
%   uiprogressdlg needs a visible figure and cannot be created under
%   MATLAB -batch in every configuration, so the tests that need a real
%   dialog are skipped rather than failed when that is the case; the
%   headless-guard tests, which are the ones protecting the rest of the
%   suite, always run.
%
%   Run with: runtests('tests/BusyGateTest.m').
%
%   See also BEGINBUSY, TRANSTOOLS.INITGUARD, TRANSFORMSETTINGS.

    properties
        Figure
    end

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'Support')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'src', 'Transformations')));
        end
    end

    methods (TestMethodTeardown)
        function closeFigure(testCase)
            busyGate('close');
            if ~isempty(testCase.Figure) && isvalid(testCase.Figure)
                delete(testCase.Figure);
            end
            testCase.Figure = [];
        end
    end

    methods (Test)
        function unarmedActionsAreHarmlessNoOps(testCase)
        %UNARMEDACTIONSAREHARMLESSNOOPS  InitGuard and TransformSettings.set
        %   call suspend/resume on every transformation run, including the
        %   many that never involve the app at all. Those calls must do
        %   nothing rather than error.
            busyGate('close');
            testCase.verifyFalse(busyGate('isArmed'));
            busyGate('suspend');
            busyGate('resume');
            busyGate('message', 'ignored');
            busyGate('progress', 0);
            busyGate('progress', 0.5);
            busyGate('progress', 1);
            testCase.verifyFalse(busyGate('isArmed'));
            testCase.verifyEmpty(busyGate('dialog'));
        end

        function theTransToolsWrapperIsSafeWithoutTheUiLayer(testCase)
        %THETRANSTOOLSWRAPPERISSAFEWITHOUTTHEUILAYER  Transformations must
        %   stay runnable with only src/Transformations on the path, which
        %   is how most of the test suite invokes them. The wrapper resolves
        %   busyGate once and quietly does nothing when it is absent.
            testCase.verifyWarningFree(@() TransTools.BusyGate('suspend'));
            testCase.verifyWarningFree(@() TransTools.BusyGate('resume'));
            testCase.verifyWarningFree(@() TransTools.BusyGate('progress', 0.5));
        end

        function anInteractiveInitGuardSuspendsAndSettingsSetRestores(testCase)
        %ANINTERACTIVEINITGUARDSUSPENDSANDSETTINGSSETRESTORES  The whole
        %   round trip, driven exactly as a transformation drives it.
            testCase.skipIfNoDialogs();
            busyGate('open', testCase.Figure, 'Running Something...');
            testCase.verifyTrue(busyGate('isArmed'));

            % A one-argument (interactive) call: about to open a dialog.
            [~, interactive] = TransTools.InitGuard(1, 'Alakazam:Test');
            testCase.verifyTrue(interactive);
            testCase.verifyFalse(testCase.dialogIsUp(), ...
                'The indicator should be down while the options dialog is up.');

            % Options accepted: real work starts, indicator comes back.
            TransformSettings.set('BusyGateTestTransform', struct('a', 1));
            testCase.verifyTrue(testCase.dialogIsUp(), ...
                'The indicator should be back once settings were accepted.');
        end

        function aReplayCallLeavesTheIndicatorUp(testCase)
        %AREPLAYCALLLEAVESTHEINDICATORUP  Replaying stored options (drag and
        %   drop, Apply to All, a cached recalculation) opens no dialog, so
        %   there is nothing to step aside for.
            testCase.skipIfNoDialogs();
            busyGate('open', testCase.Figure, 'Running Something...');

            [~, interactive] = TransTools.InitGuard(2, 'Alakazam:Test', struct('a', 1));

            testCase.verifyFalse(interactive);
            testCase.verifyTrue(testCase.dialogIsUp());
        end

        function closeDisarmsSoLaterCallsDoNothing(testCase)
        %CLOSEDISARMSSOLATERCALLSDONOTHING  recalculateTransformNode's own
        %   onCleanup restores the previous stored settings AFTER the busy
        %   indicator has been closed, which calls resume on a closed gate.
            testCase.skipIfNoDialogs();
            busyGate('open', testCase.Figure, 'Running Something...');
            busyGate('close');

            busyGate('resume');
            testCase.verifyFalse(busyGate('isArmed'));
            testCase.verifyFalse(testCase.dialogIsUp());
        end

        % ---- progress: the indicator as a filling bar ---------------------
        function progressFillsTheIndicatorAndOneHandsItBack(testCase)
        %PROGRESSFILLSTHEINDICATORANDONEHANDSITBACK  A transformation's loop
        %   reports through the wrapper, as Fourier, Welch, ComputeErsp and
        %   ComputeCoherenceMap do: 0 turns the spinner into an empty bar, a
        %   fraction fills it, and 1 gives the spinner and the app's own
        %   message back. The pauses outlast the redraw interval, so every
        %   report here is drawn.
            testCase.skipIfNoDialogs();
            busyGate('open', testCase.Figure, 'Running Something...');

            TransTools.BusyGate('progress', 0);
            dlg = busyGate('dialog');
            testCase.verifyEqual(string(dlg.Indeterminate), "off", 'Zero starts a bar.');
            testCase.verifyEqual(dlg.Value, 0);
            testCase.verifyEqual(string(dlg.ShowPercentage), "on");

            pause(0.2);
            TransTools.BusyGate('progress', 0.25);
            testCase.verifyEqual(dlg.Value, 0.25, 'AbsTol', 1e-12);

            TransTools.BusyGate('progress', 1);
            testCase.verifyEqual(string(dlg.Indeterminate), "on", 'One gives the spinner back.');
            testCase.verifyEqual(string(dlg.ShowPercentage), "off");
            testCase.verifyEqual(string(dlg.Message), "Running Something...");
        end

        function progressShowsTheTimeLeftOnceThereIsSomethingToGoOn(testCase)
        %PROGRESSSHOWSTHETIMELEFTONCETHEREISSOMETHINGTOGOON  Under the
        %   message, after a second of work, a second line estimates the time
        %   left at the rate so far: half done after about 1.2 s is about 1 s
        %   left.
            testCase.skipIfNoDialogs();
            busyGate('open', testCase.Figure, 'Running Something...');

            busyGate('progress', 0);
            dlg = busyGate('dialog');
            testCase.verifyEqual(string(dlg.Message), "Running Something...", ...
                'No estimate before there is anything to base it on.');

            pause(1.2);
            busyGate('progress', 0.5);
            % uiprogressdlg keeps a two-line message as one string with a
            % line break in it, whatever form it was given in.
            lines = splitlines(string(dlg.Message));
            testCase.verifyNumElements(lines, 2);
            testCase.verifyEqual(lines(1), "Running Something...");
            testCase.verifyMatches(lines(2), "^About \d+ s left$");
        end

        function progressWaitsWhileTheIndicatorIsSuspended(testCase)
        %PROGRESSWAITSWHILETHEINDICATORISSUSPENDED  With an options dialog up
        %   there is no indicator to fill, so a report does nothing; after
        %   resume the next report starts a fresh bar on the new spinner.
            testCase.skipIfNoDialogs();
            busyGate('open', testCase.Figure, 'Running Something...');
            busyGate('progress', 0);
            busyGate('suspend');

            testCase.verifyWarningFree(@() busyGate('progress', 0.5));
            testCase.verifyEmpty(busyGate('dialog'));

            busyGate('resume');
            busyGate('progress', 0.5);
            dlg = busyGate('dialog');
            testCase.verifyEqual(string(dlg.Indeterminate), "off");
            testCase.verifyEqual(dlg.Value, 0.5, 'AbsTol', 1e-12);
        end
    end

    % ==================================================================== %
    methods
        function tf = dialogIsUp(~)
        %DIALOGISUP  A ProgressDialog is not in the figure's HG tree, so it
        %   cannot be found with findall; ask the gate itself instead.
            tf = busyGate('isShowing');
        end

        function skipIfNoDialogs(testCase)
            try
                testCase.Figure = uifigure('Visible', 'on');
                dlg = uiprogressdlg(testCase.Figure, 'Message', 'probe', 'Indeterminate', 'on');
                close(dlg);
            catch
                testCase.assumeFail(['uiprogressdlg is unavailable in this MATLAB ' ...
                    'configuration (non-interactive), so the gate cannot be exercised here.']);
            end
        end
    end
end
