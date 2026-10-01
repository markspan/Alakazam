classdef WarningStateGuardTest < matlab.unittest.TestCase
%WARNINGSTATEGUARDTEST  The two halves of keeping one test's warning state
%   from reaching another: EnabledWarningsFixture and WarningStateGuardPlugin.
%
%   The reported run had eight tests in five classes fail with
%   "did not issue any warnings", each at a warning() call the code still
%   reaches. Something earlier in the run had left every warning switched
%   off. The cases below pin that a test which names its warning is heard
%   regardless, that the fixture leaves the state as it found it, and that
%   the guard names a class that leaves warnings off and puts them back.
%
%   Every case restores the warning state it started with, so a defect in
%   either half fails here rather than in whatever class runs next.
%
%   Run with: runtests('tests/WarningStateGuardTest.m').
%
%   See also ENABLEDWARNINGSFIXTURE, WARNINGSTATEGUARDPLUGIN.

    properties (Constant, Access = private)
        % An identifier no code issues, so nothing else is affected by it.
        Checked = 'Alakazam:WarningStateGuardTest:checked'
    end

    methods (TestMethodSetup)
        function restoreTheWarningStateAfterwards(testCase)
            testCase.addTeardown(@warning, warning());
        end
    end

    methods (Test)
        % ---- EnabledWarningsFixture -----------------------------------------
        function aNamedWarningIsHeardWhileAllAreOff(testCase)
            warning('off', 'all');

            testCase.applyFixture(EnabledWarningsFixture(testCase.Checked));

            testCase.verifyWarning(@() warning(testCase.Checked, 'issued'), testCase.Checked);
        end

        function onlyTheNamedWarningsAreTurnedOn(testCase)
            warning('off', 'all');

            testCase.applyFixture(EnabledWarningsFixture(testCase.Checked));

            other = warning('query', 'Alakazam:WarningStateGuardTest:other');
            testCase.verifyEqual(other.state, 'off');
        end

        function teardownRestoresTheStateFromBefore(testCase)
            warning('off', 'all');
            before = warning();
            fixture = EnabledWarningsFixture(testCase.Checked);

            fixture.setup();
            during = warning('query', testCase.Checked);
            fixture.teardown();

            testCase.verifyEqual(during.state, 'on');
            testCase.verifyEmpty(WarningStateGuardPlugin.stateChanges(before, warning()));
        end

        % ---- WarningStateGuardPlugin: what counts as a change ---------------
        function allWarningsOffIsAChange(testCase)
            warning('on', 'all');
            before = warning();
            warning('off', 'all');

            testCase.verifyEqual(WarningStateGuardPlugin.stateChanges(before, warning()), ...
                "all: on to off");
        end

        function oneWarningOffIsAChange(testCase)
            warning('on', 'all');
            before = warning();
            warning('off', testCase.Checked);

            testCase.verifyEqual(WarningStateGuardPlugin.stateChanges(before, warning()), ...
                string(testCase.Checked) + ": on to off");
        end

        function anEntrySayingWhatAllSaysIsNoChange(testCase)
        %ANENTRYSAYINGWHATALLSAYSISNOCHANGE  A test that turns a warning off
        %   and restores it leaves an entry of its own behind, "on" under an
        %   "all" that is on. Every warning is still issued as before.
            warning('on', 'all');
            before = warning();
            previous = warning('off', testCase.Checked);
            warning(previous);

            testCase.verifyEmpty(WarningStateGuardPlugin.stateChanges(before, warning()));
        end

        function howWarningsArePrintedIsNoChange(testCase)
            warning('on', 'backtrace');
            before = warning();
            warning('off', 'backtrace');

            testCase.verifyEmpty(WarningStateGuardPlugin.stateChanges(before, warning()));
        end

        % ---- WarningStateGuardPlugin: in a run -------------------------------
        function aClassThatLeavesWarningsOffIsNamedAndUndone(testCase)
            warning('on', 'all');
            before = warning();
            folder = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture()).Folder;
            leaky = writeTestClass(folder, 'LeakyWarningsTest', 'warning(''off'', ''all'');');
            tidy = writeTestClass(folder, 'TidyWarningsTest', 'x = 1; %#ok<NASGU>');
            suite = [matlab.unittest.TestSuite.fromFile(leaky), ...
                     matlab.unittest.TestSuite.fromFile(tidy)];
            guard = WarningStateGuardPlugin();
            runner = matlab.unittest.TestRunner.withNoPlugins();
            runner.addPlugin(guard);

            printed = evalc('runner.run(suite);');

            testCase.verifyEqual([guard.Leaks.TestClass], "LeakyWarningsTest");
            testCase.verifyEqual(guard.Leaks(1).Changes, "all: on to off");
            testCase.verifyEmpty(WarningStateGuardPlugin.stateChanges(before, warning()), ...
                'The state from before the class is restored.');
            testCase.verifySubstring(printed, 'LeakyWarningsTest left the warnings changed (all: on to off)', ...
                'Said when it happens, so a run stopped early has still named it.');
            testCase.verifyFalse(contains(printed, 'TidyWarningsTest'));
        end
    end
end

% ======================================================================= %
function file = writeTestClass(folder, name, body)
%WRITETESTCLASS  A test class NAME in FOLDER with one test that runs BODY.
    file = fullfile(folder, [name '.m']);
    text = sprintf(['classdef %s < matlab.unittest.TestCase\n' ...
                    '    methods (Test)\n' ...
                    '        function theOnlyCase(~)\n' ...
                    '            %s\n' ...
                    '        end\n' ...
                    '    end\n' ...
                    'end\n'], name, body);
    fid = fopen(file, 'w');
    closer = onCleanup(@() fclose(fid)); %#ok<NASGU>  closes the file on return
    fprintf(fid, '%s', text);
end
